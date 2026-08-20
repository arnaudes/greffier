import AVFoundation
import Foundation
import ScreenCaptureKit

/// La capture d'une visioconférence en **deux pistes séparées** : le micro
/// d'un côté, le son du système de l'autre.
///
/// C'est l'avantage décisif sur les outils de transcription courants, dont le
/// verbatim ne porte aucune attribution de locuteur — quatre cents lignes sans
/// un seul nom, sur une mesure faite pendant la conception. Ici l'attribution
/// n'est pas devinée, elle est **exacte par construction** : ce qui vient du
/// micro est de l'utilisateur, le reste est des autres.
/// Les huit questions de la famille « qui a dit quoi » disparaissent donc.
///
/// Le son système passe par ScreenCaptureKit, seul moyen de le capter sans
/// installer de pilote audio. Il exige l'autorisation « Enregistrement de
/// l'écran », que macOS ne demande qu'une fois.
public final class CaptureDoublePiste: NSObject, @unchecked Sendable {

    public enum Erreur: Error, LocalizedError {
        case microRefuse
        case ecranRefuse
        case aucunEcran
        case dejaEnCours
        case aucunEnregistrement
        case echec(String)

        public var errorDescription: String? {
            switch self {
            case .microRefuse:
                "Greffier n'a pas accès au micro. L'autorisation se donne dans Réglages "
                    + "Système, Confidentialité et sécurité, Micro. Si vous venez de "
                    + "l'accorder, quittez et rouvrez Greffier : macOS ne rafraîchit pas cette "
                    + "autorisation pour une application déjà lancée."
            case .ecranRefuse:
                "Greffier n'a pas l'autorisation d'enregistrer l'écran, qui est aussi celle de "
                    + "capter le son des autres participants. Elle se donne dans Réglages "
                    + "Système, Confidentialité et sécurité, Enregistrement de l'écran — puis "
                    + "il faut quitter et rouvrir Greffier."
            case .aucunEcran:
                "Aucun écran n'a été trouvé pour capter le son du système."
            case .dejaEnCours:
                "Un enregistrement est déjà en cours."
            case .aucunEnregistrement:
                "Aucun enregistrement n'a été démarré."
            case .echec(let detail):
                "L'enregistrement en deux pistes n'a pas pu démarrer. \(detail)"
            }
        }
    }

    /// Les deux fichiers produits.
    public struct Pistes: Sendable {
        /// Ce que l'utilisateur a dit.
        public var moi: URL
        /// Ce que les autres ont dit.
        public var lesAutres: URL
    }

    private let dossier: URL
    /// Créé seulement au moment d'enregistrer — même raison que pour la
    /// capture au micro seul.
    private var moteurMicro: AVAudioEngine?
    private var fichierMicro: AVAudioFile?

    private var flux: SCStream?
    private var fichierSysteme: AVAudioFile?
    private var formatSysteme: AVAudioFormat?
    private let fileEcriture = DispatchQueue(label: "io.github.arnaudes.greffier.doublepiste")

    private var pistes: Pistes?
    private var debut: Date?

    /// Prévenu quand la piste système s'interrompt d'elle-même.
    ///
    /// Le micro continue alors de tourner : l'enregistrement paraît normal,
    /// alors qu'il ne capte plus qu'une moitié de la réunion.
    public var surPerteDuSysteme: (@Sendable (String) -> Void)?
    /// Vrai dès que la piste système a cessé de fonctionner.
    public private(set) var systemePerdu = false

    public init(dossier: URL) {
        self.dossier = dossier
        super.init()
    }

    public var enCours: Bool { moteurMicro?.isRunning ?? false }

    public var depuis: TimeInterval? {
        guard let debut, enCours else { return nil }
        return Date().timeIntervalSince(debut)
    }

    // MARK: - Autorisations

