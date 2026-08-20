import XCTest
@testable import NoyauCR

/// Les cas de ces tests ne sont pas inventés : ce sont les erreurs réellement
/// produites par un moteur de transcription sur la réunion MenuiserieVidal du
/// 14 août 2026, relevées dans docs/BANC-ESSAI-temps1-MenuiserieVidal.md.
final class LexiqueTests: XCTestCase {

    private func lexique() -> Lexique {
        Lexique(entrees: [
            EntreeLexique(terme: "Deployo", variantes: ["Deploio"], categorie: .outil,
                          note: "Plateforme de déploiement du serveur."),
            EntreeLexique(terme: "Halle Nord", categorie: .lieu),
            EntreeLexique(terme: "Atelier Roy", categorie: .entreprise),
            EntreeLexique(terme: "FONDERIE LAMBERT", categorie: .entreprise),
            EntreeLexique(terme: "Ferrolab", categorie: .outil),
        ])
    }

    // MARK: - Normalisation

    func testNormalisationPlieAccentsCasseEtPonctuation() {
        XCTAssertEqual(Lexique.normaliser("L'Atelier Roy"), "l atelier roy")
        XCTAssertEqual(Lexique.normaliser("Halle Nordî"), "halle nordi")
        XCTAssertEqual(Lexique.normaliser("  re-pull, "), "re pull")
    }

    // MARK: - Passe exacte

    func testVarianteConnueEstReconnue() {
        // « Deploio » est une faute déjà rencontrée : elle doit être retenue
        // sans qu'aucune correspondance approchée n'ait à s'en mêler.
        let retenues = lexique().selectionner(
            pourTranscript: "un volume de stockage sera créé dans Deploio pour les fichiers")
        XCTAssertEqual(retenues.map(\.terme), ["Deployo"])
    }

    func testCorrespondanceExacteNeDeclenchePasSurUnFragment() {
        // « Ferrolab » ne doit pas être retenu parce que le transcript contient
        // « fer » : la comparaison porte sur des mots entiers.
        let retenues = lexique().selectionner(pourTranscript: "il regarde le fer du profilé")
        XCTAssertTrue(retenues.isEmpty)
    }

    // MARK: - Passe approchée

    func testFauteInediteEstRattrapee() {
        // « hale nord » n'est pas dans les variantes : c'est exactement la
        // situation que la passe approchée doit couvrir.
        let retenues = lexique().selectionner(
            pourTranscript: "et après partenariat un peu spécifique, hale nord par exemple")
        XCTAssertEqual(retenues.map(\.terme), ["Halle Nord"])
    }

    func testMotCoupeEnDeuxEstRattrape() {
        // « fonderie-lambert » : le trait d'union devient un espace à la
        // normalisation, et la fenêtre de deux mots retrouve le terme.
        let retenues = lexique().selectionner(
            pourTranscript: "ça pourrait être intéressant pour fonderie-lambert, pour leur ERP")
        XCTAssertEqual(retenues.map(\.terme), ["FONDERIE LAMBERT"])
    }

    /// Limite mesurée le 14 août 2026, consignée plutôt que contournée.
    ///
    /// « Atelillier Rois » pour *Atelier Roy* est le genre de faute que produit
    /// un transcript, mais elle est trop déformée pour le seuil par défaut. La sélection
    /// échoue donc ici — du côté prudent : le coût est une question déjà
    /// réglée qu'on repose, jamais une invention. Et la fusion referme le trou
    /// dès que l'utilisateur répond (spécification § 8.3).
    ///
    /// Baisser le seuil pour rattraper ce cas ferait rentrer bien d'autres
    /// entrées sans rapport : c'est un arbitrage, pas un défaut à corriger.
    func testUneFauteTropDeformeeEchappeAuSeuilParDefaut() {
        let transcript = "C'est chez Atelillier Rois."
        XCTAssertTrue(lexique().selectionner(pourTranscript: transcript).isEmpty)

        // Et la preuve que c'est bien une affaire de seuil, non de mécanisme.
        let large = lexique().selectionner(pourTranscript: transcript, seuil: 0.60)
        XCTAssertEqual(large.map(\.terme), ["Atelier Roy"])
    }

