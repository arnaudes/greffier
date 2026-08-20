import AVFoundation
import Foundation
import Speech

/// La transcription d'un enregistrement, **sur l'appareil**.
///
/// C'est une contrainte du projet, pas une préférence : rien du son d'une
/// réunion client ne part sur un serveur. `requiresOnDeviceRecognition` le
/// garantit, et l'appel échoue plutôt que de basculer discrètement en ligne.
///
/// Le moteur employé est `SFSpeechRecognizer`, disponible et stable. macOS 26
/// apporte une nouvelle interface de transcription, plus précise ; le jour où
/// l'on voudra en changer, seul ce fichier bougera — c'est la raison de
/// l'isoler ici plutôt que de l'appeler depuis l'interface.
public struct Transcription: Sendable {

    public enum Erreur: Error, LocalizedError {
        case autorisationRefusee
        case moteurIndisponible
        case surLAppareilImpossible
        case dicteeDesactivee
        case echec(String)

        public var errorDescription: String? {
            switch self {
            case .autorisationRefusee:
                "Greffier n'a pas l'autorisation de transcrire. Elle se donne dans "
                    + "Réglages Système, Confidentialité et sécurité, Reconnaissance vocale."
            case .moteurIndisponible:
                "La reconnaissance vocale française n'est pas disponible sur cet ordinateur."
            case .surLAppareilImpossible:
                "La transcription sur l'appareil n'est pas disponible pour le français. "
                    + "Le modèle se télécharge dans Réglages Système, Clavier, Dictée."
            case .dicteeDesactivee:
                "La dictée est désactivée sur cet ordinateur, et la transcription en dépend — "
                    + "y compris celle qui reste sur l'appareil. Activez-la dans Réglages "
                    + "Système, Clavier, Dictée, en choisissant le français. "
                    + "L'enregistrement est conservé : il suffira de relancer la transcription."
            case .echec(let detail):
                Erreur.enFrancais(detail)
            }
        }

        /// Les messages du moteur arrivent en anglais. Les recopier tels quels
        /// dans une interface française n'aide personne : les cas connus sont
        /// traduits et complétés par ce qu'il faut faire.
        static func enFrancais(_ detail: String) -> String {
            if detail.localizedCaseInsensitiveContains("Siri and Dictation are disabled") {
                return Erreur.dicteeDesactivee.errorDescription!
            }
            if detail.localizedCaseInsensitiveContains("No speech detected") {
                return "Aucune parole n'a été reconnue dans cet enregistrement. "
                    + "Le micro captait-il bien la réunion ?"
            }
            return "La transcription a échoué. \(detail)"
        }
    }

    public var langue: Locale

    public init(langue: Locale = Locale(identifier: "fr_FR")) {
        self.langue = langue
    }

    /// Ce que la machine sait faire, sans rien enregistrer ni demander.
    public struct Etat: Sendable {
        public var langue: String
        public var disponible: Bool
        public var surLAppareil: Bool
        public var dictee: Bool
        public var autorisation: String

        /// Vrai seulement si tout est réuni. C'est cette réponse-là qui compte,
        /// pas la disponibilité du moteur prise isolément.
        public var pretATranscrire: Bool { disponible && surLAppareil && dictee }
    }

    /// La dictée est-elle activée dans les Réglages Système ?
    ///
    /// Ce n'est pas une coquetterie : `SFSpeechRecognizer` s'appuie sur le
    /// service de dictée de macOS, y compris pour la reconnaissance sur
    /// l'appareil. Sans elle, `isAvailable` et `supportsOnDeviceRecognition`
    /// répondent « oui » tous les deux, et la transcription échoue quand même —
    /// avec un message en anglais, « Siri and Dictation are disabled ».
    /// Constaté le 17/08/2026.
    public static var dicteeActivee: Bool {
        let prefs = UserDefaults(suiteName: "com.apple.assistant.support")
        return (prefs?.object(forKey: "Dictation Enabled") as? Bool)
            ?? ((prefs?.object(forKey: "Dictation Enabled") as? Int).map { $0 != 0 } ?? false)
    }

