import XCTest
@testable import NoyauCR

/// Le tri des enregistrements et les délais de rétention.
///
/// Arbitrés le 19/08/2026. Le point que ces cas verrouillent : **l'âge ne dit
/// rien de la valeur d'un enregistrement sans compte rendu**. C'est sa durée
/// qui discrimine — une visioconférence de trente minutes oubliée est une
/// réunion à traiter, pas un déchet à effacer.
final class EnregistrementsTests: XCTestCase {

    private func orphelin(duree: TimeInterval, age: TimeInterval = 0,
                          extension ext: String = "caf") -> Enregistrements.Orphelin {
        Enregistrements.Orphelin(
            url: URL(fileURLWithPath: "/tmp/reunion.\(ext)"),
            date: Date().addingTimeInterval(-age),
            duree: duree, taille: 1_000_000)
    }

    func testUnEnregistrementCourtEstUnEssai() {
        XCTAssertTrue(orphelin(duree: 0).estUnEssai)
        XCTAssertTrue(orphelin(duree: 51).estUnEssai, "51 s : un des ratés réels du 19/08")
        XCTAssertTrue(orphelin(duree: 119).estUnEssai)
    }

    func testUneVraieReunionNEstPasUnEssai() {
        XCTAssertFalse(orphelin(duree: 1821).estUnEssai,
                       "trente minutes : la visio récupérée le 19/08")
        XCTAssertFalse(orphelin(duree: 120).estUnEssai)
    }

    func testCeQuOnProposeDeFaireDependDeLaDureePasDeLAge() {
        // Un essai vieux d'un jour et un essai vieux d'un an méritent le même
        // sort ; une réunion oubliée mérite d'être transcrite, quel que soit
        // son âge.
        XCTAssertTrue(orphelin(duree: 30, age: 3600).conseil.contains("essai"))
        XCTAssertTrue(orphelin(duree: 30, age: 400 * 24 * 3600).conseil.contains("essai"))
        XCTAssertTrue(orphelin(duree: 1800, age: 400 * 24 * 3600).conseil.contains("transcrire"))
    }

    // MARK: - La compression automatique

    func testUnEssaiNEstJamaisCompresseAutomatiquement() {
        // Occuper le processeur pour gagner quelques mégaoctets sur un fichier
        // destiné à être effacé n'aurait pas de sens.
        let essai = orphelin(duree: 30, age: 60 * 24 * 3600)
        XCTAssertTrue(essai.estUnEssai)
    }

    func testUnFichierDejaCompresseNEstPasRecompresse() {
        XCTAssertTrue(orphelin(duree: 1800, extension: "m4a").estCompresse)
        XCTAssertFalse(orphelin(duree: 1800, extension: "caf").estCompresse)
    }

    // MARK: - La rétention de l'audio rangé

    private func range(age: TimeInterval) -> Enregistrements.AudioRange {
        Enregistrements.AudioRange(
            url: URL(fileURLWithPath: "/tmp/audio.m4a"), projet: "MENUISERIES VIDAL",
            reunion: "Devis", date: Date().addingTimeInterval(-age), taille: 27_000_000)
    }

    func testLaSuggestionArriveAuBoutDeDouzeMois() {
        // Arbitré long à dessein : garder coûte quelques gigaoctets, supprimer
        // est irréversible, et un engagement pris en réunion ressort à
        // l'échéance d'un dossier.
        XCTAssertFalse(range(age: 300 * 24 * 3600).perime())
        XCTAssertTrue(range(age: 400 * 24 * 3600).perime())
    }

    func testUneReunionSansDateNEstJamaisProposeeALaSuppression() {
        // Un dossier renommé à la main perd sa date : dans le doute, on garde.
        let sansDate = Enregistrements.AudioRange(
            url: URL(fileURLWithPath: "/tmp/audio.m4a"), projet: "X",
            reunion: "Y", date: nil, taille: 1)
        XCTAssertFalse(sansDate.perime())
    }

    // MARK: - Dire les choses

    func testLesDureesSeLisent() {
        XCTAssertEqual(Enregistrements.dureeLisible(0), "vide")
        XCTAssertEqual(Enregistrements.dureeLisible(51), "51 s")
        XCTAssertEqual(Enregistrements.dureeLisible(1821), "30 min")
        XCTAssertEqual(Enregistrements.dureeLisible(3600), "1 h")
        XCTAssertEqual(Enregistrements.dureeLisible(5400), "1 h 30")
    }
}
