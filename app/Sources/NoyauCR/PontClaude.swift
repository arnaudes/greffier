import Foundation

// Le lien avec Claude : pilotage direct du binaire `claude` en sous-processus
// (chantier § 3.3). L'authentification est celle de l'utilisateur, donc son abonnement —
// jamais l'API facturée séparément.
//
// Format vérifié en ligne de commande le 14 août 2026 :
//   claude -p --verbose --input-format stream-json --output-format stream-json
// Le drapeau --verbose n'est pas optionnel : avec -p, le binaire refuse
// stream-json sans lui.
//
// Chaque ligne de la sortie est un objet JSON. Les types rencontrés :
//   system/init          session_id et modèle retenu, une fois au démarrage
//   rate_limit_event     état des limites du forfait — surveillé, pas ignoré
//   system/…             thinking_tokens, post_turn_summary : sans usage ici
//   assistant            le message en cours de construction
//   result               la réponse complète du tour, dans le champ `result`

/// Où se trouve le programme `claude` sur cette machine.
///
/// Une application lancée depuis le Finder n'hérite **pas** du `PATH` du
/// terminal : elle ne connaît que `/usr/bin:/bin:/usr/sbin:/sbin`. Lancer
/// `/usr/bin/env claude` y échoue donc avec « No such file or directory » et le
/// code 127, alors que la même commande fonctionne dans un shell. Mesuré le
/// 17/08/2026 : l'application enregistrait, transcrivait, et s'arrêtait net au
/// moment de rédiger.
///
/// Aucun chemin n'est écrit en dur avec un numéro de version : une
/// installation par Node vit dans un dossier qui porte cette version, et ce
/// dossier change de nom à chaque mise à jour.
public enum LocalisationClaude {

    /// Le résultat de la recherche, gardé pour toute la durée d'exécution : le
    /// dernier recours lance un shell de connexion, ce qui ne doit pas se
    /// produire à chaque compte rendu.
    /// Seuls les succès sont retenus : mémoriser un échec empêcherait de voir
    /// une installation faite entre-temps sans relancer l'application.
    private final class Memoire: @unchecked Sendable {
        private var connu: [String: String] = [:]
        private let verrou = NSLock()
        func valeur(pour demande: String, sinon calcul: () -> String?) -> String? {
            verrou.lock(); defer { verrou.unlock() }
            if let deja = connu[demande] { return deja }
            let trouve = calcul()
            if let trouve { connu[demande] = trouve }
            return trouve
        }
    }
    private static let memoire = Memoire()

    /// Rend le chemin complet du programme, ou `nil` s'il reste introuvable.
    ///
    /// - Parameter demande: ce que réclame la configuration. Un chemin contenant
    ///   une barre oblique est pris tel quel — c'est le réglage de secours, qui
    ///   doit primer sur toute détection automatique.
    public static func resoudre(_ demande: String = "claude") -> String? {
        memoire.valeur(pour: demande) { chercher(demande) }
    }

    private static func chercher(_ demande: String) -> String? {
        let fm = FileManager.default
        let dilate = NSString(string: demande).expandingTildeInPath

        if demande.contains("/") {
            return fm.isExecutableFile(atPath: dilate) ? dilate : nil
        }
        for chemin in candidats(nom: demande) where fm.isExecutableFile(atPath: chemin) {
            return chemin
        }
        return demanderAuShell(demande)
    }

    /// Les endroits où Claude Code s'installe, du plus courant au plus
    /// particulier.
    public static func candidats(nom: String) -> [String] {
        let maison = NSHomeDirectory()
        var liste = [
            "\(maison)/.claude/local/\(nom)",
            "\(maison)/.local/bin/\(nom)",
            "\(maison)/.bun/bin/\(nom)",
            "\(maison)/.volta/bin/\(nom)",
            "/opt/homebrew/bin/\(nom)",
            "/usr/local/bin/\(nom)",
        ]
        // Les installations de Node vivent dans un dossier portant leur
        // version. On parcourt les sous-dossiers, du nom le plus élevé au plus
        // bas, pour tomber sur la version la plus récente en premier.
        for racine in ["\(maison)/.local",
                       "\(maison)/.nvm/versions/node",
                       "/usr/local/n/versions/node"] {
            let sous = (try? FileManager.default.contentsOfDirectory(atPath: racine)) ?? []
            liste += sous.sorted(by: >).map { "\(racine)/\($0)/bin/\(nom)" }
        }
        return liste
    }

