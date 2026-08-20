import XCTest
@testable import NoyauCR

/// Les conditions nécessaires pour qu'une réunion devienne un compte rendu.
///
/// Chacune correspond à un échec réellement subi : le micro refusé sans message
/// le 17/08/2026, la dictée désactivée le même jour, Claude introuvable le
/// 19/08 — celui-là après trente minutes de réunion enregistrée et transcrite —
/// et la reconnaissance vocale jamais demandée le 20/08, sans que rien ne le
/// signale.
final class PrerequisTests: XCTestCase {

    private func etat(_ manquantes: Prerequis.Condition...) -> Prerequis {
        var etats: [Prerequis.Condition: Prerequis.Etat] = [:]
        for condition in Prerequis.Condition.allCases {
            etats[condition] = manquantes.contains(condition) ? .refuse : .bon
        }
        return Prerequis(etats: etats)
    }

    func testToutVaBienQuandRienNeManque() {
        XCTAssertTrue(etat().toutVaBien)
        XCTAssertEqual(etat().gravite, .bien)
        XCTAssertTrue(etat().resume.contains("Prêt"))
    }

    // MARK: - Ce qui ferait perdre une réunion

    func testUnMicroRefuseEstBloquant() {
        XCTAssertEqual(etat(.micro).gravite, .bloquant)
        XCTAssertFalse(etat(.micro).peutEnregistrer)
    }

    func testLaDicteeDesactiveeEstBloquanteAussi() {
        // Elle laisse enregistrer, mais la transcription échouera : la réunion
        // serait captée pour rien. C'est ce qui est arrivé le 17/08.
        XCTAssertFalse(etat(.dictee).peutEnregistrer)
    }

    func testLaReconnaissanceVocaleEstBloquante() {
        // Défaut constaté le 20/08 : elle n'avait jamais été demandée, et
        // aucun écran ne le disait.
        XCTAssertFalse(etat(.reconnaissance).peutEnregistrer)
        XCTAssertEqual(etat(.reconnaissance).gravite, .bloquant)
    }

    func testUnDossierInaccessibleEstBloquant() {
        XCTAssertFalse(etat(.dossier).peutEnregistrer)
        XCTAssertTrue(Prerequis.Condition.dossier.consequence.contains("plus grave"))
    }

    // MARK: - Ce qui se rattrape après coup

    func testClaudeIntrouvableNEmpechePasDEnregistrer() {
        // Une réunion captée et transcrite peut attendre que Claude soit
        // retrouvé. L'inverse n'est pas vrai : une réunion non captée est
        // perdue.
        XCTAssertTrue(etat(.claude).peutEnregistrer)
        XCTAssertEqual(etat(.claude).gravite, .attention)
    }

    func testLEcranEtChromeEtLeCalendrierNeFontPasPerdreDeReunion() {
        for condition in [Prerequis.Condition.ecran, .chrome, .calendrier] {
            XCTAssertFalse(condition.faitPerdreLaReunion, "\(condition) mal classée")
            XCTAssertTrue(etat(condition).peutEnregistrer)
        }
    }

    // MARK: - Ce qui est dit à l'utilisateur

    func testLeResumeAnnonceLeManqueLePlusGrave() {
        // Le calendrier ne doit pas éclipser un micro refusé.
        let deux = etat(.calendrier, .micro)
        XCTAssertTrue(deux.resume.contains("Micro"))
    }

    func testChaqueConditionDitCeQuElleEmpeche() {
        // Le message doit dire la conséquence, pas l'état technique.
        for condition in Prerequis.Condition.allCases {
            XCTAssertGreaterThan(condition.consequence.count, 20, "\(condition) : trop bref")
            XCTAssertGreaterThan(condition.role.count, 15, "\(condition) : rôle non expliqué")
            XCTAssertFalse(condition.titre.isEmpty)
        }
    }

    func testUnEtatNonRenseigneEstAdemander() {
        // Au premier lancement, rien n'est connu : mieux vaut « jamais
        // demandée » qu'un faux « en place ».
        let vide = Prerequis(etats: [:])
        XCTAssertEqual(vide.etat(.micro), .aDemander)
        XCTAssertFalse(vide.toutVaBien)
    }

    func testLesAutorisationsQuiSeDemandentOntUnCheminDeReglages() {
        for condition in [Prerequis.Condition.micro, .reconnaissance, .ecran, .calendrier] {
            XCTAssertNotNil(Prerequis.reglagesSysteme(condition),
                            "\(condition) doit pouvoir s'ouvrir dans les Réglages Système")
        }
    }
}

/// Ce que Claude reçoit doit rester borné.
///
/// Constaté au second audit, le 20/08/2026 : **tous** les comptes rendus d'un
/// dossier étaient envoyés à chaque analyse. À la soixantième réunion d'un
/// client, cela aurait fait près d'un mégaoctet — au-delà de ce qu'un modèle
/// accepte, et coûteux bien avant. Le panneau de droite, lui, n'en montrait que
/// trois : l'écart entre ce qu'on voyait et ce qui partait était invisible.
final class ContexteEnvoyeTests: XCTestCase {

    func testLeMessageInitialResteRaisonnableAvecTroisComptesRendus() {
        let contexte = ContexteReunion(
            titre: "Point mensuel", quand: "20 août 2026", format: "Visioconférence",
            participants: ["Camille Roy"], projet: "Menuiseries Vidal", entree: .collage)
        let unCR = String(repeating: "Contenu du compte rendu. ", count: 600)  // ~15 Ko

        let message = Prompts.messageInitial(
            contexte: contexte,
            transcript: String(repeating: "mot ", count: 5_000),
            lexique: [],
            comptesRendusAnterieurs: Array(repeating: unCR, count: 3))

        // Trois comptes rendus, un transcript d'une heure : on doit rester très
        // en deçà de ce qu'un modèle accepte.
        XCTAssertLessThan(message.utf8.count, 200_000)
        XCTAssertTrue(message.contains("Comptes rendus antérieurs"))
    }

    func testSansComptesRendusAnterieursLaSectionDisparait() {
        let contexte = ContexteReunion(
            titre: "Première réunion", quand: "20 août 2026", format: "Présentiel",
            participants: [], projet: "Nouveau client", entree: .collage)
        let message = Prompts.messageInitial(contexte: contexte, transcript: "Bonjour.",
                                             lexique: [], comptesRendusAnterieurs: [])
        XCTAssertFalse(message.contains("Comptes rendus antérieurs"),
                       "une section vide n'apprend rien et coûte des jetons")
    }
}
