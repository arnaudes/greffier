import XCTest
@testable import NoyauCR

/// La lecture des réponses de Claude. Ces cas ne sont pas théoriques : un
/// modèle encadre régulièrement son JSON d'une phrase de politesse ou d'un
/// bloc de code, malgré la consigne. Faire échouer tout un compte rendu pour
/// cela serait absurde.
final class LectureReponsesTests: XCTestCase {

    func testUnJSONEncadreDeTexteResteLisible() throws {
        let brut = """
            Bien sûr, voici les questions :
            {"questions":[{"id":"q1","famille":"mots-douteux","question":"Deploio ?",\
            "extrait":"dans Deploio","type":"oui-non","saisie_libre":true,\
            "enrichit_lexique":true}]}
            J'espère que cela convient.
            """
        let questions = try ChaineCR.decoderQuestions(brut)
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions[0].famille, .motsDouteux)
    }

    func testUneAccoladeDansUneChaineNeCoupePasLObjet() {
        // Le piège : une accolade à l'intérieur d'un texte de question.
        let json = #"{"a":"un { piège }","b":2}"#
        XCTAssertEqual(ChaineCR.extraireObjetJSON("blabla " + json + " suite"), json)
    }

    func testUneAccoladeEchappeeNeTrompePas() {
        let json = #"{"a":"guillemet \" puis }","b":1}"#
        XCTAssertEqual(ChaineCR.extraireObjetJSON(json), json)
    }

    func testUnTexteSansJSONEstSignaleCommeIllisible() {
        XCTAssertNil(ChaineCR.extraireObjetJSON("Je n'ai pas de question."))
        XCTAssertThrowsError(try ChaineCR.decoderQuestions("Je n'ai pas de question."))
    }

    func testUneListeVideSignifieQuIlNYAPlusDeQuestion() throws {
        XCTAssertTrue(try ChaineCR.decoderQuestions(#"{"questions":[]}"#).isEmpty)
    }

    func testLeBlocDeCodeAutourDUnDocumentEstRetire() {
        let avec = "```markdown\n# Compte rendu\n\nDu texte.\n```"
        XCTAssertEqual(ChaineCR.nettoyerMarkdown(avec), "# Compte rendu\n\nDu texte.")
    }

    func testUnMarkdownSansBlocDeCodeNEstPasAbime() {
        let brut = "# Compte rendu\n\nDu texte avec ``` au milieu."
        XCTAssertEqual(ChaineCR.nettoyerMarkdown(brut), brut)
    }
}

/// Ce que l'application dit à Claude avant qu'il ne lise le transcript.
final class PromptsTests: XCTestCase {

    private func contexte(perimetre: Perimetre = .touteLaReunion,
                          entree: TypeEntree = .collage) -> ContexteReunion {
        ContexteReunion(
            titre: "Point avec Camille - Menuiseries Vidal",
            quand: "vendredi 14 août 2026, 9 h 59 – 10 h 46",
            format: "visioconférence",
            participants: ["Nicolas Berthier", "Camille Roy"],
            projet: "MenuiserieVidal", perimetre: perimetre, entree: entree)
    }

    func testUnPerimetreRestreintEstEnonceCommeUneContrainte() {
        let m = Prompts.messageInitial(
            contexte: contexte(perimetre: .sujet("uniquement la partie MenuiserieVidal")),
            transcript: "…", lexique: [], comptesRendusAnterieurs: [])
        XCTAssertTrue(m.contains("uniquement la partie MenuiserieVidal"))
        XCTAssertTrue(m.contains("hors sujet"))
    }

    func testLaDoublePisteDispenseDeDemanderLAttribution() {
        let doublePiste = Prompts.messageInitial(
            contexte: contexte(entree: .doublePiste),
            transcript: "…", lexique: [], comptesRendusAnterieurs: [])
        XCTAssertTrue(doublePiste.contains("exacte par construction"))

        let collage = Prompts.messageInitial(
            contexte: contexte(entree: .collage),
            transcript: "…", lexique: [], comptesRendusAnterieurs: [])
        XCTAssertTrue(collage.contains("AUCUNE attribution"))
    }

    func testLeLexiqueEstTransmisAvecSesVariantesEtSaNote() {
        let m = Prompts.messageInitial(
            contexte: contexte(), transcript: "…",
            lexique: [EntreeLexique(terme: "Deployo", variantes: ["Deploio"],
                                    categorie: .outil, note: "Plateforme de déploiement")],
            comptesRendusAnterieurs: [])
        XCTAssertTrue(m.contains("**Deployo**"))
        XCTAssertTrue(m.contains("déjà transcrit à tort : Deploio"))
        XCTAssertTrue(m.contains("Plateforme de déploiement"))
        XCTAssertTrue(m.contains("jamais à redemander"))
    }

    func testUnLexiqueVideEstDitPlutotQueTu() {
        // Une section vide sans explication se lit comme un oubli.
        let m = Prompts.messageInitial(contexte: contexte(), transcript: "…",
                                       lexique: [], comptesRendusAnterieurs: [])
        XCTAssertTrue(m.contains("Le lexique est vide"))
    }

    func testLesComptesRendusAnterieursSontFournisAvecLeurRaison() {
        let m = Prompts.messageInitial(
            contexte: contexte(), transcript: "…", lexique: [],
            comptesRendusAnterieurs: ["# Compte rendu du 11 août"])
        XCTAssertTrue(m.contains("# Compte rendu du 11 août"))
        XCTAssertTrue(m.contains("contradiction"))
    }

    func testLInstructionDAnalyseCouvreLesHuitFamilles() {
        let i = Prompts.instructionAnalyse
        for famille in ["participants", "qui-a-dit-quoi", "mots-douteux", "dates-relatives",
                        "decision-ou-piste", "actions-porteurs", "chiffres"] {
            XCTAssertTrue(i.contains(famille), "famille absente de l'instruction : \(famille)")
        }
        // La septième ne se pose qu'à la dérivation de l'email.
        XCTAssertTrue(i.contains("ne se pose qu'au moment de dériver"))
    }

    func testUneReponseManquanteNAutorisePasClaudeATrancher() {
        let q = Question(id: "q1", famille: .chiffres, question: "Confirmez-vous ?",
                         extrait: "…", horodatage: nil, occurrences: nil, type: .ouiNon,
                         options: nil, saisieLibre: true, enrichitLexique: false,
                         justification: nil)
        let m = Prompts.messageReponses([Reponse(id: "q1", reponse: nil)], questions: [q])
        XCTAssertTrue(m.contains("sans réponse"))
        XCTAssertTrue(m.contains("ne doit pas être tranchée à ma place"))
        XCTAssertTrue(m.contains("Points ouverts"))
    }

    func testLeGabaritDeRedactionInterditLOrdreChronologique() {
        let i = Prompts.instructionRedaction(contexte: contexte())
        XCTAssertTrue(i.contains("jamais par ordre chronologique"))
        XCTAssertTrue(i.contains("MenuiserieVidal"))
        XCTAssertTrue(i.contains("ne pas diffuser au client"))
    }

    func testLEmailEstUnEmailCompletEtNonUnCompteRenduRaccourci() {
        let i = Prompts.instructionEmail(destinataire: "Paul Marchand", entreprise: "MenuiserieVidal")
        XCTAssertTrue(i.contains("pas un compte rendu raccourci"))
        XCTAssertTrue(i.contains("Paul Marchand"))
        XCTAssertTrue(i.contains("Aucun tableau"))
        XCTAssertTrue(i.contains("Le filtrage retire ce qui est interne, il n'embellit rien"))
    }

    func testLePromptSystemePorteLaRegleAbsolue() {
        let prompt = Prompts.systeme()
        XCTAssertTrue(prompt.contains("NE JAMAIS INVENTER"))
        XCTAssertTrue(prompt.contains("soit c'est dit, soit tu le demandes"))
        XCTAssertTrue(prompt.contains("Il n'y a pas de quota"))
    }

    func testLeParametrageNeFaitJamaisDisparaitreLesRegles() {
        // Le point qui décide de tout : une charte personnelle s'ajoute aux
        // garanties du produit, elle ne peut pas les remplacer.
        let identite = Identite(nom: "Camille Roy", fonction: "gérante",
                                societe: "Atelier Roy",
                                activite: "L'Atelier Roy fabrique des menuiseries.",
                                charte: "Sois très bref. Tranche quand tu hésites.")
        let prompt = Prompts.systeme(identite: identite)

        XCTAssertTrue(prompt.contains("NE JAMAIS INVENTER"))
        XCTAssertTrue(prompt.contains("Camille Roy"))
        XCTAssertTrue(prompt.contains("menuiseries"))
        XCTAssertTrue(prompt.contains("Tranche quand tu hésites"))

        // Et surtout : la charte est placée AVANT les règles, jamais après.
        let placeCharte = prompt.range(of: "Tranche quand tu hésites")!.lowerBound
        let placeRegles = prompt.range(of: "NE JAMAIS INVENTER")!.lowerBound
        XCTAssertTrue(placeCharte < placeRegles,
                      "une charte placée après les règles pourrait les défaire")
        XCTAssertTrue(prompt.contains("ne peuvent jamais"),
                      "le prompt doit dire explicitement que la charte ne prime pas")
    }

    func testSansIdentiteLePromptNInventeAucunNom() {
        // Mieux vaut un prompt impersonnel qu'une identité par défaut : ce
        // fichier partira sur un dépôt public.
        let prompt = Prompts.systeme()
        XCTAssertFalse(prompt.contains("Tu assistes"),
                       "sans identité, personne ne doit être nommé")
        XCTAssertTrue(prompt.contains("Tu rédiges des comptes rendus"))
    }
}