    /// Dernier recours : demander à un shell de connexion, qui charge le profil
    /// de l'utilisateur et voit donc exactement ce que voit son terminal.
    private static func demanderAuShell(_ nom: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: shell)
        processus.arguments = ["-lc", "command -v \(nom)"]
        let tuyau = Pipe()
        processus.standardOutput = tuyau
        processus.standardError = FileHandle.nullDevice
        guard (try? processus.run()) != nil else { return nil }
        let data = tuyau.fileHandleForReading.readDataToEndOfFile()
        processus.waitUntilExit()
        let chemin = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !chemin.isEmpty,
              FileManager.default.isExecutableFile(atPath: chemin) else { return nil }
        return chemin
    }

    /// L'environnement du sous-processus, complété du dossier où le programme a
    /// été trouvé. Claude Code appelle lui-même d'autres outils — `git`, entre
    /// autres — qui doivent rester à portée.
    static func environnement(pour binaire: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let maison = NSHomeDirectory()
        var chemins = [URL(fileURLWithPath: binaire).deletingLastPathComponent().path]
        chemins += (env["PATH"] ?? "").split(separator: ":").map(String.init)
        chemins += ["\(maison)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                    "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var vus = Set<String>()
        env["PATH"] = chemins.filter { vus.insert($0).inserted }.joined(separator: ":")
        return env
    }
}

/// Réglages du sous-processus.
public struct ConfigClaude: Sendable {
    /// Nom ou chemin du programme. Un simple nom est cherché aux emplacements
    /// habituels d'installation ; un chemin complet est employé tel quel.
    public var binaire: String
    /// Modèle demandé. `nil` laisse le binaire choisir celui de la session.
    public var modele: String?
    /// Modèle de repli, utilisé automatiquement quand le premier devient
    /// indisponible — typiquement une limite de forfait atteinte. Sans lui,
    /// l'application s'arrêterait net en pleine rédaction.
    public var modeleRepli: String?
    /// Prompt système ajouté à celui du binaire (spécification § 2).
    public var promptSysteme: String?
    /// Répertoire de travail du sous-processus.
    public var repertoire: URL?

    public init(binaire: String = "claude", modele: String? = nil,
                modeleRepli: String? = nil, promptSysteme: String? = nil,
                repertoire: URL? = nil) {
        self.binaire = binaire
        self.modele = modele
        self.modeleRepli = modeleRepli
        self.promptSysteme = promptSysteme
        self.repertoire = repertoire
    }

    var arguments: [String] {
        var a = ["-p", "--verbose",
                 "--input-format", "stream-json",
                 "--output-format", "stream-json"]
        if let modele { a += ["--model", modele] }
        if let modeleRepli { a += ["--fallback-model", modeleRepli] }
        if let promptSysteme { a += ["--append-system-prompt", promptSysteme] }
        return a
    }
}

/// État des limites du forfait, tel que le flux le rapporte.
public struct InfoLimite: Sendable {
    public var statut: String
    public var type: String?
    public var reinitialisationLe: Date?

    init?(_ objet: [String: Any]) {
        guard let statut = objet["status"] as? String else { return nil }
        self.statut = statut
        self.type = objet["rateLimitType"] as? String
        if let t = objet["resetsAt"] as? Double {
            self.reinitialisationLe = Date(timeIntervalSince1970: t)
        }
    }
}

public enum ErreurPont: Error, LocalizedError {
    case binaireIntrouvable(String)
    case processusTermine(code: Int32, sortieErreur: String)
    case reponseIllisible(String)
    case dejaEnCours
    case silence

    public var errorDescription: String? {
        switch self {
        case .binaireIntrouvable(let chemin):
            "Greffier n'a pas trouvé le programme Claude Code, qu'il cherchait sous le nom "
                + "« \(chemin) ». Il est pourtant peut-être bien installé : une application "
                + "lancée depuis le Finder ne voit pas les mêmes dossiers qu'un terminal. "
                + "Tapez « which claude » dans un terminal, puis recopiez le chemin obtenu "
                + "dans les réglages d'Greffier, onglet Rédaction."
        case .processusTermine(let code, let err):
            "Le dialogue avec Claude s'est interrompu (code \(code))."
                + (err.isEmpty ? "" : " \(err)")
        case .reponseIllisible(let ligne):
            // Le début de la réponse aide à comprendre ce qui s'est passé, mais
            // seul compte ce qu'on peut faire : réessayer, car un modèle
            // encadre parfois son JSON d'une phrase malgré la consigne.
            "Claude a répondu quelque chose d'inattendu. Réessayez : vos réponses et "
                + "votre transcript sont conservés.\n\nDébut de la réponse : "
                + "\(ligne.prefix(120))"
        case .dejaEnCours:
            "Une question est déjà en cours ; il faut attendre la réponse."
        case .silence:
            "Claude n'a pas répondu dans le temps imparti. Votre transcript et vos "
                + "réponses sont conservés : vous pouvez réessayer."
        }
    }
}

