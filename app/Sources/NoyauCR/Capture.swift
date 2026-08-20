import AVFoundation
import Foundation

/// L'enregistrement audio d'une réunion.
///
/// **Enregistrer d'abord, transcrire ensuite** (chantier § 4.6). Une réunion
/// client peut durer deux heures sur batterie ; transcrire en direct chaufferait
/// le processeur et viderait la machine. La capture ne fait donc qu'écrire un
/// fichier, et la transcription attend le retour au bureau, sur secteur.
public final class Capture: @unchecked Sendable {

    public enum Erreur: Error, LocalizedError {
        case microRefuse
        case dejaEnCours
        case aucunEnregistrement
        case echecDuMoteur(String)

        public var errorDescription: String? {
            switch self {
            case .microRefuse:
                "Greffier n'a pas accès au micro. L'autorisation se donne dans Réglages "
                    + "Système, Confidentialité et sécurité, Micro. Si vous venez de "
                    + "l'accorder, quittez et rouvrez Greffier : macOS ne rafraîchit pas cette "
                    + "autorisation pour une application déjà lancée."
            case .dejaEnCours:
                "Un enregistrement est déjà en cours."
            case .aucunEnregistrement:
                "Aucun enregistrement n'a été démarré."
            case .echecDuMoteur(let detail):
                "L'enregistrement n'a pas pu démarrer. \(detail)"
            }
        }
    }

    /// **Créé seulement au moment d'enregistrer.** Instancié au lancement de
    /// l'application, `AVAudioEngine` touche au matériel audio avant que
    /// l'autorisation n'ait été demandée — et macOS peut alors refuser
    /// définitivement, sans jamais présenter de fenêtre.
    private var moteur: AVAudioEngine?
    private var fichier: AVAudioFile?
    private var debut: Date?

    /// Où sont déposés les enregistrements. Hors du dépôt git et hors de la
    /// sauvegarde : ce sont des fichiers volumineux, et le transcript qu'ils
    /// produisent suffit une fois corrigé.
    public let dossier: URL

    public init(dossier: URL) {
        self.dossier = dossier
    }

    public private(set) var url: URL?

    public var enCours: Bool { moteur?.isRunning ?? false }

    /// Depuis combien de temps ça tourne — ce que le menu affiche en clair,
    /// « Enregistrement en cours depuis 12 min », plutôt qu'une pastille rouge.
    public var depuis: TimeInterval? {
        guard let debut, enCours else { return nil }
        return Date().timeIntervalSince(debut)
    }

    /// L'état de l'autorisation, tel que l'application le voit. Sans ce
    /// diagnostic, une demande qui n'aboutit pas ne laisse aucune trace : ni
    /// dialogue à l'écran, ni décision dans le journal du système.
    public static var etatDuMicro: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "accordée"
        case .denied: "refusée"
        case .restricted: "restreinte par le système"
        case .notDetermined: "jamais demandée"
        @unknown default: "inconnue"
        }
    }

    /// Demande l'autorisation du micro. macOS ne la pose qu'une fois ; le refus
    /// doit être dit clairement plutôt que se traduire par un silence.
    public static func autoriserLeMicro() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    // MARK: - Enregistrer

    public func demarrer(nom: String) throws {
        guard !enCours else { throw Erreur.dejaEnCours }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw Erreur.microRefuse
        }
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)

        let moteur = AVAudioEngine()
        self.moteur = moteur
        let entree = moteur.inputNode
        let format = entree.outputFormat(forBus: 0)
        let destination = dossier.appendingPathComponent("\(nom).caf")

        do {
            // On écrit tel quel, sans conversion : la compression coûterait du
            // processeur pendant la réunion, précisément ce qu'on cherche à
            // éviter. Le disque, lui, ne manque pas.
            let f = try AVAudioFile(forWriting: destination, settings: format.settings)
            entree.installTap(onBus: 0, bufferSize: 4096, format: format) { tampon, _ in
                try? f.write(from: tampon)
            }
            moteur.prepare()
            try moteur.start()
            fichier = f
            url = destination
            debut = Date()
        } catch {
            moteur.inputNode.removeTap(onBus: 0)
            self.moteur = nil
            throw Erreur.echecDuMoteur(error.localizedDescription)
        }
    }

    /// Arrête et rend le fichier produit.
    @discardableResult
    public func arreter() throws -> URL {
        guard let url else { throw Erreur.aucunEnregistrement }
        moteur?.inputNode.removeTap(onBus: 0)
        moteur?.stop()
        moteur = nil
        fichier = nil
        debut = nil
        return url
    }

    /// Durée d'un enregistrement déjà écrit, pour l'afficher avant de
    /// transcrire.
    public static func duree(de url: URL) -> TimeInterval? {
        guard let f = try? AVAudioFile(forReading: url) else { return nil }
        return Double(f.length) / f.fileFormat.sampleRate
    }

    public static func lisible(_ secondes: TimeInterval) -> String {
        let minutes = Int(secondes) / 60
        if minutes < 1 { return "moins d'une minute" }
        if minutes < 60 { return "\(minutes) min" }
        let heures = minutes / 60
        let reste = minutes % 60
        return reste == 0 ? "\(heures) h" : "\(heures) h \(reste)"
    }
}
