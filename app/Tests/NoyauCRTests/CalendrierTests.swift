import XCTest
@testable import NoyauCR

/// La détection du mode de capture. Les cas ne sont pas inventés : ce sont les
/// événements de calendrier ordinaires, relevés pendant la conception.
final class CalendrierTests: XCTestCase {

    // MARK: - Ce qu'on propose, et ce qu'on ne propose pas

    func testUnBlocSansParticipantNEstPasUneReunion() {
        // Une journée entière bloquée, 08:45–18:30, zéro participant. C'est le cas qui
        // a fait retenir le nombre de participants plutôt qu'un plafond de
        // durée : neuf heures durant, l'outil ne doit rien proposer.
        XCTAssertEqual(Calendrier.modePropose(nombreDeParticipants: 0, enVisio: false), .aucun)
        XCTAssertEqual(Calendrier.modePropose(nombreDeParticipants: 0, enVisio: true), .aucun)
    }

    func testDesParticipantsEtUnLienDeVisioDonnentLaDoublePiste() {
        XCTAssertEqual(Calendrier.modePropose(nombreDeParticipants: 2, enVisio: true), .visio)
    }

    func testDesParticipantsSansVisioDonnentLePresentiel() {
        XCTAssertEqual(Calendrier.modePropose(nombreDeParticipants: 3, enVisio: false),
                       .presentiel)
    }

    func testUneReunionAUnSeulParticipantResteUneReunion() {
        // Un tête-à-tête chez un client n'a qu'un participant en face.
        XCTAssertEqual(Calendrier.modePropose(nombreDeParticipants: 1, enVisio: false),
                       .presentiel)
    }

    // MARK: - Reconnaître une visioconférence

    func testUneInvitationTeamsEstReconnue() {
        // Formulation exacte que pose une invitation Teams en français.
        XCTAssertTrue(Calendrier.estUneVisio(notes: nil, lieu: "Réunion Microsoft Teams",
                                             url: nil))
        XCTAssertTrue(Calendrier.estUneVisio(
            notes: "Cliquez ici pour rejoindre : https://teams.microsoft.com/l/meetup-join/…",
            lieu: nil, url: nil))
    }

    func testLeLienPeutSeTrouverDansLUrlDeLEvenement() {
        XCTAssertTrue(Calendrier.estUneVisio(
            notes: nil, lieu: nil, url: URL(string: "https://teams.microsoft.com/l/meetup-join/x")))
    }

    func testLesAutresOutilsDeVisioSontReconnusAussi() {
        for lien in ["https://zoom.us/j/123", "https://meet.google.com/abc-defg-hij"] {
            XCTAssertTrue(Calendrier.estUneVisio(notes: lien, lieu: nil, url: nil),
                          "non reconnu : \(lien)")
        }
    }

    func testUneReunionSurSiteNEstPasPriseP0urUneVisio() {
        XCTAssertFalse(Calendrier.estUneVisio(
            notes: "Rendez-vous à l'accueil", lieu: "MenuiserieVidal, sur site", url: nil))
    }

    func testUnEvenementSansAucuneInformationNEstPasUneVisio() {
        XCTAssertFalse(Calendrier.estUneVisio(notes: nil, lieu: nil, url: nil))
    }

    // MARK: - Liste blanche

    func testLaListeBlancheNeRetientQueLeCalendrierProfessionnel() {
        // Sans elle, l'outil proposerait d'enregistrer l'Assomption : un Mac
        // porte souvent douze calendriers, dont anniversaires et jours fériés.
        let calendrier = Calendrier()
        XCTAssertEqual(calendrier.calendriersRetenus, ["Calendrier"])
        XCTAssertFalse(calendrier.calendriersRetenus.contains("Jours fériés en France"))
        XCTAssertFalse(calendrier.calendriersRetenus.contains("Anniversaires"))
    }

    func testLaListeBlanchePeutEtreElargie() {
        let calendrier = Calendrier(calendriersRetenus: ["Calendrier", "Projets"])
        XCTAssertTrue(calendrier.calendriersRetenus.contains("Projets"))
    }

    // MARK: - En cours ou à venir

    private func reunion(debut: Date, fin: Date) -> Calendrier.Reunion {
        Calendrier.Reunion(id: "1", titre: "Point", debut: debut, fin: fin, lieu: nil,
                           participants: ["Nicolas Berthier"], enVisio: true,
                           calendrier: "Calendrier")
    }

    func testUneReunionEstEnCoursEntreSonDebutEtSaFin() {
        let maintenant = Date()
        let r = reunion(debut: maintenant.addingTimeInterval(-600),
                        fin: maintenant.addingTimeInterval(600))
        XCTAssertTrue(r.enCours)
    }

    func testUneReunionTermineeNEstPlusEnCours() {
        let maintenant = Date()
        XCTAssertFalse(reunion(debut: maintenant.addingTimeInterval(-7200),
                               fin: maintenant.addingTimeInterval(-3600)).enCours)
    }

    func testUneReunionAVenirNEstPasEncoreEnCours() {
        let maintenant = Date()
        XCTAssertFalse(reunion(debut: maintenant.addingTimeInterval(600),
                               fin: maintenant.addingTimeInterval(3600)).enCours)
    }
}
