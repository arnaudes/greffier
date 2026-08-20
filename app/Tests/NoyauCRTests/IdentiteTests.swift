import XCTest
@testable import NoyauCR

/// L'identité de qui rédige.
///
/// Elle était écrite dans le code : le prompt nommait une personne et sa
/// société, et le filtrage des participants cherchait un prénom précis. Chez
/// quelqu'un d'autre, ses propres propos auraient été attribués aux autres.
final class IdentiteTests: XCTestCase {

    private let camille = Identite(
        nom: "Camille Roy", fonction: "gérante", societe: "Atelier Roy",
        activite: "L'Atelier Roy fabrique des menuiseries sur mesure.")

    func testSeReconnaitreParmiLesParticipants() {
        XCTAssertTrue(camille.estMoi("Camille Roy"))
        XCTAssertTrue(camille.estMoi("camille roy"))
        XCTAssertTrue(camille.estMoi("Camille"), "le prénom seul suffit dans une invitation")
        XCTAssertTrue(camille.estMoi("Roy, Camille"))
    }

    func testNePasSeConfondreAvecUnAutre() {
        XCTAssertFalse(camille.estMoi("Nicolas Berthier"))
        XCTAssertFalse(camille.estMoi("Nicolas"))
    }

    func testSansNomOnNeReconnaitPersonne() {
        // Le pire des cas serait de tout attribuer à un nom vide.
        XCTAssertFalse(Identite().estMoi("Camille Roy"))
        XCTAssertFalse(Identite().estMoi(""))
    }

    func testLeNomSuffitAtravailler() {
        // Bloquer sur un formulaire incomplet coûterait plus qu'un compte rendu
        // perfectible.
        XCTAssertTrue(Identite(nom: "Camille Roy").utilisable)
        XCTAssertFalse(Identite(fonction: "gérante", societe: "Atelier Roy").utilisable)
    }

    func testCeQuiManqueEstDitEnFrancais() {
        let manques = Identite().incomplet
        XCTAssertTrue(manques.contains("votre nom"))
        XCTAssertTrue(manques.contains("ce que fait votre société"))
        XCTAssertTrue(camille.incomplet.isEmpty)
    }

    func testLaPresentationNInventeRienQuandToutEstVide() {
        // Mieux vaut un prompt impersonnel qu'une identité par défaut.
        let vide = Identite().presentation
        XCTAssertEqual(vide, "Tu rédiges des comptes rendus de réunion.")
    }

    func testLaPresentationPorteLActivite() {
        XCTAssertTrue(camille.presentation.contains("Camille Roy"))
        XCTAssertTrue(camille.presentation.contains("Atelier Roy"))
        XCTAssertTrue(camille.presentation.contains("menuiseries"))
    }

    func testLaSignatureSePasseDesChampsVides() {
        XCTAssertEqual(Identite(nom: "Camille Roy").signature, "Camille Roy")
        XCTAssertEqual(camille.signature, "Camille Roy — gérante — Atelier Roy")
    }

    func testElleSeRelitTelleQuEcrite() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("identite-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try camille.enregistrer(vers: url)
        XCTAssertEqual(Identite.charger(depuis: url), camille)
    }

    func testUnFichierAbsentDonneUneIdentiteVideEtPasUneErreur() {
        // Au premier lancement, il n'y a rien à lire : l'application doit
        // s'ouvrir quand même.
        let absent = URL(fileURLWithPath: "/tmp/n-existe-pas-\(UUID().uuidString).json")
        XCTAssertEqual(Identite.charger(depuis: absent), Identite())
    }
}