    public static func etatDuMoteur(langue: Locale = Locale(identifier: "fr_FR")) -> Etat {
        let moteur = SFSpeechRecognizer(locale: langue)
        let autorisation: String = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: "accordée"
        case .denied: "refusée"
        case .restricted: "restreinte par le système"
        case .notDetermined: "jamais demandée"
        @unknown default: "inconnue"
        }
        return Etat(langue: langue.identifier,
                    disponible: moteur?.isAvailable ?? false,
                    surLAppareil: moteur?.supportsOnDeviceRecognition ?? false,
                    dictee: dicteeActivee,
                    autorisation: autorisation)
    }

    public static func autoriser() async -> Bool {
        await withCheckedContinuation { suite in
            SFSpeechRecognizer.requestAuthorization { statut in
                suite.resume(returning: statut == .authorized)
            }
        }
    }

    /// Un transcript beaucoup trop court pour la durée enregistrée : le dire,
    /// plutôt que de laisser rédiger un compte rendu sur presque rien.
    ///
    /// Le 19/08/2026, trente minutes de visioconférence ont produit une seule
    /// ligne — un défaut d'assemblage des résultats du moteur, corrigé depuis.
    /// Rien ne l'avait signalé : l'écran annonçait « transcription terminée »
    /// exactement comme si tout allait bien. Ce contrôle-ci ne remplace pas le
    /// correctif, il rattrape la prochaine panne d'un autre genre — un micro
    /// muet, une réunion où personne ne parle près de l'ordinateur.
    ///
    /// Le seuil est bas à dessein : on parle autour de cent trente mots par
    /// minute, et vingt suffisent à écarter le doute sans crier au loup dès
    /// qu'une réunion est silencieuse.
    public static func alerteSiTropCourt(_ transcript: String, duree: TimeInterval) -> String? {
        guard duree >= 120 else { return nil }
        let mots = transcript.split(whereSeparator: \.isWhitespace).count
        let attendus = Int(duree / 60 * 20)
        guard mots < attendus else { return nil }
        return "⚠️ Seulement \(mots) mots reconnus pour \(Capture.lisible(duree)) "
            + "d'enregistrement : c'est anormalement peu. Relisez le transcript avant "
            + "d'analyser. L'enregistrement est conservé — la transcription peut être "
            + "relancée sans avoir à refaire la réunion."
    }

    /// Où en est une transcription.
    ///
    /// La progression n'est pas une estimation : chaque énoncé reconnu porte sa
    /// place exacte dans l'enregistrement, et la durée totale du fichier est
    /// connue d'avance. Le pourcentage affiché est donc vrai, pas décoratif.
    public struct Avancement: Sendable {
        public var mots: Int
        /// Jusqu'où la reconnaissance est arrivée dans l'enregistrement.
        public var secondes: TimeInterval
        public var duree: TimeInterval

        public var fraction: Double {
            guard duree > 0 else { return 0 }
            return min(1, max(0, secondes / duree))
        }

        public var pourcentage: Int { Int((fraction * 100).rounded()) }
    }

    /// La durée d'un fichier audio, pour savoir sur quoi rapporter l'avancement.
    static func duree(de url: URL) -> TimeInterval {
        guard let f = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(f.length) / f.fileFormat.sampleRate
    }

    /// Au-delà de ce silence du moteur, on considère qu'il ne répondra plus.
    ///
    /// **Rien ne bornait l'attente.** Si le moteur cesse de répondre sans
    /// rendre de résultat final — fichier qu'il n'arrive pas à lire, service de
    /// dictée qui tombe —, la transcription attendait indéfiniment et
    /// l'application restait figée sur « transcription en cours », sans
    /// échappatoire. C'est exactement ce qui s'est produit sur une sonde le
    /// 19/08/2026, bloquée vingt minutes sans qu'on comprenne pourquoi.
    ///
    /// Le délai porte sur le **silence**, pas sur la durée totale : une réunion
    /// de trois heures est longue à transcrire, mais le moteur y donne signe de
    /// vie en permanence.
    public static let silenceQuiFaitAbandonner: TimeInterval = 90

    /// Un morceau de parole reconnu, avec sa place dans l'enregistrement.
    /// C'est l'horodatage qui permet ensuite d'entrelacer les deux pistes
    /// d'une visioconférence dans l'ordre où les choses ont été dites.
    public struct Segment: Sendable, Equatable {
        public var texte: String
        public var debut: TimeInterval
        public var duree: TimeInterval

        public init(texte: String, debut: TimeInterval, duree: TimeInterval) {
            self.texte = texte
            self.debut = debut
            self.duree = duree
        }

        public var fin: TimeInterval { debut + duree }
    }

    /// Transcrit un fichier en conservant l'horodatage de chaque morceau.
    ///
    /// - Parameter progression: appelée au fil de l'eau avec le nombre de mots
    ///   déjà reconnus. Une visioconférence de trente minutes ne doit pas
    ///   ressembler à un gel de l'application.
    public func segmenter(_ url: URL,
                          progression: (@Sendable (Avancement) -> Void)? = nil) async throws
                          -> [Segment] {
        let duree = Transcription.duree(de: url)
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw Erreur.autorisationRefusee
        }
        guard let moteur = SFSpeechRecognizer(locale: langue), moteur.isAvailable else {
            throw Erreur.moteurIndisponible
        }
        guard moteur.supportsOnDeviceRecognition else { throw Erreur.surLAppareilImpossible }
        guard Transcription.dicteeActivee else { throw Erreur.dicteeDesactivee }

        let demande = SFSpeechURLRecognitionRequest(url: url)
        demande.requiresOnDeviceRecognition = true
        // Les résultats intermédiaires sont demandés même sans progression à
        // afficher : ils servent de filet quand le résultat final revient vide.
        demande.shouldReportPartialResults = true
        demande.addsPunctuation = true

        return try await withCheckedThrowingContinuation { suite in
            let boite = BoiteASegments(suite)
            let tache = moteur.recognitionTask(with: demande) { resultat, erreur in
                if let erreur { boite.echouer(Erreur.echec(erreur.localizedDescription)); return }
                guard let resultat else { return }
                let segments = resultat.bestTranscription.segments.map {
                    Segment(texte: $0.substring, debut: $0.timestamp, duree: $0.duration)
                }
                boite.signeDeVie()
                if resultat.isFinal {
                    boite.reussir(segments)
                } else if !segments.isEmpty {
                    boite.retenir(segments)
                    progression?(boite.avancement(duree: duree))
                }
            }
            boite.veiller(tache: tache)
        }
    }

    /// Transcrit un fichier audio en texte.
    ///
    /// - Parameter progression: appelée au fil de l'eau avec le texte reconnu
    ///   jusque-là. Une transcription d'une heure ne doit pas ressembler à un
    ///   gel de l'application.
    public func transcrire(_ url: URL,
                           progression: (@Sendable (Avancement) -> Void)? = nil) async throws
                           -> String {
        let duree = Transcription.duree(de: url)
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw Erreur.autorisationRefusee
        }
        guard let moteur = SFSpeechRecognizer(locale: langue), moteur.isAvailable else {
            throw Erreur.moteurIndisponible
        }
        guard moteur.supportsOnDeviceRecognition else {
            throw Erreur.surLAppareilImpossible
        }
        guard Transcription.dicteeActivee else { throw Erreur.dicteeDesactivee }

        let demande = SFSpeechURLRecognitionRequest(url: url)
        demande.requiresOnDeviceRecognition = true
        // Toujours demandés, même sans progression à afficher : c'est par eux
        // que les énoncés arrivent, et sans eux le moteur ne rendrait que le
        // dernier.
        demande.shouldReportPartialResults = true
        // La ponctuation change tout pour un compte rendu : sans elle, le
        // transcript arrive en un seul bloc et Claude doit deviner les phrases.
        demande.addsPunctuation = true

        return try await withCheckedThrowingContinuation { suite in
            let boite = BoiteAUneSeuleReponse(suite)
            moteur.recognitionTask(with: demande) { resultat, erreur in
                if let erreur {
                    boite.echouer(Erreur.echec(erreur.localizedDescription))
                    return
                }
                guard let resultat else { return }
                let texte = resultat.bestTranscription.formattedString
                let segments = resultat.bestTranscription.segments.map {
                    Segment(texte: $0.substring, debut: $0.timestamp, duree: $0.duration)
                }
                if resultat.isFinal {
                    boite.reussir(texte, segments: segments)
                } else {
                    boite.retenir(texte, segments: segments)
                    // Ce qui est rapporté est ce qui est acquis, pas le seul
                    // énoncé en cours : sinon la progression donne à croire
                    // que la transcription n'avance pas.
                    progression?(boite.avancement(duree: duree))
                }
            }
        }
    }
}

