import AVFoundation
import XCTest
@testable import NoyauCR

/// La réunion des deux pistes en un seul fichier stéréo.
///
/// Arbitré le 19/08/2026 après écoute de deux essais réels. Ce que ces cas
/// verrouillent, c'est la raison du choix : la séparation gauche/droite doit
/// rester **exacte**, sinon le fichier unifié ne vaut pas mieux qu'un mélange
/// et l'attribution des propos est perdue pour toujours.
final class FusionAudioTests: XCTestCase {

    /// Écrit une piste d'essai : un son continu, à un format donné.
    private func piste(_ nom: String, frequence: Double, canaux: AVAudioChannelCount,
                       secondes: Double, niveau: Float) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(nom)-\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: frequence, channels: canaux)!
        let fichier = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(frequence * secondes)
        let tampon = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        tampon.frameLength = frames
        for canal in 0..<Int(canaux) {
            for i in 0..<Int(frames) {
                tampon.floatChannelData![canal][i] =
                    niveau * sinf(2 * .pi * 440 * Float(i) / Float(frequence))
            }
        }
        try fichier.write(from: tampon)
        return url
    }

    func testDesFormatsDifferentsSontRamenesAuMeme() throws {
        // Le cas réel mesuré : micro mono 24 kHz, système stéréo 48 kHz. Les
        // entrelacer sans les convertir donnerait un fichier accéléré d'un côté.
        let moi = try piste("moi", frequence: 24_000, canaux: 1, secondes: 2, niveau: 0.3)
        let autres = try piste("autres", frequence: 48_000, canaux: 2, secondes: 2, niveau: 0.6)
        defer { for u in [moi, autres] { try? FileManager.default.removeItem(at: u) } }

        let gauche = try FusionAudio.monophonique(moi)
        let droite = try FusionAudio.monophonique(autres)

        // Deux secondes à 48 kHz, quel que soit le format d'origine.
        XCTAssertEqual(Double(gauche.count), 96_000, accuracy: 2_000)
        XCTAssertEqual(Double(droite.count), 96_000, accuracy: 2_000)
    }

    func testLesDeuxCanauxRestentSepares() throws {
        let moi = try piste("moi", frequence: 48_000, canaux: 1, secondes: 1, niveau: 0.2)
        let autres = try piste("autres", frequence: 48_000, canaux: 1, secondes: 1, niveau: 0.8)
        let sortie = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("unifie-\(UUID().uuidString).m4a")
        defer {
            for u in [moi, autres, sortie] { try? FileManager.default.removeItem(at: u) }
        }

        let bilan = try FusionAudio.unifier(moi: moi, lesAutres: autres, vers: sortie)
        XCTAssertGreaterThan(bilan.taille, 0)

        let relu = try AVAudioFile(forReading: sortie)
        XCTAssertEqual(relu.processingFormat.channelCount, 2, "le fichier doit rester stéréo")

        let tampon = AVAudioPCMBuffer(pcmFormat: relu.processingFormat,
                                      frameCapacity: AVAudioFrameCount(relu.length))!
        try relu.read(into: tampon)
        let canaux = tampon.floatChannelData!
        func energie(_ c: Int) -> Float {
            let n = Int(tampon.frameLength)
            // Le début est ignoré : l'encodeur AAC insère un court silence.
            return (n / 4..<n).reduce(0) { $0 + abs(canaux[c][$1]) } / Float(n - n / 4)
        }
        XCTAssertGreaterThan(energie(1), energie(0) * 2,
                             "le canal droit portait un signal quatre fois plus fort : "
                             + "s'ils se ressemblent, la séparation a été perdue")
    }

    func testLaPisteLaPlusLongueCommande() throws {
        // Une piste qui s'arrête avant l'autre est complétée par du silence,
        // jamais tronquée : mieux vaut quelques secondes muettes qu'une fin de
        // réunion coupée.
        let moi = try piste("moi", frequence: 48_000, canaux: 1, secondes: 1, niveau: 0.4)
        let autres = try piste("autres", frequence: 48_000, canaux: 1, secondes: 3, niveau: 0.4)
        let sortie = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("unifie-\(UUID().uuidString).m4a")
        defer {
            for u in [moi, autres, sortie] { try? FileManager.default.removeItem(at: u) }
        }

        try FusionAudio.unifier(moi: moi, lesAutres: autres, vers: sortie)
        let relu = try AVAudioFile(forReading: sortie)
        let duree = Double(relu.length) / relu.processingFormat.sampleRate
        XCTAssertEqual(duree, 3, accuracy: 0.2, "la piste la plus longue doit survivre entière")
    }

    func testUnePisteManquanteEstDite() {
        let absent = URL(fileURLWithPath: "/tmp/n-existe-pas-\(UUID().uuidString).caf")
        XCTAssertThrowsError(try FusionAudio.unifier(
            moi: absent, lesAutres: absent,
            vers: URL(fileURLWithPath: "/tmp/x.m4a")))
    }
}
