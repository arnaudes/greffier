import XCTest
@testable import NoyauCR

/// Le tout premier lancement, sur une machine où rien n'existe encore.
///
/// **Ce cas n'avait jamais été éprouvé.** L'application a toujours démarré sur
/// une machine où le dossier, le lexique et l'identité existaient déjà. C'est
/// pourtant l'état que rencontreront ceux à qui elle sera confiée, et le seul
/// moment où une erreur les fait renoncer.
final class PremierLancementTests: XCTestCase {

    private var vierge: URL!

    override func setUp() {
        vierge = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("greffier-vierge-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: vierge, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: vierge) }

    func testRienNeCasseQuandToutEstVide() {
        XCTAssertTrue(Rangement.reunions(racine: vierge, projet: "Inconnu").isEmpty)
        XCTAssertEqual(Rangement.nombreDeComptesRendus(racine: vierge, projet: "Inconnu"), 0)
        XCTAssertTrue(Recherche.toutes(racine: vierge).isEmpty)
        XCTAssertTrue(Recherche.chercher("quoi que ce soit", racine: vierge).isEmpty)
        XCTAssertTrue(Enregistrements.orphelins(racine: vierge).isEmpty)
        XCTAssertTrue(Enregistrements.rangés(racine: vierge).isEmpty)
        XCTAssertTrue(Enregistrements.aCompresser(racine: vierge).isEmpty)
    }

    func testUneIdentiteAbsenteNEmpechePasDeDemarrer() {
        let identite = Identite.charger(depuis: vierge.appendingPathComponent("identite.json"))
        XCTAssertEqual(identite, Identite())
        XCTAssertFalse(identite.utilisable)
        // Et ce qui manque est dit en français, pas en noms de champs.
        XCTAssertTrue(identite.incomplet.contains("votre nom"))
    }

    func testLeLexiqueAbsentNEstPasUnLexiqueCorrompu() {
        // La distinction décide s'il faut mettre le fichier de côté : au premier
        // lancement, il n'y a rien à sauver.
        let url = vierge.appendingPathComponent("lexique/lexique.json")
        XCTAssertFalse(Lexique.estCorrompu(url))
        XCTAssertNil(Lexique.mettreDeCote(url))
    }

    func testLePromptResteImpersonnelEtCompletSansIdentite() {
        let prompt = Prompts.systeme()
        XCTAssertFalse(prompt.contains("Tu assistes"))
        // Les garanties du produit doivent y être, identité ou pas.
        XCTAssertTrue(prompt.contains("NE JAMAIS INVENTER"))
        XCTAssertTrue(prompt.contains("TU POSES AUTANT DE QUESTIONS"))
    }

    func testUnPremierCompteRenduSEcritDansUnDossierNeuf() throws {
        var c = DateComponents(); c.year = 2026; c.month = 8; c.day = 20
        let date = Calendar(identifier: .gregorian).date(from: c)!
        let dossier = Rangement.dossierLibre(racine: vierge, projet: "Premier client",
                                             date: date, objet: "Première réunion")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        try "# Premier".write(to: Rangement.chemin(.compteRendu, dans: dossier),
                              atomically: true, encoding: .utf8)

        // Et il se retrouve immédiatement.
        XCTAssertEqual(Recherche.toutes(racine: vierge).count, 1)
        XCTAssertEqual(Recherche.chercher("Premier client", racine: vierge).count, 1)
    }
}
