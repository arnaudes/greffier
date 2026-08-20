import Foundation

/// Ce qu'on demande à Claude en plus, pour un dossier donné.
///
/// Un client n'attend pas ce qu'attend l'autre. L'un veut des comptes rendus
/// serrés et des tableaux ; l'autre suit un dossier de subvention où chaque
/// jalon doit être qualifié de contractuel ou d'indicatif. Une charte unique
/// pour tous les dossiers oblige à écrire des consignes si générales qu'elles
/// ne servent plus.
///
/// Le fichier vit **avec le dossier**, en Markdown : il se lit, se corrige à la
/// main, et suit le dossier si on le déplace.
public struct ConsignesDossier: Sendable, Equatable {

    public var texte: String

    public init(texte: String = "") { self.texte = texte }

    public var estVide: Bool {
        texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Le fichier qui les porte, à la racine du dossier du client.
    public static func chemin(racine: URL, projet: String) -> URL {
        Rangement.dossierProjet(racine: racine, projet: projet)
            .appendingPathComponent("Consignes de rédaction.md")
    }

    public static func charger(racine: URL, projet: String) -> ConsignesDossier {
        let url = chemin(racine: racine, projet: projet)
        let brut = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // L'en-tête est là pour le lecteur humain, pas pour Claude : le fichier
        // doit s'expliquer quand on tombe dessus dans le Finder.
        let sansEntete = brut
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("_") }
            .joined(separator: "\n")
        return ConsignesDossier(texte: sansEntete.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func enregistrer(racine: URL, projet: String) throws {
        let url = ConsignesDossier.chemin(racine: racine, projet: projet)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        guard !estVide else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let document = """
            # Consignes de rédaction — \(projet)

            _Ce qui suit est ajouté aux consignes envoyées à Claude pour ce dossier
            seulement. Vous pouvez le corriger ici, ou depuis Greffier. Les lignes
            commençant par # ou _ ne sont pas transmises._

            \(texte.trimmingCharacters(in: .whitespacesAndNewlines))

            """
        try document.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Ajoute une consigne à celles qui existent, sans doublon.
    public mutating func ajouter(_ consigne: String) {
        let propre = consigne.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return }
        let ligne = propre.hasPrefix("-") ? propre : "- " + propre
        guard !texte.contains(propre) else { return }
        texte = estVide ? ligne : texte + "\n" + ligne
    }
}
