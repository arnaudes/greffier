import Foundation

/// Nature d'une entrée du lexique (spécification § 8).
public enum Categorie: String, Codable, Sendable, CaseIterable {
    case personne, entreprise, projet, outil, sigle, lieu, expression
}

/// Une entrée du lexique.
///
/// `variantes` recense les erreurs de transcription déjà rencontrées : elles
/// suppriment l'hésitation quand la faute est connue. `note` ne corrige rien —
/// elle sert à rédiger juste, pas seulement à orthographier juste, et reste
/// vide plutôt que plausible quand le transcript ne dit rien du terme.
public struct EntreeLexique: Codable, Sendable, Equatable {
    public var terme: String
    public var variantes: [String]
    public var categorie: Categorie
    public var note: String?

    public init(terme: String, variantes: [String] = [], categorie: Categorie, note: String? = nil) {
        self.terme = terme
        self.variantes = variantes
        self.categorie = categorie
        self.note = note
    }
}

/// Le lexique persistant, lu et enrichi à chaque compte rendu.
public struct Lexique: Codable, Sendable {
    public var version: Int
    public var entrees: [EntreeLexique]

    enum CodingKeys: String, CodingKey { case version, entrees }

    public init(version: Int = 1, entrees: [EntreeLexique] = []) {
        self.version = version
        self.entrees = entrees
    }

    // Le fichier porte aussi une clé `_apropos`, destinée au lecteur humain et
    // sans usage pour le code : elle est ignorée à la lecture et réécrite par
    // `enregistrer(vers:)` pour ne pas disparaître au premier enrichissement.
    private static let apropos = """
        Lexique persistant d'Greffier. Lu au début de chaque analyse, enrichi \
        après chaque interrogation validée. Le champ variantes ne \
        recense QUE des erreurs de transcription réellement observées : on n'y \
        invente pas de fautes hypothétiques. Voir docs/SPEC-generation.md § 8.
        """

    public static func charger(depuis url: URL) throws -> Lexique {
        try JSONDecoder().decode(Lexique.self, from: Data(contentsOf: url))
    }

    /// Le fichier existe-t-il mais reste-t-il illisible ?
    ///
    /// **Ce cas détruisait le lexique.** Les appelants faisaient `try?` : un
    /// fichier corrompu donnait un lexique vide, et la première écriture
    /// remplaçait définitivement le fichier par ce vide. Des mois de termes
    /// appris disparaissaient sans un mot.
    ///
    /// Le distinguer d'un fichier absent — qui, lui, est l'état normal d'un
    /// premier lancement — permet de refuser d'écrire par-dessus.
    public static func estCorrompu(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return (try? charger(depuis: url)) == nil
    }

    /// Met le fichier illisible de côté au lieu de l'écraser, et rend le nom
    /// sous lequel il a été sauvé.
    ///
    /// On préfère un lexique reparti de zéro **avec** l'ancien conservé à côté,
    /// plutôt qu'un lexique vide et rien d'autre.
    @discardableResult
    public static func mettreDeCote(_ url: URL) -> String? {
        guard estCorrompu(url) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let nom = "lexique-illisible-\(f.string(from: Date())).json"
        let cible = url.deletingLastPathComponent().appendingPathComponent(nom)
        guard (try? FileManager.default.moveItem(at: url, to: cible)) != nil else { return nil }
        return nom
    }

