import XCTest
@testable import NoyauCR

/// Retrouver une réunion parmi toutes celles qu'on a tenues.
///
/// Classer ne suffit pas : on ne se souvient pas toujours du client, mais on se
/// souvient d'un montant ou d'une phrase dite en séance.
final class RechercheTests: XCTestCase {

    private var racine: URL!

    override func setUpWithError() throws {
        racine = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("greffier-recherche-\(UUID().uuidString)")
        try poser(projet: "Menuiseries Vidal", jour: 19, objet: "Devis et subvention",
                  texte: "# Compte rendu\n\nLe devis s'élève à 18 200 euros hors taxes.\n"
                       + "Nicolas Berthier déposera le dossier avant jeudi.")
        try poser(projet: "Fonderie Lambert", jour: 12, objet: "Cadrage ERP",
                  texte: "# Compte rendu\n\nLe périmètre couvre la production et la qualité.")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: racine)
    }

    private func poser(projet: String, jour: Int, objet: String, texte: String) throws {
        var c = DateComponents(); c.year = 2026; c.month = 8; c.day = jour; c.hour = 10
        let date = Calendar(identifier: .gregorian).date(from: c)!
        let dossier = Rangement.dossierReunion(racine: racine, projet: projet,
                                               date: date, objet: objet)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        try texte.write(to: Rangement.chemin(.compteRendu, dans: dossier),
                        atomically: true, encoding: .utf8)
    }

    // MARK: - Ce qu'on cherche

    func testOnRetrouveParLeNomDuClient() {
        let trouves = Recherche.chercher("Vidal", racine: racine)
        XCTAssertEqual(trouves.count, 1)
        XCTAssertEqual(trouves.first?.projet, "Menuiseries Vidal")
        XCTAssertTrue(trouves.first?.dansLeTitre ?? false)
    }

    func testOnRetrouveParLObjetDeLaReunion() {
        XCTAssertEqual(Recherche.chercher("subvention", racine: racine).count, 1)
    }

    func testOnRetrouveParUnMotDitEnSeance() {
        // Le cas qui justifie la recherche : on se souvient du montant, pas du
        // client ni de la date.
        let trouves = Recherche.chercher("18 200", racine: racine)
        XCTAssertEqual(trouves.count, 1)
        XCTAssertNotNil(trouves.first?.extrait, "l'extrait doit montrer pourquoi")
        XCTAssertTrue(trouves.first!.extrait!.contains("18 200"))
    }

    func testLaCasseEtLesAccentsSontIgnores() {
        XCTAssertEqual(Recherche.chercher("BERTHIER", racine: racine).count, 1)
        XCTAssertEqual(Recherche.chercher("perimetre", racine: racine).count, 1)
    }

    func testUnMotAbsentNeRendRien() {
        XCTAssertTrue(Recherche.chercher("hélicoptère", racine: racine).isEmpty)
    }

    func testUneDemandeTropCourteNeCherchePas() {
        // Une lettre ramènerait tout : ce n'est pas une recherche.
        XCTAssertTrue(Recherche.chercher("a", racine: racine).isEmpty)
        XCTAssertTrue(Recherche.chercher(" ", racine: racine).isEmpty)
    }

    // MARK: - Tout lister

    func testToutesLesReunionsDeLaPlusRecenteALaPlusAncienne() {
        let toutes = Recherche.toutes(racine: racine)
        XCTAssertEqual(toutes.count, 2)
        XCTAssertEqual(toutes.first?.projet, "Menuiseries Vidal", "le 19 précède le 12")
    }

    func testUneReunionSansCompteRenduNApparaitPas() throws {
        // Un dossier créé mais abandonné avant la rédaction : il n'a rien à
        // faire dans la liste de ce qu'on peut relire.
        var c = DateComponents(); c.year = 2026; c.month = 8; c.day = 20
        let date = Calendar(identifier: .gregorian).date(from: c)!
        try FileManager.default.createDirectory(
            at: Rangement.dossierReunion(racine: racine, projet: "Menuiseries Vidal",
                                         date: date, objet: "Abandonnée"),
            withIntermediateDirectories: true)
        XCTAssertEqual(Recherche.toutes(racine: racine).count, 2)
    }

    // MARK: - L'extrait

    func testLExtraitEstCadreAutourDuTerme() {
        let texte = String(repeating: "avant ", count: 40) + "TROUVAILLE"
            + String(repeating: " après", count: 40)
        let extrait = Recherche.extraitAutour(de: "trouvaille", dans: texte)
        XCTAssertNotNil(extrait)
        XCTAssertLessThan(extrait!.count, 140, "un extrait doit tenir sur deux lignes")
        XCTAssertTrue(extrait!.hasPrefix("…"), "le début coupé doit se voir")
    }

    func testUnTermeAbsentNaPasDExtrait() {
        XCTAssertNil(Recherche.extraitAutour(de: "absent", dans: "un texte quelconque"))
    }
}
