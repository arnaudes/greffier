import Foundation

/// La forme des documents produits — le PDF comme le document Word.
///
/// Elle vivait dans un gabarit HTML posé à côté de l'application, hors du
/// dépôt : c'était la bonne intention, puisque les couleurs et le nom d'une
/// société n'ont rien à faire dans un dépôt public. Mais l'effet de bord était
/// rude : **qui n'avait pas ce fichier n'obtenait aucun PDF du tout.**
///
/// La charte est donc décrite ici en valeurs, avec un jeu par défaut sobre et
/// anonyme. Chacun peut la remplacer par la sienne, depuis les réglages ou en
/// corrigeant le fichier à la main. Rien n'y désigne personne.
public struct Charte: Codable, Sendable, Equatable {

    // MARK: - Les couleurs, en hexadécimal « RRGGBB »

    /// Filets de section, numéros, liens : ce qui porte l'identité.
    public var accent: String
    /// Le dégradé du bandeau de tête, du plus sombre au plus clair.
    public var bandeauDebut: String
    public var bandeauFin: String
    /// Le fond des en-têtes de tableau.
    public var enteteTableau: String

    /// Les titres.
    public var encreForte: String
    /// Le corps du texte.
    public var encre: String
    /// Les libellés et les mentions secondaires.
    public var encreDouce: String
    /// Le pied de page, la pagination.
    public var encreFaible: String

    /// Les filets de tableau.
    public var filet: String
    /// Le fond d'une ligne sur deux.
    public var fondAlterne: String

    /// Les encadrés : une information, puis un avertissement.
    public var information: String
    public var avertissement: String

    // MARK: - La typographie

    /// Le nom de la police. Vide signifie « celle du système », qui est le
    /// choix sûr : une police absente chez le destinataire est remplacée par
    /// Word sans prévenir, et le document s'abîme à l'ouverture.
    public var police: String
    /// Le corps du texte, en points.
    public var tailleCorps: Double

    // MARK: - Le jeu par défaut

    public static let parDefaut = Charte(
        accent: "2563EB",
        bandeauDebut: "1F3C8E", bandeauFin: "3168EC",
        enteteTableau: "172033",
        encreForte: "0F172A", encre: "1E293B",
        encreDouce: "475569", encreFaible: "94A3B8",
        filet: "E2E8F0", fondAlterne: "F1F5F9",
        information: "2563EB", avertissement: "B45309",
        police: "", tailleCorps: 10.5)

    public init(accent: String, bandeauDebut: String, bandeauFin: String,
                enteteTableau: String, encreForte: String, encre: String,
                encreDouce: String, encreFaible: String, filet: String,
                fondAlterne: String, information: String, avertissement: String,
                police: String, tailleCorps: Double) {
        self.accent = accent
        self.bandeauDebut = bandeauDebut
        self.bandeauFin = bandeauFin
        self.enteteTableau = enteteTableau
        self.encreForte = encreForte
        self.encre = encre
        self.encreDouce = encreDouce
        self.encreFaible = encreFaible
        self.filet = filet
        self.fondAlterne = fondAlterne
        self.information = information
        self.avertissement = avertissement
        self.police = police
        self.tailleCorps = tailleCorps
    }

    /// Un décodage tolérant : une charte écrite à la main où il manque une
    /// couleur doit s'ouvrir quand même, la valeur par défaut prenant le
    /// relais. Sans cela, une faute de frappe priverait de tout document.
    public init(from decodeur: Decoder) throws {
        let c = try decodeur.container(keyedBy: CodingKeys.self)
        let d = Charte.parDefaut
        func lire(_ cle: CodingKeys, _ secours: String) -> String {
            let v = (try? c.decode(String.self, forKey: cle)) ?? secours
            return Charte.estUneCouleur(v) || cle == .police ? v : secours
        }
        accent = lire(.accent, d.accent)
        bandeauDebut = lire(.bandeauDebut, d.bandeauDebut)
        bandeauFin = lire(.bandeauFin, d.bandeauFin)
        enteteTableau = lire(.enteteTableau, d.enteteTableau)
        encreForte = lire(.encreForte, d.encreForte)
        encre = lire(.encre, d.encre)
        encreDouce = lire(.encreDouce, d.encreDouce)
        encreFaible = lire(.encreFaible, d.encreFaible)
        filet = lire(.filet, d.filet)
        fondAlterne = lire(.fondAlterne, d.fondAlterne)
        information = lire(.information, d.information)
        avertissement = lire(.avertissement, d.avertissement)
        police = (try? c.decode(String.self, forKey: .police)) ?? d.police
        let taille = (try? c.decode(Double.self, forKey: .tailleCorps)) ?? d.tailleCorps
        // Une taille absurde produirait un document illisible sans rien dire.
        tailleCorps = (7...16).contains(taille) ? taille : d.tailleCorps
    }

    /// Six chiffres hexadécimaux, sans dièse. C'est la seule forme que le
    /// Word accepte, et le CSS s'en accommode.
    public static func estUneCouleur(_ valeur: String) -> Bool {
        valeur.count == 6 && valeur.allSatisfy(\.isHexDigit)
    }

    // MARK: - Le fichier

    /// La charte vit avec les documents, pas avec l'application : on la
    /// retrouve en sauvegardant son dossier de travail.
    public static func chemin(racine: URL) -> URL {
        racine.appendingPathComponent("charte.json")
    }

    public static func charger(racine: URL) -> Charte {
        guard let donnees = try? Data(contentsOf: chemin(racine: racine)),
              let charte = try? JSONDecoder().decode(Charte.self, from: donnees)
        else { return .parDefaut }
        return charte
    }

    public func enregistrer(racine: URL) throws {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
        try encodeur.encode(self).write(to: Charte.chemin(racine: racine), options: .atomic)
    }

    /// La pile de polices du CSS. La police choisie d'abord, celles du système
    /// ensuite — un PDF ne doit jamais dépendre d'une police absente.
    public var pileCSS: String {
        let systeme = "ui-sans-serif,system-ui,-apple-system,\"Segoe UI\","
            + "Roboto,Helvetica,Arial,sans-serif"
        return police.isEmpty ? systeme : "\"\(police)\",\(systeme)"
    }

    /// La police du document Word. Calibri par défaut : c'est celle que Word
    /// installe partout, y compris sur Windows, où l'application ira un jour.
    public var policeWord: String { police.isEmpty ? "Calibri" : police }
}
