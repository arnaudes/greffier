import XCTest
@testable import NoyauCR

/// Installer une version plus récente sans manipuler un fichier.
///
/// L'application se contentait de prévenir : il fallait ensuite télécharger,
/// décompresser, glisser le bundle par-dessus l'ancien, relancer — et **rien à
/// la fin ne disait que c'était fait**. C'est là qu'on renonce à se mettre à
/// jour, et qu'une correction reste sur l'étagère.
final class InstallationMiseAJourTests: XCTestCase {

    /// Une version sans application jointe ne peut pas s'installer : il faut le
    /// dire en français, pas échouer en silence.
    func testUnePublicationSansFichierJointLeDitClairement() async {
        let publication = VerificationVersion.Publication(
            version: "2026.09.01.01",
            page: URL(string: "https://example.invalid/releases")!)
        do {
            _ = try await InstallationMiseAJour.preparer(publication)
            XCTFail("une publication sans fichier joint ne peut pas se préparer")
        } catch let erreur as InstallationMiseAJour.Erreur {
            XCTAssertEqual(erreur, .aucunFichierJoint)
            XCTAssertTrue(erreur.errorDescription!.contains("recompiler"),
                          "le message doit dire ce qu'il reste à faire")
        } catch {
            XCTFail("erreur inattendue : \(error)")
        }
    }

    /// Rien n'attend tant que rien n'a été préparé.
    func testAucuneVersionNAttendAuDepart() {
        XCTAssertNil(InstallationMiseAJour.dejaPrete(pour: "version-\(UUID().uuidString)"))
    }

    /// Garder les archives de trois versions passées occuperait le disque pour
    /// rien : chaque préparation efface les précédentes.
    func testLesVersionsPrecedentesSontOubliees() throws {
        let racine = InstallationMiseAJour.dossierDAttente
        let ancienne = "essai-ancienne-\(UUID().uuidString)"
        let gardee = "essai-gardee-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: racine.appendingPathComponent(gardee))
        }
        for nom in [ancienne, gardee] {
            try FileManager.default.createDirectory(
                at: racine.appendingPathComponent(nom), withIntermediateDirectories: true)
        }

        InstallationMiseAJour.oublierLesAutres(sauf: gardee)

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: racine.appendingPathComponent(ancienne).path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: racine.appendingPathComponent(gardee).path))
    }

    /// Les archives vivent dans les caches : si le système fait le ménage, on
    /// retéléchargera. Encombrer les Documents de l'utilisateur serait pire.
    func testLesArchivesNEncombrentPasLesDocuments() {
        let chemin = InstallationMiseAJour.dossierDAttente.path
        XCTAssertTrue(chemin.contains("Caches"))
        XCTAssertFalse(chemin.contains("Documents"))
    }

    /// Chaque échec doit se dire en français, sans jargon ni code d'erreur.
    func testChaqueEchecSExpliqueEnFrancais() {
        let cas: [InstallationMiseAJour.Erreur] = [
            .aucunFichierJoint, .telechargementEchoue("délai dépassé"),
            .archiveIllisible, .bundleAbsent, .signatureInvalide,
            .installationEchouee("droits refusés"),
        ]
        for erreur in cas {
            let message = erreur.errorDescription ?? ""
            XCTAssertGreaterThan(message.count, 25, "\(erreur) : message trop bref")
            XCTAssertFalse(message.contains("Error"), "\(erreur) : jargon")
        }
    }
}

extension InstallationMiseAJour.Erreur: Equatable {
    public static func == (a: Self, b: Self) -> Bool {
        a.errorDescription == b.errorDescription
    }
}
