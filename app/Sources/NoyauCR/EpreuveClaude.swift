import Foundation

/// Claude Code répond-il vraiment ?
///
/// Le contrôle des prérequis se contentait de **trouver le programme**. Or un
/// programme installé mais non connecté se comporte exactement comme un
/// programme absent — à ceci près qu'il ne le dit qu'au moment de rédiger,
/// c'est-à-dire après la réunion, quand la matière est captée et qu'il est trop
/// tard pour y remédier.
///
/// La seule façon de distinguer « installé » d'« utilisable » est de lui
/// poser une question et d'attendre la réponse. Elle est volontairement
/// minuscule : un mot demandé, un mot rendu.
public enum EpreuveClaude {

    public enum Verdict: Sendable, Equatable {
        /// Le programme répond : tout est en place.
        case repond
        /// Le programme est là mais n'a pas répondu — le plus souvent parce
        /// qu'il n'est pas connecté.
        case muet(String)
        /// Le programme est introuvable sur cette machine.
        case introuvable

        public var satisfait: Bool { self == .repond }

        public var libelle: String {
            switch self {
            case .repond: "Claude Code répond."
            case .muet: "Claude Code est installé, mais n'a pas répondu."
            case .introuvable: "Claude Code est introuvable."
            }
        }

        /// Ce qu'il faut faire, dit en français et sans jargon.
        public var remede: String {
            switch self {
            case .repond:
                ""
            case .muet:
                "Ouvrez le Terminal, tapez « claude », et connectez-vous avec "
                    + "votre compte. C'est votre abonnement qui porte la rédaction : "
                    + "il n'y a pas de facturation séparée."
            case .introuvable:
                "Installez Claude Code depuis claude.com/claude-code, puis "
                    + "connectez-vous une première fois en tapant « claude » dans "
                    + "le Terminal."
            }
        }
    }

    /// Combien de temps on attend avant de renoncer.
    ///
    /// Le premier démarrage est plus lent que les suivants ; au-delà, ce n'est
    /// plus de la lenteur, c'est une authentification qui n'aboutira pas.
    public static let patience: TimeInterval = 45

    /// Pose une question minuscule et regarde ce qui revient.
    ///
    /// - Parameter modele: le modèle à employer. Le plus léger suffit : on ne
    ///   mesure pas la qualité d'une réponse, seulement qu'il y en ait une.
    public static func eprouver(config: ConfigClaude) async -> Verdict {
        guard LocalisationClaude.resoudre(config.binaire) != nil else { return .introuvable }

        let pont = PontClaude(config: ConfigClaude(
            binaire: config.binaire,
            modele: config.modele,
            promptSysteme: "Tu réponds par un seul mot, sans ponctuation ni politesse."))
        defer { pont.arreter() }

        do {
            try pont.demarrer()
            let reponse = try await avecDelaiDeGarde(patience) {
                try await pont.envoyer("Réponds exactement : prêt")
            }
            let propre = reponse.trimmingCharacters(in: .whitespacesAndNewlines)
            // N'importe quelle réponse non vide prouve que la chaîne fonctionne.
            // Exiger le mot exact ferait échouer sur une politesse.
            return propre.isEmpty ? .muet("réponse vide") : .repond
        } catch {
            return .muet(error.localizedDescription)
        }
    }

    /// Un délai de garde : sans lui, une authentification qui attend une saisie
    /// dans un terminal invisible bloquerait l'écran de bienvenue sans fin.
    static func avecDelaiDeGarde<T: Sendable>(
        _ delai: TimeInterval,
        _ travail: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { groupe in
            groupe.addTask { try await travail() }
            groupe.addTask {
                try await Task.sleep(nanoseconds: UInt64(delai * 1_000_000_000))
                throw Erreur.tropLong
            }
            guard let premier = try await groupe.next() else { throw Erreur.tropLong }
            groupe.cancelAll()
            return premier
        }
    }

    enum Erreur: Error, LocalizedError {
        case tropLong
        var errorDescription: String? {
            "Claude Code n'a pas répondu dans le temps imparti. "
                + "C'est le plus souvent qu'il n'est pas connecté."
        }
    }
}
