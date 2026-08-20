import XCTest
@testable import NoyauCR

/// Savoir qu'une version plus récente existe.
///
/// Le point de conception que ces cas verrouillent : **ce n'est pas un envoi de
/// code qui prévient, c'est une version publiée**. Et la comparaison des CalVer
/// se fait en nombres, jamais en texte.
final class VerificationVersionTests: XCTestCase {

    // MARK: - Comparer

    func testUneVersionPlusRecenteEstReconnue() {
        XCTAssertTrue(VerificationVersion.estAnterieure("2026.08.20.01", "2026.08.21.01"))
        XCTAssertTrue(VerificationVersion.estAnterieure("2026.08.20.01", "2026.09.01.01"))
        XCTAssertTrue(VerificationVersion.estAnterieure("2026.12.31.01", "2027.01.01.01"))
    }

    func testLaMemeVersionNeDeclencheRien() {
        XCTAssertFalse(VerificationVersion.estAnterieure("2026.08.20.01", "2026.08.20.01"))
    }

    func testUneVersionPlusAncienneNeDeclencheRien() {
        // Le cas de celui qui compile lui-même une version de travail : il ne
        // doit pas être invité à « revenir en arrière ».
        XCTAssertFalse(VerificationVersion.estAnterieure("2026.08.21.01", "2026.08.20.01"))
    }

    func testLaComparaisonSeFaitEnNombresPasEnTexte() {
        // « 2026.08.20.9 » précède « 2026.08.20.10 » : un tri alphabétique
        // aurait dit l'inverse, et la dixième livraison du jour serait passée
        // inaperçue.
        XCTAssertTrue(VerificationVersion.estAnterieure("2026.08.20.9", "2026.08.20.10"))
        XCTAssertFalse(VerificationVersion.estAnterieure("2026.08.20.10", "2026.08.20.9"))
    }

    func testLeVDUsageEstToleré() {
        // Étiqueter « v2026.08.21.01 » est répandu : l'ignorer ferait croire à
        // une version inconnue.
        XCTAssertTrue(VerificationVersion.estAnterieure("2026.08.20.01", "v2026.08.21.01"))
        XCTAssertFalse(VerificationVersion.estAnterieure("v2026.08.21.01", "2026.08.21.01"))
    }

    // MARK: - Lire la réponse de GitHub

    private func reponse(tag: String, avecFichier: Bool = false) -> Data {
        let joints = avecFichier
            ? #"[{"browser_download_url": "https://github.com/x/y/releases/download/t/Greffier.zip"}]"#
            : "[]"
        return Data("""
            {"tag_name": "\(tag)",
             "html_url": "https://github.com/arnaudes/greffier/releases/tag/\(tag)",
             "body": "Ce qui change.",
             "assets": \(joints)}
            """.utf8)
    }

    func testUnePublicationSeLit() throws {
        let publication = try VerificationVersion.lire(reponse(tag: "2026.08.21.01"))
        XCTAssertEqual(publication?.version, "2026.08.21.01")
        XCTAssertEqual(publication?.notes, "Ce qui change.")
        XCTAssertNil(publication?.telechargement, "aucun fichier joint dans ce cas")
    }

    func testLeFichierAInstallerEstRepere() throws {
        let publication = try VerificationVersion.lire(reponse(tag: "2026.08.21.01",
                                                               avecFichier: true))
        XCTAssertNotNil(publication?.telechargement,
                        "sans fichier joint, il faudrait recompiler soi-même")
    }

    func testUneReponseIncompréhensibleEstUneErreurPasUnPlantage() {
        XCTAssertThrowsError(try VerificationVersion.lire(Data("pas du json".utf8)))
    }

    // MARK: - Décider de prévenir

    private let publication = VerificationVersion.Publication(
        version: "2026.08.21.01",
        page: URL(string: "https://github.com/arnaudes/greffier/releases")!)

    func testOnPrevientQuandUneVersionPlusRecenteExiste() {
        XCTAssertTrue(VerificationVersion.doitPrevenir(
            publication, versionActuelle: "2026.08.20.01",
            prevenir: true, versionEcartee: nil))
    }

    func testOnSeTaitQuandLUtilisateurNeVeutPasEtrePrevenu() {
        XCTAssertFalse(VerificationVersion.doitPrevenir(
            publication, versionActuelle: "2026.08.20.01",
            prevenir: false, versionEcartee: nil))
    }

    func testUneVersionEcarteeNeRevientPas() {
        // Écarter une mise à jour et la voir reparaître le lendemain, c'est le
        // meilleur moyen de faire désactiver la vérification.
        XCTAssertFalse(VerificationVersion.doitPrevenir(
            publication, versionActuelle: "2026.08.20.01",
            prevenir: true, versionEcartee: "2026.08.21.01"))
    }

    func testMaisLaSuivanteEstBienSignalee() {
        let suivante = VerificationVersion.Publication(
            version: "2026.08.22.01", page: publication.page)
        XCTAssertTrue(VerificationVersion.doitPrevenir(
            suivante, versionActuelle: "2026.08.20.01",
            prevenir: true, versionEcartee: "2026.08.21.01"))
    }

    func testAucunePublicationNeDeclencheRien() {
        // Un dépôt neuf n'a publié aucune version : c'est normal, pas une panne.
        XCTAssertFalse(VerificationVersion.doitPrevenir(
            nil, versionActuelle: "2026.08.20.01", prevenir: true, versionEcartee: nil))
    }

    // MARK: - Ne regarder qu'une fois par jour

    func testOnNeRegardePasDeuxFoisLeMemeJour() {
        let ilYaUneHeure = Date().addingTimeInterval(-3600)
        XCTAssertTrue(VerificationVersion.aDejaRegarde(ilYaUneHeure))
    }

    func testOnRegardeANouveauLeLendemain() {
        let ilYaDeuxJours = Date().addingTimeInterval(-48 * 3600)
        XCTAssertFalse(VerificationVersion.aDejaRegarde(ilYaDeuxJours))
        XCTAssertFalse(VerificationVersion.aDejaRegarde(nil), "au premier lancement")
    }
}
