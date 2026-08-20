import EventKit
import Foundation

/// Le calendrier professionnel, lu par EventKit.
///
/// EventKit plutôt que Microsoft Graph (chantier § 3.1) : les données ont été
/// comparées et concordent exactement, mais Graph exigerait soit une permission
/// applicative sur les boîtes de tout le tenant, soit un flux OAuth à
/// maintenir, là où EventKit demande une autorisation macOS, un clic, une fois.
/// Et fonctionne hors ligne.
public struct Calendrier: Sendable {

    /// Ce que l'outil propose de faire d'un événement.
    public enum ModePropose: String, Sendable {
        /// Rien : ce n'est pas une réunion. Un bloc personnel sans participant
        /// — une journée entière bloquée dans l'agenda — ne doit jamais être proposé.
        case aucun
        /// Visioconférence : micro et son système, en deux pistes.
        case visio
        /// Présentiel : micro seul, au bureau comme chez un client.
        case presentiel
    }

    public struct Reunion: Sendable, Identifiable {
        public var id: String
        public var titre: String
        public var debut: Date
        public var fin: Date
        public var lieu: String?
        public var participants: [String]
        public var enVisio: Bool
        public var calendrier: String

        public var mode: ModePropose {
            Calendrier.modePropose(nombreDeParticipants: participants.count, enVisio: enVisio)
        }

        public var enCours: Bool {
            let maintenant = Date()
            return debut <= maintenant && maintenant < fin
        }
    }

    /// **Liste blanche de calendriers.** Sans elle, l'outil proposerait
    /// d'enregistrer l'Assomption : un Mac porte souvent douze calendriers, dont les
    /// anniversaires, les jours fériés et des calendriers familiaux. Seul le
    /// calendrier professionnel Exchange compte.
    public var calendriersRetenus: Set<String>

    public init(calendriersRetenus: Set<String> = ["Calendrier"]) {
        self.calendriersRetenus = calendriersRetenus
    }

    // MARK: - Détection du mode

    /// Décide de ce qu'on propose, à partir des seuls faits de l'événement.
    ///
    /// Le nombre de participants est un bien meilleur détecteur qu'un plafond
    /// de durée : il écarte par nature les blocs personnels, quelle que soit
    /// leur longueur.
    ///
    /// **Le lieu ne filtre pas, il informe.** Un déjeuner professionnel sera
    /// donc proposé et ignoré d'un regard — c'est le prix, modeste, de ne
    /// jamais rater une visite client.
    public static func modePropose(nombreDeParticipants: Int, enVisio: Bool) -> ModePropose {
        guard nombreDeParticipants > 0 else { return .aucun }
        return enVisio ? .visio : .presentiel
    }

    /// Reconnaît une visioconférence à ce que l'invitation contient.
    /// Les marqueurs sont ceux qu'on rencontre réellement dans les invitations
    /// reçues, Teams en tête, puis Meet et Zoom.
    public static func estUneVisio(notes: String?, lieu: String?, url: URL?) -> Bool {
        let marqueurs = ["teams.microsoft.com", "Réunion Microsoft Teams",
                         "Microsoft Teams meeting", "zoom.us", "meet.google.com",
                         "whereby.com", "webex.com"]
        let matiere = [notes, lieu, url?.absoluteString].compactMap { $0 }.joined(separator: " ")
        return marqueurs.contains { matiere.localizedCaseInsensitiveContains($0) }
    }

    // MARK: - Lecture

    public static func autoriser() async -> Bool {
        (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    public static var autorisationAccordee: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Les réunions du jour, filtrées par la liste blanche.
    public func reunionsDuJour(_ jour: Date = Date()) -> [Reunion] {
        let magasin = EKEventStore()
        let calendrier = Foundation.Calendar.current
        let debut = calendrier.startOfDay(for: jour)
        guard let fin = calendrier.date(byAdding: .day, value: 1, to: debut) else { return [] }

        let retenus = magasin.calendars(for: .event)
            .filter { calendriersRetenus.contains($0.title) }
        guard !retenus.isEmpty else { return [] }

        let predicat = magasin.predicateForEvents(withStart: debut, end: fin, calendars: retenus)
        return magasin.events(matching: predicat)
            .filter { !$0.isAllDay }
            .map { evenement in
                Reunion(
                    id: evenement.eventIdentifier ?? UUID().uuidString,
                    titre: evenement.title ?? "Sans titre",
                    debut: evenement.startDate,
                    fin: evenement.endDate,
                    lieu: evenement.location,
                    participants: (evenement.attendees ?? []).compactMap { participant in
                        participant.name ?? participant.url.absoluteString
                            .replacingOccurrences(of: "mailto:", with: "")
                    },
                    enVisio: Calendrier.estUneVisio(notes: evenement.notes,
                                                    lieu: evenement.location,
                                                    url: evenement.url),
                    calendrier: evenement.calendar.title)
            }
            .sorted { $0.debut < $1.debut }
    }

    /// Ce que la barre de menus doit montrer : la réunion en cours, sinon la
    /// prochaine à venir. Les événements qui ne sont pas des réunions sont
    /// écartés — c'est là que la détection du mode gagne son utilité.
    public func reunionAProposer(maintenant: Date = Date()) -> Reunion? {
        let candidates = reunionsDuJour(maintenant).filter { $0.mode != .aucun }
        return candidates.first { $0.enCours }
            ?? candidates.first { $0.debut > maintenant }
    }

    /// Tous les calendriers de la machine, pour que l'écran des réglages
    /// permette de composer la liste blanche plutôt que de la deviner.
    public static func calendriersDisponibles() -> [String] {
        EKEventStore().calendars(for: .event).map(\.title).sorted()
    }
}
