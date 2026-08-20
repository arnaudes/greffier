import AppKit
import Foundation

/// Faire sortir un document de Greffier vers ce qui l'attend ailleurs.
///
/// Le compte rendu est produit en Markdown et en PDF. C'est suffisant pour
/// lire et pour archiver, mais pas pour ce que les gens en font vraiment :
/// un client annote dans Word, un collègue attend un email, et personne ne
/// veut recopier à la main un document qui existe déjà.
public enum Export {

    public enum Erreur: Error, LocalizedError {
        case conversionImpossible

        public var errorDescription: String? {
            "Le document n'a pas pu être converti."
        }
    }

    /// L'extension du fichier produit, pour que l'appelant nomme juste.
    public static let extensionTraitementDeTexte = "docx"

    /// Écrit un vrai document Word.
    ///
    /// Le format était **RTF**, au motif qu'un `.docx` aurait demandé de
    /// construire une archive et plusieurs fichiers XML. Le motif tenait ; le
    /// résultat, non — les tableaux devenaient des lignes trouées et le gras
    /// était retiré plutôt que rendu.
    ///
    /// La conversion que macOS propose a été essayée et mesurée : elle garde le
    /// gras et les couleurs, mais **perd tous les tableaux**. Le document est
    /// donc écrit directement, par ``RenduWord``.
    @discardableResult
    public static func versTraitementDeTexte(_ markdown: String, vers url: URL,
                                             charte: Charte = .parDefaut,
                                             surTitre: String = "",
                                             enteteWord: RenduWord.Entete? = nil) throws -> URL {
        let titre = enteteWord ?? RenduWord.Entete(titre: titreDe(markdown))
        return try RenduWord(charte: charte, surTitre: surTitre)
            .ecrire(markdown: markdown, entete: titre, vers: url)
    }

    /// Le titre de niveau 1 du compte rendu, qui va dans le bandeau.
    static func titreDe(_ markdown: String) -> String {
        for ligne in markdown.components(separatedBy: .newlines) where ligne.hasPrefix("# ") {
            return String(ligne.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return "Compte rendu de réunion"
    }

    /// Rend le Markdown lisible dans un traitement de texte.
    ///
    /// La conversion reste volontairement modeste : titres, gras, listes et
    /// tableaux rendus en texte aligné. Un rendu parfait exigerait un moteur
    /// complet, alors que ce fichier sert à annoter et à commenter — le PDF
    /// reste le document de référence.
    static func enTexteAttribue(_ markdown: String) -> NSAttributedString {
        let sortie = NSMutableAttributedString()
        let corps = NSFont.systemFont(ofSize: 11)
        let gras = NSFont.boldSystemFont(ofSize: 11)

        for ligne in markdown.components(separatedBy: .newlines) {
            let (texte, police, espaceAvant): (String, NSFont, CGFloat)
            switch true {
            case ligne.hasPrefix("# "):
                (texte, police, espaceAvant) = (String(ligne.dropFirst(2)),
                                                NSFont.boldSystemFont(ofSize: 17), 14)
            case ligne.hasPrefix("## "):
                (texte, police, espaceAvant) = (String(ligne.dropFirst(3)),
                                                NSFont.boldSystemFont(ofSize: 14), 12)
            case ligne.hasPrefix("### "):
                (texte, police, espaceAvant) = (String(ligne.dropFirst(4)), gras, 10)
            case ligne.hasPrefix("- ") || ligne.hasPrefix("* "):
                (texte, police, espaceAvant) = ("  • " + ligne.dropFirst(2), corps, 2)
            case ligne.hasPrefix(">"):
                (texte, police, espaceAvant) = (ligne.dropFirst()
                    .trimmingCharacters(in: .whitespaces), gras, 6)
            default:
                (texte, police, espaceAvant) = (ligne, corps, 2)
            }

            let paragraphe = NSMutableParagraphStyle()
            paragraphe.paragraphSpacingBefore = espaceAvant
            paragraphe.lineSpacing = 2
            sortie.append(NSAttributedString(
                string: sansMarques(texte) + "\n",
                attributes: [.font: police, .paragraphStyle: paragraphe]))
        }
        return sortie
    }

    /// Retire les marques de Markdown que la mise en forme rend déjà.
    static func sansMarques(_ texte: String) -> String {
        texte
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            // Les séparateurs de tableau n'ont pas de sens hors du Markdown.
            .replacingOccurrences(of: "|---", with: "")
            .replacingOccurrences(of: "---|", with: "")
            .replacingOccurrences(of: "|", with: "   ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - L'email

    /// Ouvre un brouillon dans le logiciel de courrier, sans jamais envoyer.
    ///
    /// La règle du produit ne change pas — **rien n'est envoyé** — mais préparer
    /// le brouillon évite le copier-coller, et c'est là que se perdent les
    /// mises en forme et les pièces jointes oubliées.
    ///
    /// - Returns: `false` si l'adresse `mailto:` a été refusée, ce qui arrive
    ///   quand aucun logiciel de courrier n'est configuré.
    @discardableResult
    public static func brouillonEmail(objet: String, corps: String,
                                      destinataire: String = "") -> Bool {
        var composants = URLComponents()
        composants.scheme = "mailto"
        composants.path = destinataire
        composants.queryItems = [
            URLQueryItem(name: "subject", value: objet),
            URLQueryItem(name: "body", value: corps),
        ]
        guard let url = composants.url else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// L'objet et le corps, tirés d'un email rédigé en Markdown.
    ///
    /// Claude produit un document avec un en-tête « **Objet :** … ». Le
    /// recopier à la main dans le logiciel de courrier serait exactement le
    /// geste qu'on cherche à éviter.
    public static func decouper(_ email: String) -> (objet: String, corps: String) {
        var objet = ""
        var corps: [String] = []
        var enTete = true

        for ligne in email.components(separatedBy: .newlines) {
            let propre = sansMarques(ligne)
            if enTete {
                if propre.lowercased().hasPrefix("objet :") {
                    objet = propre.dropFirst("objet :".count)
                        .trimmingCharacters(in: .whitespaces)
                    continue
                }
                // L'en-tête se termine à la première ligne de contenu.
                if propre.lowercased().hasPrefix("à :")
                    || propre.lowercased().hasPrefix("de :")
                    || propre.isEmpty || propre.hasPrefix("#") { continue }
                enTete = false
            }
            corps.append(propre)
        }
        return (objet.isEmpty ? "Compte rendu de notre réunion" : objet,
                corps.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
