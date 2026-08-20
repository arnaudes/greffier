import XCTest
@testable import NoyauCR

/// L'assemblage des résultats du moteur de reconnaissance.
///
/// Ces cas verrouillent le défaut qui a coûté une visioconférence entière le
/// 19/08/2026 : trente minutes de réunion réduites à une seule ligne, celle
/// des sept dernières secondes. Le moteur ne rend pas une transcription qui
/// grandit, il rend un énoncé à la fois — garder le dernier reçu revenait à
/// jeter toute la réunion.
final class AssemblageResultatsTests: XCTestCase {

    private func seg(_ texte: String, _ debut: TimeInterval,
                     _ duree: TimeInterval = 0.5) -> Transcription.Segment {
        Transcription.Segment(texte: texte, debut: debut, duree: duree)
    }

    // MARK: - Reconnaître un énoncé abouti

    func testUnEtatIntermediaireNEstPasAbouti() {
        // Mesuré : les résultats en cours de reconnaissance arrivent avec un
        // début ET une durée à zéro.
        let intermediaire = [seg("bonjour", 0, 0), seg("Nicolas", 0, 0)]
        XCTAssertFalse(AssemblageResultats.estAbouti(intermediaire))
    }

    func testUnEnonceHorodateEstAbouti() {
        XCTAssertTrue(AssemblageResultats.estAbouti([seg("bonjour", 21.1)]))
    }

    func testLePremierEnonceDUnFichierEstAbouti() {
        // Il commence à zéro comme un état intermédiaire : c'est sa durée qui
        // les sépare. Sans ce cas, le début de chaque réunion serait perdu.
        XCTAssertTrue(AssemblageResultats.estAbouti([seg("bonjour", 0, 0.4)]))
    }

    func testUnResultatVideNEstPasAbouti() {
        XCTAssertFalse(AssemblageResultats.estAbouti([]))
    }

    // MARK: - Accumuler

    func testLesEnoncesSuccessifsSAjoutent() {
        var acquis: [Transcription.Segment] = []
        AssemblageResultats.integrer([seg("bonjour", 0, 0.4)], dans: &acquis)
        AssemblageResultats.integrer([seg("Nicolas", 21.1)], dans: &acquis)
        AssemblageResultats.integrer([seg("d'accord", 24.3)], dans: &acquis)

        XCTAssertEqual(acquis.map(\.texte), ["bonjour", "Nicolas", "d'accord"],
                       "le troisième énoncé ne doit pas effacer les deux premiers")
    }

    func testUnEnonceReemisRemplaceLePrecedent() {
        // Le moteur se corrige : il réémet un passage avec un texte différent.
        // Sans remplacement, le transcript porterait les deux versions.
        var acquis: [Transcription.Segment] = []
        AssemblageResultats.integrer([seg("bonjour", 0, 0.4)], dans: &acquis)
        AssemblageResultats.integrer([seg("Nicola", 21.1)], dans: &acquis)
        AssemblageResultats.integrer([seg("Nicolas", 21.1)], dans: &acquis)

        XCTAssertEqual(acquis.map(\.texte), ["bonjour", "Nicolas"])
    }

    func testUnResultatCumulatifRemplaceToutSansDoubler() {
        // Si un jour le moteur redevenait cumulatif, l'assemblage doit rester
        // juste : le nouveau résultat repart de zéro et remplace tout.
        var acquis: [Transcription.Segment] = []
        AssemblageResultats.integrer([seg("bonjour", 0, 0.4)], dans: &acquis)
        AssemblageResultats.integrer([seg("bonjour", 0, 0.4), seg("Nicolas", 21.1)],
                                     dans: &acquis)

        XCTAssertEqual(acquis.map(\.texte), ["bonjour", "Nicolas"])
    }

    func testTrenteMinutesNeSeReduisentPasALaDerniereLigne() {
        // Le cas réel, en miniature : cent énoncés répartis sur trente minutes.
        var acquis: [Transcription.Segment] = []
        for i in 0..<100 {
            AssemblageResultats.integrer([seg("mot\(i)", Double(i) * 18 + 0.1)], dans: &acquis)
        }
        XCTAssertEqual(acquis.count, 100)
        XCTAssertEqual(acquis.first?.texte, "mot0", "le début de la réunion doit survivre")
        XCTAssertEqual(acquis.last?.texte, "mot99")
    }
}

/// Le contrôle de vraisemblance posé après l'incident du 19/08/2026 : trente
/// minutes de réunion transcrites en une ligne, et l'écran annonçait
/// « transcription terminée » comme si tout allait bien.
final class AlerteTranscriptCourtTests: XCTestCase {

    private func mots(_ n: Int) -> String {
        (0..<n).map { "mot\($0)" }.joined(separator: " ")
    }

    func testLeCasReelDeclencheLAlerte() {
        // 64 mots pour 1821 secondes — la visioconférence avec Nicolas.
        let alerte = Transcription.alerteSiTropCourt(mots(64), duree: 1821)
        XCTAssertNotNil(alerte)
        XCTAssertTrue(alerte!.contains("64 mots"))
        XCTAssertTrue(alerte!.contains("conservé"), "il faut dire que rien n'est perdu")
    }

    func testUneReunionNormaleNAlertePas() {
        // Trente minutes à un débit ordinaire : environ 4 000 mots.
        XCTAssertNil(Transcription.alerteSiTropCourt(mots(4000), duree: 1821))
    }

    func testUneReunionSilencieuseNAlertePasPourAutant() {
        // Le seuil est de 20 mots par minute, très en dessous des 130 d'une
        // conversation : une réunion où l'on parle peu ne doit pas crier au loup.
        XCTAssertNil(Transcription.alerteSiTropCourt(mots(700), duree: 1800))
    }

    func testUnEnregistrementCourtEstHorsDeCause() {
        // Sous deux minutes, une phrase ou deux sont normales : un essai de
        // micro ne doit pas produire d'avertissement.
        XCTAssertNil(Transcription.alerteSiTropCourt("bonjour", duree: 90))
    }
}
