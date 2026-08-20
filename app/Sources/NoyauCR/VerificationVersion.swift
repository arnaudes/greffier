import Foundation

/// Savoir qu'une version plus récente existe.
///
/// **Ce qui déclenche n'est pas un envoi de code, c'est une version publiée.**
/// Pousser sur GitHub ne prévient personne, et c'est voulu : sinon une
/// correction de commentaire ferait apparaître un bandeau chez tout le monde.
/// La publication d'une *release* est un geste délibéré — « cette version-là
/// vaut le coup d'être installée » — et son étiquette porte le CalVer.
///
/// L'application ne se remplace **jamais** toute seule : écraser le bundle
/// d'une application en cours d'exécution la fait planter, mesuré le
/// 19/08/2026. Elle prévient, l'utilisateur installe.
public enum VerificationVersion {

    /// Le dépôt interrogé. Public : aucune authentification, donc aucun jeton à
    /// distribuer aux utilisateurs.
    public static let depotParDefaut = "arnaudes/greffier"

    /// Une version publiée, telle que GitHub la décrit.
    public struct Publication: Sendable, Equatable {
        public var version: String
        public var page: URL
        public var notes: String?
        /// Le fichier joint à télécharger, s'il y en a un. Sans lui, il faut
        /// recompiler soi-même — ce qui suppose les outils de développement.
        public var telechargement: URL?

        public init(version: String, page: URL, notes: String? = nil,
                    telechargement: URL? = nil) {
            self.version = version
            self.page = page
            self.notes = notes
            self.telechargement = telechargement
        }
    }

    public enum Erreur: Error {
        case reseauIndisponible
        case reponseIllisible
        case aucunePublication
    }

    // MARK: - Comparer deux CalVer

    /// `a` est-elle antérieure à `b` ?
    ///
    /// Comparaison composante par composante, en nombres et non en texte :
    /// « 2026.08.20.9 » précède « 2026.08.20.10 », ce qu'un tri alphabétique
    /// aurait inversé.
    public static func estAnterieure(_ a: String, _ b: String) -> Bool {
        let gauche = composantes(a)
        let droite = composantes(b)
        for i in 0..<max(gauche.count, droite.count) {
            let x = i < gauche.count ? gauche[i] : 0
            let y = i < droite.count ? droite[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// Les nombres d'une étiquette de version, quels que soient les ornements.
    ///
    /// Une étiquette écrite « v2026.08.20.01 » doit valoir « 2026.08.20.01 » :
    /// l'usage du « v » est répandu, et l'oublier ferait croire à une version
    /// inconnue.
    static func composantes(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    // MARK: - Interroger GitHub

    /// La dernière version publiée, ou `nil` si le dépôt n'en a aucune.
    ///
    /// - Parameter session: injectable pour éprouver la lecture sans réseau.
    public static func derniere(depot: String = depotParDefaut,
                                session: URLSession = .shared) async throws -> Publication? {
        guard let url = URL(string: "https://api.github.com/repos/\(depot)/releases/latest")
        else { throw Erreur.reponseIllisible }

        var requete = URLRequest(url: url)
        requete.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Une attente courte : cette vérification est un confort, jamais une
        // étape. Elle ne doit pas retarder l'ouverture de l'application.
        requete.timeoutInterval = 8

        let data: Data
        let reponse: URLResponse
        do { (data, reponse) = try await session.data(for: requete) } catch {
            throw Erreur.reseauIndisponible
        }
        if let http = reponse as? HTTPURLResponse {
            // 404 : le dépôt n'a encore publié aucune version. Ce n'est pas une
            // panne, c'est l'état normal d'un dépôt neuf.
            if http.statusCode == 404 { return nil }
            guard (200..<300).contains(http.statusCode) else { throw Erreur.reseauIndisponible }
        }
        return try lire(data)
    }

    /// Extrait ce qui nous intéresse de la réponse de GitHub.
    static func lire(_ data: Data) throws -> Publication? {
        guard let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Erreur.reponseIllisible }
        guard let tag = objet["tag_name"] as? String,
              let lien = objet["html_url"] as? String,
              let page = URL(string: lien) else { throw Erreur.reponseIllisible }

        let notes = (objet["body"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Le premier fichier joint : c'est l'application prête à installer,
        // quand elle est publiée ainsi.
        let joints = objet["assets"] as? [[String: Any]] ?? []
        let telechargement = joints
            .compactMap { $0["browser_download_url"] as? String }
            .first
            .flatMap(URL.init(string:))

        return Publication(version: tag, page: page,
                           notes: (notes?.isEmpty ?? true) ? nil : notes,
                           telechargement: telechargement)
    }

    // MARK: - Décider s'il faut prévenir

    /// Faut-il signaler cette publication à l'utilisateur ?
    ///
    /// Trois raisons de se taire : elle n'est pas plus récente, il a demandé
    /// qu'on ne le prévienne pas, ou il a déjà écarté cette version-là. Une
    /// notification qu'on ne peut pas faire taire devient un reproche.
    public static func doitPrevenir(_ publication: Publication?,
                                    versionActuelle: String,
                                    prevenir: Bool,
                                    versionEcartee: String?) -> Bool {
        guard prevenir, let publication else { return false }
        guard estAnterieure(versionActuelle, publication.version) else { return false }
        guard publication.version != versionEcartee else { return false }
        return true
    }

    /// A-t-on déjà regardé aujourd'hui ?
    ///
    /// Une fois par jour suffit : les versions ne se publient pas à la minute,
    /// et l'API publique de GitHub limite le nombre d'appels par adresse.
    public static func aDejaRegarde(_ derniereFois: Date?,
                                    maintenant: Date = Date()) -> Bool {
        guard let derniereFois else { return false }
        return maintenant.timeIntervalSince(derniereFois) < 24 * 3600
    }
}