/// Assemble les résultats du moteur en une transcription complète.
///
/// **Le moteur ne rend pas une transcription qui grandit : il rend un énoncé
/// à la fois.** Mesuré le 19/08/2026 sur une visioconférence réelle de trente
/// minutes — 437 réponses pour quatre minutes d'audio, et le résultat final ne
/// couvrait que les sept dernières secondes. Garder le dernier résultat reçu,
/// comme on le faisait, revenait à ne conserver que la dernière phrase de la
/// réunion. Une visioconférence de trente minutes s'était réduite à une ligne.
///
/// Le tri se fait sur l'horodatage : les états intermédiaires d'un énoncé en
/// cours de reconnaissance arrivent sans horodatage — début et durée à zéro —
/// tandis qu'un énoncé abouti porte sa place exacte dans l'enregistrement.
enum AssemblageResultats {

    /// Cet ensemble de segments est-il un énoncé abouti, ou un état
    /// intermédiaire encore sans horodatage ?
    static func estAbouti(_ segments: [Transcription.Segment]) -> Bool {
        guard let premier = segments.first else { return false }
        return premier.debut > 0 || premier.duree > 0
    }

    /// Ajoute un énoncé à ceux déjà retenus.
    ///
    /// Un énoncé qui recommence là où un autre commençait le remplace : le
    /// moteur se corrige parfois en réémettant un passage.
    static func integrer(_ nouveaux: [Transcription.Segment],
                         dans acquis: inout [Transcription.Segment]) {
        guard let debut = nouveaux.first?.debut else { return }
        acquis.removeAll { $0.debut >= debut }
        acquis.append(contentsOf: nouveaux)
    }
}

