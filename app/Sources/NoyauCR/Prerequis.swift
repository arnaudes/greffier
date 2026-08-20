import AVFoundation
import CoreGraphics
import Foundation
import Speech

/// Tout ce qu'il faut réunir pour qu'une réunion devienne un compte rendu.
///
/// Ces conditions ne se découvraient qu'à l'usage, et toujours trop tard : le
/// 17/08/2026, une autorisation micro refusée sans message a coûté une
/// demi-journée ; le même jour, la dictée désactivée a fait échouer une
/// transcription après l'enregistrement ; le 19/08, le programme Claude
/// introuvable a arrêté la chaîne **après** trente minutes de réunion captée et
/// transcrite ; et le 20/08, l'autorisation de reconnaissance vocale n'avait
/// **jamais été demandée** sans que rien ne le signale.
///
/// Aucun de ces échecs n'était visible au moment où il aurait fallu : avant
/// d'appuyer sur enregistrer.
public struct Prerequis: Sendable, Equatable {

    /// Ce que l'application vérifie, dans l'ordre où cela compte.
    public enum Condition: String, Sendable, CaseIterable, Identifiable {
        case micro, dictee, reconnaissance, ecran, claude, chrome, calendrier, dossier
        public var id: String { rawValue }

        public var titre: String {
            switch self {
            case .micro: "Micro"
            case .dictee: "Dictée du système"
            case .reconnaissance: "Reconnaissance vocale"
            case .ecran: "Enregistrement de l'écran"
            case .claude: "Claude Code"
            case .chrome: "Google Chrome"
            case .calendrier: "Calendrier"
            case .dossier: "Dossier de travail"
            }
        }

        /// À quoi cela sert — pas ce que c'est, mais ce que ça permet.
        public var role: String {
            switch self {
            case .micro: "Capter ce que vous dites."
            case .dictee: "La transcription s'appuie dessus, même hors ligne."
            case .reconnaissance: "Transformer l'enregistrement en texte, sur cet ordinateur."
            case .ecran: "Capter le son des autres participants en visioconférence."
            case .claude: "Rédiger le compte rendu, via votre abonnement."
            case .chrome: "Produire les PDF."
            case .calendrier: "Vous proposer vos réunions au bon moment."
            case .dossier: "Y ranger vos comptes rendus."
            }
        }

        /// Ce qu'on ne pourra pas faire sans.
        public var consequence: String {
            switch self {
            case .micro: "Aucun enregistrement n'est possible."
            case .dictee: "La transcription échouera, même si l'enregistrement réussit."
            case .reconnaissance:
                "L'enregistrement se fera, mais il ne pourra pas être transcrit."
            case .ecran:
                "Les visioconférences ne seront captées que par le micro : vous vous "
                    + "entendrez, pas les autres."
            case .claude:
                "Vous pourrez enregistrer et transcrire, mais aucun compte rendu ne "
                    + "sera rédigé."
            case .chrome: "Les comptes rendus resteront en Markdown, sans PDF."
            case .calendrier:
                "Vos réunions ne seront pas proposées ; tout le reste fonctionne."
            case .dossier: "Rien ne pourra être enregistré. C'est le plus grave."
            }
        }

        /// Un manque qui empêcherait de capter une réunion — donc de la perdre
        /// pour toujours. Le reste se rattrape après coup.
        /// L'autorisation se demande-t-elle depuis l'application ?
        ///
        /// La dictée, un programme absent et un dossier introuvable se règlent
        /// ailleurs : proposer « Autoriser » là où rien ne peut être accordé
        /// ferait cliquer sur un bouton qui ne fait rien.
        public var peutSeDemander: Bool {
            switch self {
            case .micro, .reconnaissance, .calendrier, .ecran: true
            case .dictee, .claude, .chrome, .dossier: false
            }
        }

        public var faitPerdreLaReunion: Bool {
            switch self {
            case .micro, .dictee, .reconnaissance, .dossier: true
            case .ecran, .claude, .chrome, .calendrier: false
            }
        }
    }

    /// L'état d'une condition, tel que la machine le rapporte.
    public enum Etat: String, Sendable, Equatable {
        case bon, aDemander, refuse, absent

        public var libelle: String {
            switch self {
            case .bon: "en place"
            case .aDemander: "jamais demandée"
            case .refuse: "refusée"
            case .absent: "introuvable"
            }
        }

