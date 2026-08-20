import Foundation

/// Conversion du Markdown des comptes rendus en HTML à la charte UP.
///
/// Volontairement limité au sous-ensemble que les gabarits produisent
/// (spécification § 5.1) : titres, gras, italique, code, listes, tableaux,
/// encadrés et filets. Écrire un convertisseur complet serait du travail perdu,
/// et ajouter une dépendance externe à un outil local qui doit fonctionner
/// hors ligne serait pire.
///
/// Les correspondances avec les classes de `CHARTE-PDF-TEMPLATE.html` sont
/// celles du § 6 de la spécification.
public enum Markdown {

    /// Convertit le corps d'un compte rendu. Le titre de niveau 1 n'en fait pas
    /// partie : il va dans le bandeau, pas dans le texte.
    public static func versHTML(_ markdown: String) -> String {
        var html: [String] = []
        let lignes = markdown.components(separatedBy: .newlines)
        var i = 0
        var listeEnCours: String?  // "ul" ou "ol"
        var sectionOuverte = false

        func fermerListe() {
            if let l = listeEnCours { html.append("</\(l)>"); listeEnCours = nil }
        }
        func fermerSection() {
            if sectionOuverte { html.append("</div>"); sectionOuverte = false }
        }

        while i < lignes.count {
            let brute = lignes[i]
            let ligne = brute.trimmingCharacters(in: .whitespaces)

            // Ligne vide : elle ferme une liste, jamais une section.
            if ligne.isEmpty { fermerListe(); i += 1; continue }

            // Filet horizontal : sans usage, la charte pose ses propres
            // séparateurs par section.
            if ligne == "---" || ligne == "***" { fermerListe(); i += 1; continue }

            // Titre de niveau 1 : ignoré, il est déjà dans le bandeau.
            if ligne.hasPrefix("# ") { i += 1; continue }

            // Section — « ## 1. Titre » ou « ## Titre ».
            if ligne.hasPrefix("## ") {
                fermerListe(); fermerSection()
                let corps = String(ligne.dropFirst(3))
                let (numero, titre) = separerNumero(corps)
                html.append("<div class=\"sec\">")
                sectionOuverte = true
                let n = numero.map { "<span class=\"n\">\($0)</span>" } ?? ""
                html.append("<div class=\"sec-h\">\(n)<h2>\(enligne(titre))</h2></div>")
                html.append("<div class=\"sec-rule\"></div>")
                i += 1; continue
            }

            if ligne.hasPrefix("### ") {
                fermerListe()
                html.append("<h3>\(enligne(String(ligne.dropFirst(4))))</h3>")
                i += 1; continue
            }

            // Encadré. Un « ⚠ » en fait un avertissement, sinon c'est une
            // information — c'est la distinction du § 6.
            if ligne.hasPrefix(">") {
                fermerListe()
                var bloc: [String] = []
                while i < lignes.count {
                    let l = lignes[i].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix(">") else { break }
                    bloc.append(String(l.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                let texte = bloc.joined(separator: " ")
                // La comparaison porte sur la valeur Unicode et non sur le
                // caractère : « ⚠️ » s'écrit avec un sélecteur de variante, et
                // ne s'égale donc pas à « ⚠ » graphème pour graphème.
                let classe = texte.unicodeScalars.contains("\u{26A0}") ? "warn" : "info"
                html.append("<div class=\"call \(classe)\">\(enligne(texte))</div>")
                continue
            }

            // Tableau : une ligne de cellules suivie d'une ligne de séparation.
            if ligne.hasPrefix("|"), i + 1 < lignes.count,
               estSeparateurDeTableau(lignes[i + 1]) {
                fermerListe()
                let entetes = cellules(ligne)
                i += 2
                var corps: [[String]] = []
                while i < lignes.count {
                    let l = lignes[i].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix("|") else { break }
                    corps.append(cellules(l))
                    i += 1
                }
                html.append(tableau(entetes: entetes, corps: corps))
                continue
            }

            // Liste à puces ou numérotée.
            if ligne.hasPrefix("- ") || ligne.hasPrefix("* ") {
                if listeEnCours != "ul" { fermerListe(); html.append("<ul>"); listeEnCours = "ul" }
                html.append("<li>\(enligne(String(ligne.dropFirst(2))))</li>")
                i += 1; continue
            }
            if let point = ligne.firstIndex(of: "."),
               point > ligne.startIndex,
               ligne[ligne.startIndex..<point].allSatisfy(\.isNumber),
               ligne[ligne.index(after: point)...].hasPrefix(" ") {
                if listeEnCours != "ol" { fermerListe(); html.append("<ol>"); listeEnCours = "ol" }
                let texte = ligne[ligne.index(point, offsetBy: 2)...]
                html.append("<li>\(enligne(String(texte)))</li>")
                i += 1; continue
            }

            fermerListe()
            html.append("<p>\(enligne(ligne))</p>")
            i += 1
        }
        fermerListe(); fermerSection()
        return html.joined(separator: "\n")
    }

    // MARK: - Détails

    /// Sépare « 1. Titre » en numéro et titre. Un compte rendu numérote ses
    /// sections ; la charte affiche ce numéro à part.
    static func separerNumero(_ texte: String) -> (String?, String) {
        guard let point = texte.firstIndex(of: "."),
              texte[texte.startIndex..<point].allSatisfy(\.isNumber),
              texte.index(after: point) < texte.endIndex else { return (nil, texte) }
        let numero = String(texte[texte.startIndex...point])
        let reste = texte[texte.index(after: point)...].trimmingCharacters(in: .whitespaces)
        return reste.isEmpty ? (nil, texte) : (numero, reste)
    }

    static func estSeparateurDeTableau(_ ligne: String) -> Bool {
        let l = ligne.trimmingCharacters(in: .whitespaces)
        guard l.hasPrefix("|") else { return false }
        return l.allSatisfy { "|-: ".contains($0) } && l.contains("-")
    }

    static func cellules(_ ligne: String) -> [String] {
        var l = ligne.trimmingCharacters(in: .whitespaces)
        if l.hasPrefix("|") { l.removeFirst() }
        if l.hasSuffix("|") { l.removeLast() }
        return l.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func tableau(entetes: [String], corps: [[String]]) -> String {
        // Un tableau dont toutes les cellules d'en-tête sont vides est une
        // fiche d'identité, pas un tableau de données : c'est la forme du
        // bandeau de tête des comptes rendus.
        let fiche = entetes.allSatisfy(\.isEmpty)
        var html = fiche ? "<table class=\"fiche\">" : "<table>"
        if !fiche {
            html += "<thead><tr>" + entetes.map { "<th>\(enligne($0))</th>" }.joined() + "</tr></thead>"
        }
        html += "<tbody>"
        for ligne in corps {
            html += "<tr>" + ligne.map { "<td>\(enligne($0))</td>" }.joined() + "</tr>"
        }
        return html + "</tbody></table>"
    }

    /// Balisage à l'intérieur d'une ligne : code, gras, italique, liens.
    /// L'échappement passe en premier, sinon un `<` du texte casserait la page.
    static func enligne(_ texte: String) -> String {
        var s = texte
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        s = remplacer(s, motif: "`([^`]+)`", par: "<code>$1</code>")
        s = remplacer(s, motif: "\\*\\*([^*]+)\\*\\*", par: "<b>$1</b>")
        s = remplacer(s, motif: "(?<![\\*\\w])\\*([^*]+)\\*(?!\\*)", par: "<i>$1</i>")
        s = remplacer(s, motif: "\\[([^\\]]+)\\]\\(([^)]+)\\)", par: "<a href=\"$2\">$1</a>")
        return s
    }

    static func remplacer(_ texte: String, motif: String, par: String) -> String {
        guard let re = try? NSRegularExpression(pattern: motif) else { return texte }
        return re.stringByReplacingMatches(
            in: texte, range: NSRange(texte.startIndex..., in: texte), withTemplate: par)
    }
}
