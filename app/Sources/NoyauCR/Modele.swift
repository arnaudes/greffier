import Foundation

// Le contrat d'échange avec Claude, tel qu'il est fixé par
// docs/SPEC-generation.md § 3.3 et § 4. Les noms de champs sont ceux du JSON :
// la spécification fait foi, le code s'y conforme.

/// Les huit familles de questions (spécification § 3.2).
///
/// Les sept premières naissent d'un doute. La huitième, `chiffres`, couvre ce
/// dont Claude ne peut pas douter — une valeur plausible mais fausse ne se
/// signale jamais d'elle-même.
public enum Famille: String, Codable, CaseIterable, Sendable {
    case participants
    case quiADitQuoi = "qui-a-dit-quoi"
    case motsDouteux = "mots-douteux"
    case datesRelatives = "dates-relatives"
    case decisionOuPiste = "decision-ou-piste"
    case actionsPorteurs = "actions-porteurs"
    case ceQuiNeSortPas = "ce-qui-ne-sort-pas"
    case chiffres

    /// Libellé affiché à côté de la question.
    public var libelle: String {
        switch self {
        case .participants: "les participants"
        case .quiADitQuoi: "qui a dit quoi"
        case .motsDouteux: "mot douteux"
        case .datesRelatives: "date relative"
        case .decisionOuPiste: "décision ou piste"
        case .actionsPorteurs: "action et porteur"
        case .ceQuiNeSortPas: "ce qui ne sort pas"
        case .chiffres: "relecture des chiffres"
        }
    }
}

/// Le contrôle que l'interface présente pour répondre.
public enum TypeQuestion: String, Codable, Sendable {
    case choixUnique = "choix-unique"
    case choixMultiple = "choix-multiple"
    case ouiNon = "oui-non"
    case date
    case texte
}

/// De quoi transformer une réponse en entrée de lexique.
///
/// La question dit qu'elle enrichit le lexique ; elle ne disait pas **quoi**
/// enrichir. Sans ces trois informations, une réponse comme « Menuiseries Vidal » ne
/// suffit pas : on ignore la faute à retenir, la nature du terme, et ce qu'il
/// faudrait en savoir pour rédiger juste.
///
/// Le terme correct, lui, ne vient jamais d'ici : c'est la réponse de l'utilisateur.
public struct AmorceLexique: Codable, Sendable, Equatable {
    /// Le mot tel qu'il apparaît dans le transcript — la faute à retenir, pour
    /// qu'elle ne repose plus jamais de question.
    public var variante: String?
    public var categorie: Categorie
    /// Ce que le transcript apprend du terme, ou rien. Une note vide est
    /// honnête ; une note vraisemblable et fausse contaminerait tous les
    /// comptes rendus suivants (spécification § 8.2).
    public var note: String?

    public init(variante: String? = nil, categorie: Categorie, note: String? = nil) {
        self.variante = variante
        self.categorie = categorie
        self.note = note
    }

    /// L'entrée à intégrer, une fois le terme connu.
    public func entree(pourTerme terme: String) -> EntreeLexique {
        let propre = terme.trimmingCharacters(in: .whitespacesAndNewlines)
        var retenues: [String] = []
        if let variante = variante?.trimmingCharacters(in: .whitespacesAndNewlines),
           !variante.isEmpty,
           Lexique.normaliser(variante) != Lexique.normaliser(propre) {
            retenues.append(variante)
        }
        let notePropre = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return EntreeLexique(terme: propre, variantes: retenues, categorie: categorie,
                             note: (notePropre?.isEmpty ?? true) ? nil : notePropre)
    }
}

/// Une question posée avant rédaction.
public struct Question: Codable, Identifiable, Sendable {
    public var id: String
    public var famille: Famille
    public var question: String
    /// L'extrait du transcript qui motive la question. C'est le seul moyen de
    /// répondre sans réécouter la réunion : il n'est jamais facultatif.
    public var extrait: String
    public var horodatage: String?
    public var occurrences: Int?
    public var type: TypeQuestion
    public var options: [String]?
    public var saisieLibre: Bool
    public var enrichitLexique: Bool
    /// Ce qu'il faut savoir pour créer l'entrée, quand la question enrichit le
    /// lexique. Absent partout ailleurs.
    public var lexique: AmorceLexique?
    public var justification: String?

    enum CodingKeys: String, CodingKey {
        case id, famille, question, extrait, horodatage, occurrences, type, options
        case saisieLibre = "saisie_libre"
        case enrichitLexique = "enrichit_lexique"
        case lexique
        case justification
    }

    /// Coût de réponse, qui décide de l'ordre d'affichage (spécification § 3.4).
    ///
    /// Les questions à un clic passent en premier quelle que soit leur famille :
    /// une série de réponses rapides s'enchaîne sans rupture de rythme, alors
    /// qu'un arbitrage placé en troisième position arrête tout.
    public var vague: Int {
        switch type {
        case .texte: 4
        case .choixMultiple: 3
        case .ouiNon: 1
        case .choixUnique: (options?.count ?? 0) <= 2 ? 1 : 2
        case .date: 2
        }
    }
}

/// La réponse de l'utilisateur à une question.
///
/// `reponse` vaut `nil` quand la question a été laissée de côté : le point est
/// alors traité comme non établi — écrit au conditionnel en le signalant, ou
/// rangé dans « Points ouverts ». Claude ne tranche jamais à sa place.
public struct Reponse: Codable, Sendable {
    public var id: String
    public var reponse: String?
    public var enrichirLexique: Bool?

    enum CodingKeys: String, CodingKey {
        case id, reponse
        case enrichirLexique = "enrichir_lexique"
    }

    public init(id: String, reponse: String?, enrichirLexique: Bool? = nil) {
        self.id = id
        self.reponse = reponse
        self.enrichirLexique = enrichirLexique
    }
}

public struct ListeQuestions: Codable, Sendable {
    public var questions: [Question]
    public init(questions: [Question]) { self.questions = questions }

    /// Les questions dans l'ordre où l'interface doit les présenter : par coût
    /// croissant, puis par famille, puis dans l'ordre du transcript.
    public var ordonnees: [Question] {
        Array(questions.enumerated()).sorted { (g: (offset: Int, element: Question),
                                                d: (offset: Int, element: Question)) -> Bool in
            if g.element.vague != d.element.vague { return g.element.vague < d.element.vague }
            let fg = Famille.allCases.firstIndex(of: g.element.famille) ?? 0
            let fd = Famille.allCases.firstIndex(of: d.element.famille) ?? 0
            if fg != fd { return fg < fd }
            let sg = ListeQuestions.secondes(g.element.horodatage)
            let sd = ListeQuestions.secondes(d.element.horodatage)
            if sg != sd { return sg < sd }
            return g.offset < d.offset
        }.map(\.element)
    }

    /// Convertit un horodatage `mm:ss` en secondes. Une valeur absente ou
    /// illisible est renvoyée en fin de liste plutôt que traitée comme zéro.
    static func secondes(_ horodatage: String?) -> Int {
        guard let h = horodatage else { return .max }
        let parts = h.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return .max }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

public struct ListeReponses: Codable, Sendable {
    public var reponses: [Reponse]
    public init(reponses: [Reponse]) { self.reponses = reponses }
}