private final class BoiteASegments: @unchecked Sendable {
    private var suite: CheckedContinuation<[Transcription.Segment], Error>?
    /// Tous les énoncés aboutis depuis le début du fichier.
    private var acquis: [Transcription.Segment] = []
    /// Le dernier état reçu, quel qu'il soit. Filet pour un enregistrement si
    /// court qu'aucun énoncé n'a eu le temps d'être horodaté.
    private var dernier: [Transcription.Segment] = []
    private let verrou = NSLock()

    /// Quand le moteur a donné signe de vie pour la dernière fois.
    private var dernierSigne = Date()
    private var veille: Timer?
    private weak var tache: SFSpeechRecognitionTask?

    init(_ suite: CheckedContinuation<[Transcription.Segment], Error>) { self.suite = suite }

    /// Surveille le silence du moteur et abandonne s'il dure trop.
    ///
    /// On rend ce qui a été reconnu plutôt que de lever une erreur : une
    /// transcription partielle vaut mieux qu'un écran figé et qu'un
    /// enregistrement perdu.
    func veiller(tache: SFSpeechRecognitionTask) {
        verrou.lock(); defer { verrou.unlock() }
        self.tache = tache
        let minuterie = Timer(timeInterval: 10, repeats: true) { [weak self] minuterie in
            guard let self else { minuterie.invalidate(); return }
            verrou.lock()
            let silence = Date().timeIntervalSince(dernierSigne)
            let fini = suite == nil
            verrou.unlock()
            if fini { minuterie.invalidate(); return }
            guard silence > Transcription.silenceQuiFaitAbandonner else { return }
            minuterie.invalidate()
            self.tache?.cancel()
            self.abandonner()
        }
        RunLoop.main.add(minuterie, forMode: .common)
        veille = minuterie
    }

    func signeDeVie() {
        verrou.lock(); defer { verrou.unlock() }
        dernierSigne = Date()
    }

    /// Le moteur s'est tu : on rend ce qu'on a.
    private func abandonner() {
        verrou.lock(); defer { verrou.unlock() }
        guard let attente = suite else { return }
        suite = nil
        veille?.invalidate(); veille = nil
        if acquis.isEmpty && dernier.isEmpty {
            attente.resume(throwing: Transcription.Erreur.echec(
                "Le moteur de reconnaissance a cessé de répondre. "
                    + "L'enregistrement est conservé : vous pouvez relancer la "
                    + "transcription depuis la fenêtre des enregistrements."))
        } else {
            attente.resume(returning: acquis.isEmpty ? dernier : acquis)
        }
    }