/// Tient une conversation avec Claude, du premier temps au dernier.
///
/// Un seul processus pour toute la conversation : le transcript, volumineux,
/// n'est envoyé qu'une fois, et les temps suivants disposent de tout ce qui
/// précède sans avoir à le renvoyer.
public final class PontClaude: @unchecked Sendable {

    private let config: ConfigClaude
    private let processus = Process()
    private let entree = Pipe()
    private let sortie = Pipe()
    private let erreur = Pipe()

    /// Protège tout l'état mutable ci-dessous. Les données arrivent depuis le
    /// fil de lecture du tuyau, les envois depuis l'appelant.
    private let file = DispatchQueue(label: "io.github.arnaudes.greffier.pont")
    private var tampon = Data()
    private var texteErreur = ""
    private var attente: CheckedContinuation<String, Error>?
    /// Le garde-fou contre une réponse qui ne vient jamais.
    private var delai: DispatchWorkItem?

    /// Identifiant de session, connu dès le premier événement. Permet de
    /// reprendre la conversation par `--resume` si le processus tombe.
    public private(set) var sessionID: String?

    /// Appelé à chaque annonce de limite du forfait.
    public var surLimite: (@Sendable (InfoLimite) -> Void)?
    /// Appelé au fil de la rédaction, pour l'affichage progressif.
    public var surTexte: (@Sendable (String) -> Void)?

    public init(config: ConfigClaude = ConfigClaude()) {
        self.config = config
    }

    // MARK: - Cycle de vie

    public func demarrer() throws {
        // Le programme est localisé ici, et non délégué à `/usr/bin/env` : sans
        // le `PATH` d'un terminal, `env` échoue avec un laconique « code 127 »
        // qui ne dit rien à personne.
        guard let chemin = LocalisationClaude.resoudre(config.binaire) else {
            throw ErreurPont.binaireIntrouvable(config.binaire)
        }
        processus.executableURL = URL(fileURLWithPath: chemin)
        processus.arguments = config.arguments
        processus.environment = LocalisationClaude.environnement(pour: chemin)
        processus.standardInput = entree
        processus.standardOutput = sortie
        processus.standardError = erreur
        if let repertoire = config.repertoire { processus.currentDirectoryURL = repertoire }

        // `[weak self]` et non `[self]` : le tuyau retient son gestionnaire, qui
        // retiendrait le pont — lequel ne pourrait plus jamais être libéré si
        // l'arrêt était oublié.
        sortie.fileHandleForReading.readabilityHandler = { [weak self] tuyau in
            let data = tuyau.availableData
            guard let self, !data.isEmpty else { return }
            file.async { self.absorber(data) }
        }
        erreur.fileHandleForReading.readabilityHandler = { [weak self] tuyau in
            let data = tuyau.availableData
            guard let self, !data.isEmpty,
                  let texte = String(data: data, encoding: .utf8) else { return }
            file.async { self.texteErreur += texte }
        }
        processus.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            // La référence est capturée une fois, hors de la file : la relire à
            // l'intérieur reviendrait à toucher une variable depuis deux fils.
            guard let moi = self else { return }
            moi.file.async { moi.conclureBrutalement(code: code) }
        }