    public func enregistrer(vers url: URL) throws {
        var objet: [String: Any] = [
            "version": version,
            "_apropos": Lexique.apropos,
        ]
        objet["entrees"] = entrees.map { e -> [String: Any] in
            var d: [String: Any] = [
                "terme": e.terme,
                "variantes": e.variantes,
                "categorie": e.categorie.rawValue,
            ]
            if let note = e.note { d["note"] = note }
            return d
        }
        let data = try JSONSerialization.data(
            withJSONObject: objet, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Enrichissement

    /// Ajoute une entrée, ou **fusionne** si le terme est déjà connu.
    ///
    /// La fusion est ce qui rend la sélection auto-réparatrice : une faute que
    /// la détection avait manquée entre dans les variantes au moment où l'utilisateur
    /// la corrige, et ne repassera plus (spécification § 8.3).
    ///
    /// - Returns: `true` si une entrée neuve a été créée, `false` si fusion.
    @discardableResult
    public mutating func integrer(_ entree: EntreeLexique) -> Bool {
        let cle = Lexique.normaliser(entree.terme)
        guard let i = entrees.firstIndex(where: { Lexique.normaliser($0.terme) == cle }) else {
            entrees.append(entree)
            return true
        }
        for variante in entree.variantes where !contientVariante(entrees[i], variante) {
            entrees[i].variantes.append(variante)
        }
        // Une note existante n'est jamais écrasée : elle a déjà été validée.
        if entrees[i].note == nil { entrees[i].note = entree.note }
        return false
    }

    private func contientVariante(_ entree: EntreeLexique, _ variante: String) -> Bool {
        let v = Lexique.normaliser(variante)
        if Lexique.normaliser(entree.terme) == v { return true }
        return entree.variantes.contains { Lexique.normaliser($0) == v }
    }

    // MARK: - Ressemblances

    /// Au-delà de cette similarité, deux termes sont assez proches pour qu'on
    /// se demande s'ils désignent la même chose.
    ///
    /// Plus exigeant que le seuil de sélection : ici on ne cherche pas à
    /// rattraper une faute de transcription, on cherche un doublon créé par
    /// mégarde — « Menuiserie Vidal » et « Menuiseries Vidal ».
    public static let seuilRessemblance = 0.82

    /// L'entrée existante qui ressemble le plus à ce terme, sans lui être
    /// identique. `nil` si aucune n'en approche.
    public func entreeProche(de terme: String,
                             seuil: Double = seuilRessemblance) -> EntreeLexique? {
        let cible = Lexique.compacter(terme)
        guard !cible.isEmpty else { return nil }
        var meilleure: (entree: EntreeLexique, score: Double)?
        for entree in entrees {
            let candidat = Lexique.compacter(entree.terme)
            if candidat == cible { return nil }  // déjà connu : ce n'est pas un doublon
            let score = Lexique.similarite(cible, candidat)
            guard score >= seuil else { continue }
            if meilleure == nil || score > meilleure!.score { meilleure = (entree, score) }
        }
        return meilleure?.entree
    }

    /// Les paires d'entrées assez proches pour mériter un arbitrage.
    ///
    /// Sert à signaler après coup ce qui a échappé au contrôle du moment : un
    /// doublon créé avant que ce garde-fou n'existe reste sinon invisible.
    public func ressemblances(seuil: Double = seuilRessemblance) -> [(EntreeLexique, EntreeLexique)] {
        var paires: [(EntreeLexique, EntreeLexique)] = []
        for (i, a) in entrees.enumerated() {
            for b in entrees.dropFirst(i + 1) {
                let score = Lexique.similarite(Lexique.compacter(a.terme),
                                               Lexique.compacter(b.terme))
                if score >= seuil { paires.append((a, b)) }
            }
        }
        return paires
    }

    /// Réunit deux entrées en une seule, sous le terme retenu.
    ///
    /// Le terme abandonné devient une variante : c'est une faute déjà
    /// rencontrée, et la garder évite qu'elle repose la question.
    public mutating func fusionner(_ abandonne: String, dans retenu: String) {
        let cleA = Lexique.normaliser(abandonne)
        let cleR = Lexique.normaliser(retenu)
        guard cleA != cleR,
              let iA = entrees.firstIndex(where: { Lexique.normaliser($0.terme) == cleA }),
              let iR = entrees.firstIndex(where: { Lexique.normaliser($0.terme) == cleR })
        else { return }

        let perdante = entrees[iA]
        for variante in [perdante.terme] + perdante.variantes
        where !contientVariante(entrees[iR], variante) {
            entrees[iR].variantes.append(variante)
        }
        if entrees[iR].note == nil { entrees[iR].note = perdante.note }
        entrees.remove(at: iA)
    }

    /// La forme sur laquelle deux termes se comparent quand on cherche un
    /// doublon : normalisée **et sans espaces**.
    ///
    /// « Menuiserie Vidal » et « Menuiseries Vidal » ne diffèrent que d'un
    /// pluriel. En gardant les espaces, leur similarité tombait juste sous le
    /// seuil, et le doublon échappait au garde-fou censé le détecter. Compactées, les deux formes se
    /// ressemblent à 0,9, ce qu'elles sont manifestement.
    public static func compacterPublic(_ texte: String) -> String { compacter(texte) }

    /// Proximité de deux formes compactées, pour comparer aussi des noms de
    /// dossiers : ils souffrent exactement du même défaut que les termes du
    /// lexique — « Menuiserie Vidal », « menuiseries vidal », « MENUISERIES VIDAL ».
    public static func similaritePublique(_ a: String, _ b: String) -> Double {
        similarite(a, b)
    }

    static func compacter(_ texte: String) -> String {
        normaliser(texte).replacingOccurrences(of: " ", with: "")
    }

    /// Proximité de deux chaînes déjà normalisées, entre 0 et 1.
    static func similarite(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let ca = Array(a), cb = Array(b)
        let plusLong = max(ca.count, cb.count)
        guard plusLong > 0 else { return 0 }
        return 1 - Double(distance(ca, cb)) / Double(plusLong)
    }

    // MARK: - Sélection

    /// Seuil de similarité de la passe approchée.
    ///
    /// Trop strict, il laisse repasser des questions déjà réglées ; trop lâche,
    /// il réintroduit tout le lexique. À calibrer à l'usage — d'où le passage
    /// en paramètre de `selectionner`, plutôt qu'un réglage global.
    public static let seuilSimilariteParDefaut = 0.78

    /// Les seules entrées transmises à Claude pour un transcript donné
    /// (spécification § 8.3) — le lexique n'est jamais envoyé en entier.
    ///
    /// - Parameters:
    ///   - transcript: le verbatim à analyser.
    ///   - termesDuDossier: termes déjà rencontrés dans les comptes rendus
    ///     antérieurs du même projet, retenus d'office même absents du
    ///     transcript : ils informent la rédaction.
    public func selectionner(pourTranscript transcript: String,
                             termesDuDossier: [String] = [],
                             seuil: Double = Lexique.seuilSimilariteParDefaut) -> [EntreeLexique] {
        let texte = " " + Lexique.normaliser(transcript) + " "
        let mots = texte.split(separator: " ").map(String.init)
        let dossier = Set(termesDuDossier.map(Lexique.normaliser))

        return entrees.filter { entree in
            if dossier.contains(Lexique.normaliser(entree.terme)) { return true }

            // Passe 1 — correspondance exacte, sur le terme puis les variantes.
            // Elle attrape la grande majorité des cas, pour un coût négligeable.
            for forme in [entree.terme] + entree.variantes {
                let f = Lexique.normaliser(forme)
                if !f.isEmpty && texte.contains(" " + f + " ") { return true }
            }

            // Passe 2 — correspondance approchée, pour les fautes inédites.
            // Le terme à détecter est justement celui qui est mal transcrit :
            // une comparaison exacte manquerait le cas d'usage.
            return Lexique.approche(Lexique.normaliser(entree.terme), dans: mots, seuil: seuil)
        }
    }

    /// Cherche une forme approchée du terme parmi les fenêtres de mots.
    static func approche(_ terme: String, dans mots: [String], seuil: Double) -> Bool {
        guard terme.count >= 4 else { return false }  // trop court : trop de faux positifs
        let cible = Array(terme)
        let trigrammesCible = trigrammes(terme)
        let nbMots = terme.split(separator: " ").count

        for largeur in max(1, nbMots - 1)...(nbMots + 1) {
            guard mots.count >= largeur else { continue }
            for debut in 0...(mots.count - largeur) {
                let fenetre = mots[debut..<(debut + largeur)].joined(separator: " ")

                // Deux pré-filtres avant la distance, qui coûte cher : un écart
                // de longueur rédhibitoire, puis l'absence de tout trigramme
                // commun. Sans eux, un lexique fourni deviendrait trop lent.
                let ratio = Double(fenetre.count) / Double(terme.count)
                if ratio < 0.6 || ratio > 1.6 { continue }
                if trigrammesCible.isDisjoint(with: trigrammes(fenetre)) { continue }

                let d = distance(cible, Array(fenetre))
                let similarite = 1.0 - Double(d) / Double(max(cible.count, fenetre.count))
                if similarite >= seuil { return true }
            }
        }
        return false
    }

    static func trigrammes(_ s: String) -> Set<String> {
        let c = Array(s)
        guard c.count >= 3 else { return [String(c)] }
        return Set((0...(c.count - 3)).map { String(c[$0..<($0 + 3)]) })
    }

    /// Distance de Levenshtein, sur deux lignes plutôt qu'une matrice entière.
    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var precedente = Array(0...b.count)
        var courante = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            courante[0] = i
            for j in 1...b.count {
                let cout = a[i - 1] == b[j - 1] ? 0 : 1
                courante[j] = min(precedente[j] + 1, courante[j - 1] + 1, precedente[j - 1] + cout)
            }
            swap(&precedente, &courante)
        }
        return precedente[b.count]
    }

    /// Minuscules, accents retirés, ponctuation et traits d'union changés en
    /// espaces, espaces compressés. C'est la forme sur laquelle tout se compare.
    public static func normaliser(_ texte: String) -> String {
        let plie = texte.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                 locale: Locale(identifier: "fr_FR"))
        let lettres = plie.map { c -> Character in
            (c.isLetter || c.isNumber) ? c : " "
        }
        return String(lettres).split(separator: " ").joined(separator: " ")
    }
}