    func retenir(_ v: [Transcription.Segment]) {
        verrou.lock(); defer { verrou.unlock() }
        dernier = v
        guard AssemblageResultats.estAbouti(v) else { return }
        AssemblageResultats.integrer(v, dans: &acquis)
    }

    /// Où en est la reconnaissance : le dernier énoncé acquis donne la place
    /// atteinte dans l'enregistrement.
    func avancement(duree: TimeInterval) -> Transcription.Avancement {
        verrou.lock(); defer { verrou.unlock() }
        return Transcription.Avancement(mots: acquis.count,
                                        secondes: acquis.last.map { $0.debut + $0.duree } ?? 0,
                                        duree: duree)
    }

    func reussir(_ v: [Transcription.Segment]) {
        verrou.lock(); defer { verrou.unlock() }
        veille?.invalidate(); veille = nil
        if AssemblageResultats.estAbouti(v) {
            AssemblageResultats.integrer(v, dans: &acquis)
        }
        let issue = acquis.isEmpty ? (v.isEmpty ? dernier : v) : acquis
        suite?.resume(returning: issue); suite = nil
    }

    func echouer(_ e: Error) {
        verrou.lock(); defer { verrou.unlock() }
        veille?.invalidate(); veille = nil
        // Une erreur en cours de route ne doit pas jeter ce qui a été reconnu
        // jusque-là : une réunion à moitié transcrite vaut mieux que rien.
        if !acquis.isEmpty { suite?.resume(returning: acquis); suite = nil; return }
        suite?.resume(throwing: e); suite = nil
    }
}

/// Le rappel de reconnaissance est appelé plusieurs fois ; une continuation ne
/// se reprend qu'une. Sans ce garde-fou, un résultat suivi d'une erreur ferait
/// planter le programme.
///
/// Cette boîte-ci rend du texte plutôt que des segments, mais elle assemble les
/// énoncés de la même façon et pour la même raison.
private final class BoiteAUneSeuleReponse: @unchecked Sendable {
    private var suite: CheckedContinuation<String, Error>?
    /// Les énoncés aboutis, chacun avec sa place dans l'enregistrement, pour
    /// pouvoir remplacer celui que le moteur réémet.
    private var acquis: [(debut: TimeInterval, texte: String)] = []
    private var dernier = ""
    private let verrou = NSLock()

    init(_ suite: CheckedContinuation<String, Error>) { self.suite = suite }

    /// Le texte de tous les énoncés retenus, dans l'ordre.
    private var assemble: String {
        // Un énoncé par ligne : collés bout à bout, les énoncés d'une réunion
        // d'une heure forment un pavé illisible, et rien n'y marque les tours
        // de parole.
        acquis.map(\.texte).joined(separator: "\n")
    }

    func retenir(_ texte: String, segments: [Transcription.Segment]) {
        verrou.lock(); defer { verrou.unlock() }
        dernier = texte
        guard AssemblageResultats.estAbouti(segments),
              let debut = segments.first?.debut, !texte.isEmpty else { return }
        acquis.removeAll { $0.debut >= debut }
        acquis.append((debut, texte))
    }

    func avancement(duree: TimeInterval) -> Transcription.Avancement {
        verrou.lock(); defer { verrou.unlock() }
        let mots = assemble.split(whereSeparator: \.isWhitespace).count
        return Transcription.Avancement(mots: mots,
                                        secondes: acquis.last?.debut ?? 0,
                                        duree: duree)
    }

    func reussir(_ texte: String, segments: [Transcription.Segment]) {
        retenir(texte, segments: segments)
        verrou.lock(); defer { verrou.unlock() }
        let issue = acquis.isEmpty ? (texte.isEmpty ? dernier : texte) : assemble
        suite?.resume(returning: issue); suite = nil
    }

    func echouer(_ erreur: Error) {
        verrou.lock(); defer { verrou.unlock() }
        if !acquis.isEmpty { suite?.resume(returning: assemble); suite = nil; return }
        suite?.resume(throwing: erreur); suite = nil
    }
}
