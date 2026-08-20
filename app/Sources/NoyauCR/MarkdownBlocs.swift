import Foundation

extension Markdown {

    /// Ce qu'un compte rendu contient, une fois lu.
    ///
    /// Le HTML du PDF et le document Word partent tous deux d'ici. Deux
    /// analyseurs séparés auraient divergé à la première évolution — un
    /// tableau reconnu d'un côté, pas de l'autre, sans que rien ne le signale.
    public enum Bloc: Sendable, Equatable {
        /// « ## 1. Titre » : le numéro est affiché à part.
        case section(numero: String?, titre: String)
        case sousTitre(String)
        case paragraphe(String)
        /// Un encadré. Un « ⚠ » en fait un avertissement.
        case encadre(avertissement: Bool, texte: String)
        case liste(ordonnee: Bool, elements: [String])
        /// Une fiche est un tableau sans en-tête : la carte d'identité de tête.
        case tableau(entetes: [String], lignes: [[String]], fiche: Bool)
    }

    /// Un morceau de ligne et sa mise en forme.
    public struct Fragment: Sendable, Equatable {
        public var texte: String
        public var gras = false
        public var italique = false
        public var code = false
        public init(texte: String, gras: Bool = false, italique: Bool = false,
                    code: Bool = false) {
            self.texte = texte
            self.gras = gras
            self.italique = italique
            self.code = code
        }
    }

    /// Lit un compte rendu. Le titre de niveau 1 est écarté : il va dans le
    /// bandeau de tête, pas dans le corps.
    public static func analyser(_ markdown: String) -> [Bloc] {
        var blocs: [Bloc] = []
        let lignes = markdown.components(separatedBy: .newlines)
        var i = 0

        /// Ce qui s'accumule tant que la liste continue.
        var listeOrdonnee = false
        var elements: [String] = []
        func fermerListe() {
            guard !elements.isEmpty else { return }
            blocs.append(.liste(ordonnee: listeOrdonnee, elements: elements))
            elements = []
        }

        while i < lignes.count {
            let ligne = lignes[i].trimmingCharacters(in: .whitespaces)

            if ligne.isEmpty || ligne == "---" || ligne == "***" {
                fermerListe(); i += 1; continue
            }
            if ligne.hasPrefix("# ") { fermerListe(); i += 1; continue }

            if ligne.hasPrefix("## ") {
                fermerListe()
                let (numero, titre) = separerNumero(String(ligne.dropFirst(3)))
                blocs.append(.section(numero: numero, titre: titre))
                i += 1; continue
            }
            if ligne.hasPrefix("### ") {
                fermerListe()
                blocs.append(.sousTitre(String(ligne.dropFirst(4))))
                i += 1; continue
            }

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
                // La comparaison porte sur la valeur Unicode : « ⚠️ » s'écrit
                // avec un sélecteur de variante et ne s'égale pas à « ⚠ ».
                blocs.append(.encadre(avertissement: texte.unicodeScalars.contains("\u{26A0}"),
                                      texte: texte))
                continue
            }

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
                blocs.append(.tableau(entetes: entetes, lignes: corps,
                                      fiche: entetes.allSatisfy(\.isEmpty)))
                continue
            }

            if ligne.hasPrefix("- ") || ligne.hasPrefix("* ") {
                if listeOrdonnee { fermerListe() }
                listeOrdonnee = false
                elements.append(String(ligne.dropFirst(2)))
                i += 1; continue
            }
            if let point = ligne.firstIndex(of: "."), point > ligne.startIndex,
               ligne[ligne.startIndex..<point].allSatisfy(\.isNumber),
               ligne[ligne.index(after: point)...].hasPrefix(" ") {
                if !listeOrdonnee { fermerListe() }
                listeOrdonnee = true
                elements.append(String(ligne[ligne.index(point, offsetBy: 2)...]))
                i += 1; continue
            }

            fermerListe()
            blocs.append(.paragraphe(ligne))
            i += 1
        }
        fermerListe()
        return blocs
    }

    // MARK: - Le balisage à l'intérieur d'une ligne

    /// Découpe une ligne en morceaux mis en forme.
    ///
    /// Le rendu Word en a besoin : Word ne connaît pas les astérisques, il
    /// connaît des passages gras. Le convertisseur d'origine se contentait de
    /// **retirer** les astérisques — l'emphase disparaissait avec elles.
    public static func fragments(_ ligne: String) -> [Fragment] {
        var sortie: [Fragment] = []
        var courant = ""
        var gras = false, italique = false, code = false
        let caracteres = Array(ligne)
        var i = 0

        func poser() {
            guard !courant.isEmpty else { return }
            sortie.append(Fragment(texte: courant, gras: gras, italique: italique, code: code))
            courant = ""
        }

        while i < caracteres.count {
            let c = caracteres[i]
            // Le code littéral se lit tel quel : à l'intérieur, une astérisque
            // est une astérisque.
            if c == "`" {
                poser(); code.toggle(); i += 1; continue
            }
            if !code, c == "*" {
                if i + 1 < caracteres.count, caracteres[i + 1] == "*" {
                    poser(); gras.toggle(); i += 2; continue
                }
                // Une astérisque isolée au milieu d'un mot n'ouvre rien :
                // « 3*4 » ne doit pas basculer le reste en italique.
                let avant = i > 0 ? caracteres[i - 1] : " "
                let apres = i + 1 < caracteres.count ? caracteres[i + 1] : " "
                if italique || (!avant.isLetter && !avant.isNumber && apres != " ") {
                    poser(); italique.toggle(); i += 1; continue
                }
            }
            courant.append(c)
            i += 1
        }
        poser()
        // Une emphase jamais refermée ne doit pas manger la fin de la ligne :
        // les fragments déjà posés gardent leur forme, c'est tout.
        return sortie
    }
}