    func testTranscriptSansAucunTermeNeRetientRien() {
        let retenues = lexique().selectionner(
            pourTranscript: "on parle de fenêtres en bois et de délais de livraison très courts")
        XCTAssertTrue(retenues.isEmpty, "retenues à tort : \(retenues.map(\.terme))")
    }

    // MARK: - Termes du dossier

    func testTermeDuDossierEstRetenuMemeAbsentDuTranscript() {
        let retenues = lexique().selectionner(pourTranscript: "rien à voir",
                                              termesDuDossier: ["FONDERIE LAMBERT"])
        XCTAssertEqual(retenues.map(\.terme), ["FONDERIE LAMBERT"])
    }

    // MARK: - Fusion

    func testIntegrerFusionneAuLieuDeDupliquer() {
        var l = lexique()
        let neuf = l.integrer(EntreeLexique(terme: "Deployo", variantes: ["Déploillo"],
                                            categorie: .outil, note: "autre note"))
        XCTAssertFalse(neuf, "un terme déjà connu ne doit pas créer d'entrée")
        XCTAssertEqual(l.entrees.count, 5)
        let deployo = l.entrees.first { $0.terme == "Deployo" }!
        XCTAssertEqual(deployo.variantes, ["Deploio", "Déploillo"])
        XCTAssertEqual(deployo.note, "Plateforme de déploiement du serveur.",
                       "une note déjà validée ne doit jamais être écrasée")
    }

    func testIntegrerNeRepetePasUneVarianteConnue() {
        var l = lexique()
        l.integrer(EntreeLexique(terme: "Deployo", variantes: ["deploio"], categorie: .outil))
        XCTAssertEqual(l.entrees.first { $0.terme == "Deployo" }!.variantes, ["Deploio"])
    }

    func testIntegrerCreeUneEntreeNeuve() {
        var l = lexique()
        XCTAssertTrue(l.integrer(EntreeLexique(terme: "Trameo", categorie: .outil)))
        XCTAssertEqual(l.entrees.count, 6)
    }

    // MARK: - Persistance

    func testEnregistrerPuisRelireConserveTout() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lexique-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try lexique().enregistrer(vers: url)
        let relu = try Lexique.charger(depuis: url)
        XCTAssertEqual(relu.entrees, lexique().entrees)

        // La clé destinée au lecteur humain doit survivre à l'enregistrement.
        let brut = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(brut.contains("_apropos"))
    }
}

/// L'ordre d'affichage des questions (spécification § 3.4).
final class OrdreQuestionsTests: XCTestCase {

    private func question(_ id: String, _ type: TypeQuestion, _ options: Int,
                          _ famille: Famille = .motsDouteux,
                          _ horodatage: String? = nil) -> Question {
        Question(id: id, famille: famille, question: "?", extrait: "…",
                 horodatage: horodatage, occurrences: nil, type: type,
                 options: options > 0 ? Array(repeating: "o", count: options) : nil,
                 saisieLibre: true, enrichitLexique: false, justification: nil)
    }

    func testLesQuestionsAUnClicPassentEnPremier() {
        let liste = ListeQuestions(questions: [
            question("libre", .texte, 0),
            question("multiple", .choixMultiple, 4),
            question("quatre", .choixUnique, 4),
            question("deux", .choixUnique, 2),
            question("ouinon", .ouiNon, 0),
        ])
        XCTAssertEqual(liste.ordonnees.map(\.id), ["deux", "ouinon", "quatre", "multiple", "libre"])
    }

    func testACoutEgalLaFamillePuisLeTranscriptDepartagent() {
        let liste = ListeQuestions(questions: [
            question("mot-tard", .ouiNon, 0, .motsDouteux, "30:15"),
            question("mot-tot", .ouiNon, 0, .motsDouteux, "02:01"),
            question("attribution", .ouiNon, 0, .quiADitQuoi, "45:00"),
        ])
        XCTAssertEqual(liste.ordonnees.map(\.id), ["attribution", "mot-tot", "mot-tard"])
    }

    func testUnHorodatageAbsentNeRemontePasEnTete() {
        let liste = ListeQuestions(questions: [
            question("sans", .ouiNon, 0, .motsDouteux, nil),
            question("avec", .ouiNon, 0, .motsDouteux, "40:00"),
        ])
        XCTAssertEqual(liste.ordonnees.map(\.id), ["avec", "sans"])
    }
}
