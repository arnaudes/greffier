import XCTest
@testable import NoyauCR

/// Le classement des documents d'une réunion.
///
/// Motivé le 19/08/2026 : deux réunions suffisaient à mettre neuf fichiers à
/// plat dans un dossier client, dont deux artefacts HTML, tandis que l'audio
/// vivait ailleurs sous un nom qui ne disait ni le client ni le sujet.
final class RangementTests: XCTestCase {

    private func date(_ jour: Int, _ mois: Int, _ an: Int) -> Date {
        var c = DateComponents()
        c.year = an; c.month = mois; c.day = jour; c.hour = 15
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - Le nom du dossier

    func testLeNomPorteLaDatePuisLObjet() {
        XCTAssertEqual(
            Rangement.nomDeReunion(date: date(19, 8, 2026), objet: "Devis et subvention"),
            "2026-08-19 — Devis et subvention")
    }

    func testSansObjetIlNeResteQueLaDate() {
        XCTAssertEqual(Rangement.nomDeReunion(date: date(19, 8, 2026), objet: "  "),
                       "2026-08-19")
    }

    func testLOrdreAlphabetiqueEstLOrdreDuTemps() {
        // C'est la raison du format : arbitré d'abord en JJ-MM-AAAA, puis
        // repris le 19/08/2026 parce que le Finder y plaçait septembre avant
        // août.
        let aout = Rangement.nomDeReunion(date: date(19, 8, 2026), objet: "A")
        let septembre = Rangement.nomDeReunion(date: date(1, 9, 2026), objet: "B")
        XCTAssertTrue(aout < septembre, "\(aout) devrait précéder \(septembre)")
    }

    func testLaDateSeRelitDepuisLeNom() {
        let nom = Rangement.nomDeReunion(date: date(19, 8, 2026), objet: "Devis")
        let relue = Rangement.dateDe(dossier: nom)
        XCTAssertNotNil(relue)
        XCTAssertEqual(Rangement.dateDossier(relue!), "2026-08-19")
    }

    func testUnDossierSansDateNeCassePasLaLecture() {
        XCTAssertNil(Rangement.dateDe(dossier: "Ancienne réunion"))
    }

    // MARK: - Ce qu'un nom de dossier ne peut pas contenir

    func testLaBarreObliqueEstRetiree() {
        // Elle sépare les dossiers : la laisser passer casserait l'écriture
        // sans un mot d'explication.
        let nom = Rangement.nomDeReunion(date: date(19, 8, 2026),
                                         objet: "Devis 2026/2027 : phase 2")
        XCTAssertFalse(nom.dropFirst(10).contains("/"))
        XCTAssertFalse(nom.contains(":"))
        XCTAssertTrue(nom.contains("Devis 2026 2027"))
    }

    func testUnIntituleTresLongEstCoupe() {
        let long = String(repeating: "réunion ", count: 30)
        let nom = Rangement.nomDeReunion(date: date(19, 8, 2026), objet: long)
        XCTAssertLessThanOrEqual(nom.count, 100)
        XCTAssertTrue(nom.hasSuffix("…"))
    }

    func testLesRetoursALaLigneNeCassentPasLeNom() {
        let nom = Rangement.nomDeReunion(date: date(19, 8, 2026), objet: "Devis\nphase 2")
        XCTAssertFalse(nom.contains("\n"))
        XCTAssertTrue(nom.contains("Devis phase 2"))
    }

    // MARK: - Les chemins

    func testTousLesDocumentsViventDansLeDossierDeLaReunion() {
        let racine = URL(fileURLWithPath: "/tmp/greffier-essai")
        let reunion = Rangement.dossierReunion(racine: racine, projet: "MENUISERIES VIDAL",
                                               date: date(19, 8, 2026), objet: "Devis")
        XCTAssertEqual(reunion.path,
                       "/tmp/greffier-essai/comptes-rendus/MENUISERIES VIDAL/2026-08-19 — Devis")
        for fichier in Rangement.Fichier.allCases {
            XCTAssertEqual(
                Rangement.chemin(fichier, dans: reunion).deletingLastPathComponent().path,
                reunion.path, "\(fichier.rawValue) doit rester avec sa réunion")
        }
    }

    func testCeQuiNeSOuvrePasAlaMainEstAPart() {
        let reunion = URL(fileURLWithPath: "/tmp/greffier-essai/2026-08-19")
        XCTAssertEqual(Rangement.dossierFabrication(dans: reunion).lastPathComponent,
                       "Fabrication")
    }

    // MARK: - Relire ce qui est rangé

    func testLesReunionsSontRenduesDeLaPlusRecenteALaPlusAncienne() throws {
        let racine = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("greffier-rangement-\(UUID().uuidString)")
        let fm = FileManager.default
        defer { try? fm.removeItem(at: racine) }

        for (jour, objet) in [(14, "Première"), (19, "Dernière"), (15, "Milieu")] {
            let dossier = Rangement.dossierReunion(racine: racine, projet: "Client",
                                                   date: date(jour, 8, 2026), objet: objet)
            try fm.createDirectory(at: dossier, withIntermediateDirectories: true)
            try "# Compte rendu".write(to: Rangement.chemin(.compteRendu, dans: dossier),
                                       atomically: true, encoding: .utf8)
        }
        // Un dossier sans compte rendu : présent, mais pas compté.
        try fm.createDirectory(at: Rangement.dossierReunion(
            racine: racine, projet: "Client", date: date(20, 8, 2026), objet: "Sans CR"),
            withIntermediateDirectories: true)

        let reunions = Rangement.reunions(racine: racine, projet: "Client")
        XCTAssertEqual(reunions.map(\.objet), ["Sans CR", "Dernière", "Milieu", "Première"])
        XCTAssertEqual(Rangement.nombreDeComptesRendus(racine: racine, projet: "Client"), 3)
        XCTAssertNil(reunions.first { $0.objet == "Sans CR" }?.compteRendu)
    }
}

/// Ce qui protège les documents déjà écrits.
///
/// Trouvé au troisième audit, le 20/08/2026. Deux défauts qui ne se seraient
/// manifestés qu'en détruisant du travail.
final class RangementProtectionTests: XCTestCase {