    /// Les deux autorisations nécessaires, demandées ensemble pour ne pas
    /// interrompre l'utilisateur deux fois de suite.
    public static func autoriser() async -> (micro: Bool, ecran: Bool) {
        let micro = await Capture.autoriserLeMicro()
        // Interroger le contenu partageable déclenche la demande d'autorisation
        // d'écran et échoue proprement si elle est refusée.
        let ecran = (try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)) != nil
        return (micro, ecran)
    }

    // MARK: - Enregistrer

    public func demarrer(nom: String) async throws {
        guard !enCours else { throw Erreur.dejaEnCours }
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)

        let piste = Pistes(
            moi: dossier.appendingPathComponent("\(nom)-moi.caf"),
            lesAutres: dossier.appendingPathComponent("\(nom)-les-autres.caf"))

        try demarrerLeMicro(vers: piste.moi)
        do {
            try await demarrerLeSysteme(vers: piste.lesAutres)
        } catch {
            // Le micro tourne déjà : le laisser seul produirait un
            // enregistrement muet côté « les autres », donc un compte rendu
            // amputé sans que rien ne le signale. Mieux vaut tout arrêter.
            moteurMicro?.inputNode.removeTap(onBus: 0)
            moteurMicro?.stop()
            moteurMicro = nil
            fichierMicro = nil
            // Le fichier a été créé avant l'échec : le laisser ferait apparaître
            // un orphelin muet dans la fenêtre des enregistrements, sans sa
            // paire et sans une seconde de son.
            try? FileManager.default.removeItem(at: piste.moi)
            throw error
        }

        pistes = piste
        debut = Date()
    }

    private func demarrerLeMicro(vers url: URL) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw Erreur.microRefuse
        }
        let moteurMicro = AVAudioEngine()
        self.moteurMicro = moteurMicro
        let entree = moteurMicro.inputNode
        let format = entree.outputFormat(forBus: 0)
        do {
            let f = try AVAudioFile(forWriting: url, settings: format.settings)
            entree.installTap(onBus: 0, bufferSize: 4096, format: format) { tampon, _ in
                try? f.write(from: tampon)
            }
            moteurMicro.prepare()
            try moteurMicro.start()
            fichierMicro = f
        } catch {
            moteurMicro.inputNode.removeTap(onBus: 0)
            self.moteurMicro = nil
            throw Erreur.echec(error.localizedDescription)
        }
    }

    private func demarrerLeSysteme(vers url: URL) async throws {
        let contenu: SCShareableContent
        do {
            contenu = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
        } catch {
            throw Erreur.ecranRefuse
        }
        guard let ecran = contenu.displays.first else { throw Erreur.aucunEcran }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Sans cela, l'application s'entendrait elle-même.
        config.excludesCurrentProcessAudio = true
        // ScreenCaptureKit impose un flux vidéo dont nous n'avons aucun usage :
        // réduit au minimum, une image toutes les dix secondes, pour ne pas
        // faire tourner l'encodeur pendant deux heures de réunion.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 6

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else {
            throw Erreur.echec("format audio du système inattendu")
        }
        formatSysteme = format
        fichierSysteme = try AVAudioFile(forWriting: url, settings: format.settings)

        let filtre = SCContentFilter(display: ecran, excludingWindows: [])
        // Un délégué, et non `nil` : sans lui, un flux qui s'arrête en cours de
        // réunion — autorisation révoquée, écran verrouillé, session changée —
        // ne prévient personne. La visioconférence n'aurait plus que la piste
        // du micro, et on ne le découvrirait qu'à la transcription.
        let flux = SCStream(filter: filtre, configuration: config, delegate: self)
        try flux.addStreamOutput(self, type: .audio, sampleHandlerQueue: fileEcriture)
        try await flux.startCapture()
        self.flux = flux
    }

    /// Arrête les deux pistes et rend les fichiers produits.
    @discardableResult
    public func arreter() async throws -> Pistes {
        guard let pistes else { throw Erreur.aucunEnregistrement }
        moteurMicro?.inputNode.removeTap(onBus: 0)
        moteurMicro?.stop()
        moteurMicro = nil
        fichierMicro = nil
        if let flux { try? await flux.stopCapture() }
        flux = nil
        fileEcriture.sync { fichierSysteme = nil }
        debut = nil
        self.pistes = nil
        return pistes
    }
}

extension CaptureDoublePiste: SCStreamDelegate {
    /// Le flux système s'est arrêté sans qu'on le lui demande.
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        systemePerdu = true
        surPerteDuSysteme?(
            "La capture du son des autres participants s'est interrompue : "
                + error.localizedDescription
                + " Le micro continue d'enregistrer, mais cette réunion n'aura "
                + "que votre voix.")
    }
}

extension CaptureDoublePiste: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer tampon: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        guard type == .audio, let format = formatSysteme, let fichier = fichierSysteme,
              tampon.isValid, CMSampleBufferGetNumSamples(tampon) > 0 else { return }

        try? tampon.withAudioBufferList { liste, _ in
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                             bufferListNoCopy: liste.unsafePointer) else { return }
            try? fichier.write(from: pcm)
        }
    }
}
