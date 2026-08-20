import XCTest
@testable import NoyauCR

/// La recomposition d'un transcript à partir des deux pistes d'une
/// visioconférence. Ce n'est pas de l'audio : c'est de la logique pure, donc
/// entièrement vérifiable sans micro.
final class FusionPistesTests: XCTestCase {

    private func s(_ texte: String, _ debut: Double, _ duree: Double = 0.4)
        -> Transcription.Segment {
        Transcription.Segment(texte: texte, debut: debut, duree: duree)
    }

    // MARK: - Regroupement en tours de parole

    func testLesMotsSuccessifsFormentUnSeulTour() {
        // La reconnaissance rend un segment par mot : sans regroupement, le
        // transcript arriverait mot à mot et serait illisible.
        let tours = FusionPistes.regrouper(
            [s("Bonjour", 0), s("Nicolas", 0.5), s("comment", 1.0), s("vas-tu", 1.5)],
            locuteur: "Moi")
        XCTAssertEqual(tours.count, 1)
        XCTAssertEqual(tours[0].texte, "Bonjour Nicolas comment vas-tu")
        XCTAssertEqual(tours[0].debut, 0)
    }

    func testUnSilenceSuffisantOuvreUnNouveauTour() {
        let tours = FusionPistes.regrouper(
            [s("Bonjour", 0), s("Alors", 10), s("commençons", 10.5)],
            locuteur: "Moi")
        XCTAssertEqual(tours.count, 2)
        XCTAssertEqual(tours[1].texte, "Alors commençons")
        XCTAssertEqual(tours[1].debut, 10)
    }

    func testUnSilenceCourtNeCoupePasLaPhrase() {
        let tours = FusionPistes.regrouper([s("Oui", 0), s("bien sûr", 1.6)],
                                           locuteur: "Moi")
        XCTAssertEqual(tours.count, 1, "1,2 s de silence ne sépare pas deux tours")
    }

    func testLesSegmentsVidesSontIgnores() {
        let tours = FusionPistes.regrouper([s("", 0), s("   ", 1), s("Bonjour", 2)],
                                           locuteur: "A")
        XCTAssertEqual(tours.count, 1)
        XCTAssertEqual(tours[0].texte, "Bonjour")
    }

    func testUnePisteVideNeProduitAucunTour() {
        XCTAssertTrue(FusionPistes.regrouper([], locuteur: "A").isEmpty)
    }

    // MARK: - Ponctuation

    func testLaPonctuationSeRecolleAuMotPrecedent() {
        // La reconnaissance rend « bonjour » puis « , » comme deux segments.
        XCTAssertEqual(FusionPistes.assembler(["Bonjour", ",", "Nicolas", "."]),
                       "Bonjour, Nicolas.")
        // Espace INSÉCABLE avant le point d'interrogation, comme le veut la
        // typographie française.
        XCTAssertEqual(FusionPistes.assembler(["C'est", "vrai", "?"]), "C'est vrai\u{A0}?")
        XCTAssertEqual(FusionPistes.assembler(["Attention", ":", "voici"]),
                       "Attention\u{A0}: voici")
    }

    func testLesGuillemetsFrancaisPrennentLeursEspaces() {
        XCTAssertEqual(FusionPistes.assembler(["\u{AB}", "bonjour", "\u{BB}"]),
                       "\u{AB}\u{A0}bonjour\u{A0}\u{BB}")
    }

    func testLApostropheColleAuMotSuivant() {
        XCTAssertEqual(FusionPistes.assembler(["l'", "atelier"]), "l'atelier")
    }

    // MARK: - Entrelacement des deux pistes

    func testLesDeuxPistesSEntrelacentDansLOrdreDeLaConversation() {
        let transcript = FusionPistes.fusionner(
            moi: [s("Bonjour", 0), s("Nicolas", 0.4)],
            lesAutres: [s("Salut", 5), s("Camille", 5.4)],
            nomMoi: "Moi", nomAutres: "Les autres participants")

        let lignes = transcript.components(separatedBy: "\n\n")
        XCTAssertEqual(lignes.count, 2)
        XCTAssertTrue(lignes[0].contains("Moi"))
        XCTAssertTrue(lignes[0].contains("Bonjour Nicolas"))
        XCTAssertTrue(lignes[1].contains("Les autres participants"))
        XCTAssertTrue(lignes[1].contains("Salut Camille"))
    }

    func testUneReponseQuiPrecedeEstPlaceeAvant() {
        // L'ordre suit l'horodatage, pas la piste : c'est tout l'intérêt.
        let transcript = FusionPistes.fusionner(
            moi: [s("D'accord", 30)],
            lesAutres: [s("Le tarif est de 850 euros", 10)], nomMoi: "Moi")
        let premier = transcript.components(separatedBy: "\n\n")[0]
        XCTAssertTrue(premier.contains("850"), "le propos de 10 s doit précéder celui de 30 s")
    }

    func testLHorodatageEstEnMinutesEtSecondes() {
        let transcript = FusionPistes.fusionner(moi: [s("Bonjour", 125)], lesAutres: [], nomMoi: "Moi")
        XCTAssertTrue(transcript.hasPrefix("02:05 "), "obtenu : \(transcript.prefix(10))")
    }

    func testLeSilenceDUnCoteNeLaissePasDeTrou() {
        let transcript = FusionPistes.fusionner(moi: [], lesAutres: [s("Bonjour", 0)], nomMoi: "Moi")
        XCTAssertEqual(transcript.components(separatedBy: "\n\n").count, 1)
        XCTAssertTrue(transcript.contains("Les autres participants"))
    }

    // MARK: - En-tête

    func testLEnTeteDitDOuVientLAttribution() {
        // Relu dans six mois, le transcript doit expliquer lui-même pourquoi
        // les noms sont fiables.
        let entete = FusionPistes.enTete(reunion: "Point MenuiserieVidal", quand: "14 août 2026", nomMoi: "Moi")
        XCTAssertTrue(entete.contains("exacte par construction"))
        XCTAssertTrue(entete.contains("ne distingue pas les autres entre eux"))
        XCTAssertTrue(entete.contains("Point MenuiserieVidal"))
    }
}