    private func date(_ jour: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 8; c.day = jour; c.hour = 14
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private var racine: URL!

    override func setUp() {
        racine = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("greffier-protection-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: racine) }

    // MARK: - Le nom du client

    func testUneBarreObliqueDansLeNomDuClientNeCreePasDeSousDossier() {
        // « Client / Filiale » créait deux niveaux, et le compte rendu
        // disparaissait de la liste.
        let dossier = Rangement.dossierProjet(racine: racine, projet: "Client / Filiale")
        XCTAssertEqual(dossier.lastPathComponent, "Client Filiale")
        XCTAssertEqual(dossier.deletingLastPathComponent().lastPathComponent, "comptes-rendus")
    }

    func testUnNomQuiRemonteLArborescenceEstNeutralise() {
        // Le pire des cas : écrire hors du dossier de travail.
        let dossier = Rangement.dossierProjet(racine: racine, projet: "..")
        XCTAssertEqual(dossier.lastPathComponent, "Sans dossier")
        XCTAssertTrue(dossier.path.contains("comptes-rendus"))
    }

    func testUnNomVideDonneUnDossierNomme() {
        XCTAssertEqual(Rangement.dossierProjet(racine: racine, projet: "  ").lastPathComponent,
                       "Sans dossier")
    }

    // MARK: - Deux réunions le même jour

    func testDeuxReunionsSansTitreLeMemeJourNeSEcrasentPas() throws {
        let fm = FileManager.default
        let premier = Rangement.dossierLibre(racine: racine, projet: "Client",
                                             date: date(20), objet: "")
        try fm.createDirectory(at: premier, withIntermediateDirectories: true)
        try "# Premier".write(to: Rangement.chemin(.compteRendu, dans: premier),
                              atomically: true, encoding: .utf8)

        let second = Rangement.dossierLibre(racine: racine, projet: "Client",
                                            date: date(20), objet: "")
        XCTAssertNotEqual(second.path, premier.path,
                          "le second compte rendu écraserait le premier")
        XCTAssertTrue(second.lastPathComponent.hasSuffix("(2)"))

        // Et le premier est intact.
        let relu = try String(contentsOf: Rangement.chemin(.compteRendu, dans: premier),
                              encoding: .utf8)
        XCTAssertEqual(relu, "# Premier")
    }

    func testUnDossierCommenceMaisSansCompteRenduEstReutilise() throws {
        // Enregistrer deux fois la même réunion ne doit pas créer un doublon :
        // c'est le cas courant, quand on corrige et qu'on ré-enregistre.
        let fm = FileManager.default
        let premier = Rangement.dossierLibre(racine: racine, projet: "Client",
                                             date: date(20), objet: "Devis")
        try fm.createDirectory(at: premier, withIntermediateDirectories: true)
        let second = Rangement.dossierLibre(racine: racine, projet: "Client",
                                            date: date(20), objet: "Devis")
        XCTAssertEqual(second.path, premier.path)
    }
}