        public var satisfait: Bool { self == .bon }
    }

    public var etats: [Condition: Etat]

    public init(etats: [Condition: Etat]) { self.etats = etats }

    public func etat(_ condition: Condition) -> Etat { etats[condition] ?? .aDemander }

    public var manques: [Condition] {
        Condition.allCases.filter { !etat($0).satisfait }
    }

    public var toutVaBien: Bool { manques.isEmpty }

    /// Peut-on capter une réunion sans risquer de la perdre ?
    public var peutEnregistrer: Bool {
        !Condition.allCases.contains { $0.faitPerdreLaReunion && !etat($0).satisfait }
    }

    /// Ce que le menu annonce d'un coup d'œil.
    public var resume: String {
        if toutVaBien { return "Prêt à enregistrer et à rédiger." }
        guard let premier = manques.first(where: { $0.faitPerdreLaReunion })
                ?? manques.first else { return "Prêt." }
        return "\(premier.titre) : \(etat(premier).libelle)"
    }

    public enum Gravite: Sendable { case bien, attention, bloquant }

    public var gravite: Gravite {
        if toutVaBien { return .bien }
        return peutEnregistrer ? .attention : .bloquant
    }

    // MARK: - Constater

    /// Interroge la machine **sans rien demander à l'utilisateur** : on ne fait
    /// que constater. Présenter huit demandes d'autorisation à l'ouverture d'un
    /// écran serait le meilleur moyen de les voir toutes refusées.
    public static func verifier(cheminClaude: String = "claude",
                                dossierDeTravail: URL) -> Prerequis {
        var etats: [Condition: Etat] = [:]

        etats[.micro] = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .bon
        case .notDetermined: .aDemander
        default: .refuse
        }

        etats[.dictee] = Transcription.dicteeActivee ? .bon : .refuse

        etats[.reconnaissance] = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .bon
        case .notDetermined: .aDemander
        default: .refuse
        }

        // `CGPreflightScreenCaptureAccess` constate sans déclencher la demande,
        // contrairement à une interrogation de ScreenCaptureKit.
        etats[.ecran] = CGPreflightScreenCaptureAccess() ? .bon : .aDemander

        etats[.claude] = LocalisationClaude.resoudre(cheminClaude) == nil ? .absent : .bon

        etats[.chrome] = FileManager.default.isExecutableFile(atPath: RenduPDF.chrome)
            ? .bon : .absent

        etats[.calendrier] = Calendrier.autorisationAccordee ? .bon : .aDemander

        // Le dossier peut avoir été déplacé ou renommé depuis le réglage.
        let fm = FileManager.default
        var estDossier: ObjCBool = false
        let existe = fm.fileExists(atPath: dossierDeTravail.path, isDirectory: &estDossier)
        etats[.dossier] = (existe && estDossier.boolValue
                           && fm.isWritableFile(atPath: dossierDeTravail.path)) ? .bon : .absent

        return Prerequis(etats: etats)
    }

    // MARK: - Demander

    /// Demande une autorisation. Rend `true` si elle est désormais accordée.
    ///
    /// Certaines conditions ne se demandent pas : une dictée désactivée, un
    /// programme absent ou un dossier introuvable se règlent ailleurs.
    public static func demander(_ condition: Condition) async -> Bool {
        switch condition {
        case .micro: await Capture.autoriserLeMicro()
        case .reconnaissance: await Transcription.autoriser()
        case .calendrier: await Calendrier.autoriser()
        // Celle-ci ouvre les Réglages Système : macOS ne la présente pas sous
        // forme de fenêtre d'autorisation.
        case .ecran: CGRequestScreenCaptureAccess()
        case .dictee, .claude, .chrome, .dossier: false
        }
    }

    /// Où mène le bouton, quand l'autorisation ne se règle pas depuis
    /// l'application.
    public static func reglagesSysteme(_ condition: Condition) -> URL? {
        let base = "x-apple.systempreferences:com.apple.preference.security?Privacy_"
        return switch condition {
        case .micro: URL(string: base + "Microphone")
        case .reconnaissance: URL(string: base + "SpeechRecognition")
        case .ecran: URL(string: base + "ScreenCapture")
        case .calendrier: URL(string: base + "Calendars")
        case .dictee:
            URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        case .claude, .chrome, .dossier: nil
        }
    }
}