        do {
            try processus.run()
        } catch {
            throw ErreurPont.binaireIntrouvable(config.binaire)
        }
    }

    public func arreter() {
        sortie.fileHandleForReading.readabilityHandler = nil
        erreur.fileHandleForReading.readabilityHandler = nil
        try? entree.fileHandleForWriting.close()
        if processus.isRunning { processus.terminate() }
        // Une attente en cours doit être relâchée : sans cela, celui qui a posé
        // la question resterait suspendu pour toujours.
        file.async { [self] in conclure(.failure(ErreurPont.silence)) }
    }

    // MARK: - Dialogue

    /// Au-delà de ce silence, on considère que la réponse ne viendra pas.
    ///
    /// **Rien ne bornait l'attente.** Un processus vivant mais muet — réseau
    /// coupé au mauvais moment, dialogue bloqué — laissait l'application figée
    /// sur « Claude rédige » sans aucune issue. La mort du processus était
    /// couverte, son silence non.
    ///
    /// Le délai est large : Claude prend le temps qu'il faut pour lire
    /// quarante-cinq minutes de verbatim, et l'interrompre trop tôt coûterait
    /// bien plus qu'attendre.
    public static let silenceQuiFaitAbandonner: TimeInterval = 300

    /// Envoie un message et rend la réponse complète du tour.
    public func envoyer(_ texte: String) async throws -> String {
        try await withCheckedThrowingContinuation { suite in
            file.async { [self] in
                guard attente == nil else {
                    suite.resume(throwing: ErreurPont.dejaEnCours); return
                }
                attente = suite
                armerLeDelai()
                do {
                    try entree.fileHandleForWriting.write(contentsOf: Self.encoder(texte))
                } catch {
                    attente = nil
                    suite.resume(throwing: error)
                }
            }
        }
    }

    /// Un message utilisateur, tel que `--input-format stream-json` l'attend :
    /// un objet JSON par ligne.
    static func encoder(_ texte: String) -> Data {
        let objet: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": [["type": "text", "text": texte]]],
        ]
        var data = (try? JSONSerialization.data(withJSONObject: objet)) ?? Data()
        data.append(0x0A)
        return data
    }

    // MARK: - Lecture du flux

    /// Découpe le flux en lignes. Une lecture de tuyau ne s'arrête pas sur une
    /// frontière de ligne : le reliquat attend la lecture suivante.
    private func absorber(_ data: Data) {
        tampon.append(data)
        while let saut = tampon.firstIndex(of: 0x0A) {
            let ligne = tampon[tampon.startIndex..<saut]
            tampon = tampon[tampon.index(after: saut)...]
            if !ligne.isEmpty { traiter(ligne) }
        }
    }

    private func traiter(_ ligne: Data) {
        guard let objet = try? JSONSerialization.jsonObject(with: ligne) as? [String: Any],
              let type = objet["type"] as? String else { return }

        if sessionID == nil { sessionID = objet["session_id"] as? String }

        switch type {
        case "rate_limit_event":
            if let info = objet["rate_limit_info"] as? [String: Any],
               let limite = InfoLimite(info) {
                surLimite?(limite)
            }

        case "assistant":
            guard let message = objet["message"] as? [String: Any],
                  let contenu = message["content"] as? [[String: Any]] else { return }
            for bloc in contenu where bloc["type"] as? String == "text" {
                if let t = bloc["text"] as? String { surTexte?(t) }
            }

        case "result":
            let estErreur = objet["is_error"] as? Bool ?? false
            if let resultat = objet["result"] as? String, !estErreur {
                conclure(.success(resultat))
            } else {
                let detail = (objet["result"] as? String) ?? "réponse en erreur"
                conclure(.failure(ErreurPont.reponseIllisible(detail)))
            }

        default:
            break  // system/init, thinking_tokens, post_turn_summary : sans usage
        }
    }

    /// Abandonne si aucune réponse n'arrive dans le délai imparti.
    private func armerLeDelai() {
        delai?.cancel()
        let travail = DispatchWorkItem { [weak self] in
            guard let self else { return }
            conclure(.failure(ErreurPont.silence))
        }
        delai = travail
        file.asyncAfter(deadline: .now() + PontClaude.silenceQuiFaitAbandonner,
                        execute: travail)
    }

    private func conclure(_ issue: Result<String, Error>) {
        delai?.cancel(); delai = nil
        guard let suite = attente else { return }
        attente = nil
        suite.resume(with: issue)
    }

    /// Le processus est mort alors qu'un tour était en cours : il ne faut pas
    /// laisser l'appelant attendre indéfiniment une réponse qui ne viendra pas.
    private func conclureBrutalement(code: Int32) {
        guard attente != nil else { return }
        conclure(.failure(ErreurPont.processusTermine(
            code: code, sortieErreur: texteErreur.trimmingCharacters(in: .whitespacesAndNewlines))))
    }
}
