import Foundation

/// Fabrique le document Word d'un compte rendu.
///
/// L'export produisait un fichier que Word ouvrait sans en faire un document :
/// le gras était **retiré** au lieu d'être rendu, les tableaux réduits à des
/// lignes de texte trouées, les encadrés aplatis. On l'a d'abord confié à
/// macOS, qui sait convertir du HTML en `.docx` — mais la conversion perd les
/// tableaux, mesuré sur un compte rendu réel : zéro tableau sur les trois qu'il
/// contenait. Or c'est la fiche d'identité de tête, le passage le plus regardé.
///
/// Le document est donc écrit directement, en WordprocessingML. Cela coûte
/// l'archive et le balisage, et cela rend en échange ce qu'aucune conversion ne
/// donnait : des **styles Word nommés** — donc un volet de navigation qui
/// fonctionne et une charte que le destinataire peut reprendre —, de vrais
/// tableaux, et une pagination.
public struct RenduWord: Sendable {

    public var charte: Charte
    /// Ce qui s'affiche au-dessus du titre. Vide, la ligne disparaît : rien
    /// n'est inventé, et aucun nom n'est écrit en dur nulle part.
    public var surTitre: String

    public init(charte: Charte = .parDefaut, surTitre: String = "") {
        self.charte = charte
        self.surTitre = surTitre
    }

    public struct Entete: Sendable {
        public var titre: String
        public var sousTitre: String
        public var projet: String
        public var date: String
        public var typeDocument: String
        public init(titre: String, sousTitre: String = "", projet: String = "",
                    date: String = "", typeDocument: String = "Compte rendu de réunion") {
            self.titre = titre
            self.sousTitre = sousTitre
            self.projet = projet
            self.date = date
            self.typeDocument = typeDocument
        }
    }

    // MARK: - L'écriture

    @discardableResult
    public func ecrire(markdown: String, entete: Entete, vers url: URL) throws -> URL {
        let archive = ArchiveZip.ecrire([
            .init(nom: "[Content_Types].xml", contenu: Data(typesDeContenu.utf8)),
            .init(nom: "_rels/.rels", contenu: Data(relationsRacine.utf8)),
            .init(nom: "word/_rels/document.xml.rels", contenu: Data(relationsDocument.utf8)),
            .init(nom: "word/styles.xml", contenu: Data(styles.utf8)),
            .init(nom: "word/numbering.xml", contenu: Data(numerotation.utf8)),
            .init(nom: "word/footer1.xml", contenu: Data(piedDePage.utf8)),
            .init(nom: "word/document.xml",
                  contenu: Data(document(markdown: markdown, entete: entete).utf8)),
        ])
        try archive.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Le corps

    func document(markdown: String, entete: Entete) -> String {
        var corps = bandeau(entete)
        for bloc in Markdown.analyser(markdown) {
            switch bloc {
            case .section(let numero, let titre):
                corps += titreDeSection(numero: numero, titre: titre)
            case .sousTitre(let texte):
                corps += paragraphe(Markdown.fragments(texte), style: "Heading2")
            case .paragraphe(let texte):
                corps += paragraphe(Markdown.fragments(texte))
            case .encadre(let avertissement, let texte):
                corps += encadre(texte, avertissement: avertissement)
            case .liste(let ordonnee, let elements):
                for element in elements {
                    corps += paragraphe(Markdown.fragments(element),
                                        style: ordonnee ? "ListeNumerotee" : "ListePuces")
                }
            case .tableau(let entetes, let lignes, let fiche):
                corps += tableau(entetes: entetes, lignes: lignes, fiche: fiche)
            }
        }
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document \(espacesDeNoms)><w:body>\(corps)\(finDeSection)</w:body></w:document>
            """
    }

    /// Le bandeau de tête : une cellule de tableau au fond plein.
    ///
    /// Word ne connaît pas les dégradés de la charte du PDF ; la couleur la
    /// plus sombre du dégradé tient ce rôle, et c'est ce que fait tout document
    /// imprimé quand la nuance n'est pas reproductible.
    func bandeau(_ entete: Entete) -> String {
        var lignes = ""
        if !surTitre.isEmpty {
            lignes += """
                <w:p><w:pPr><w:spacing w:after="140"/></w:pPr>\
                <w:r><w:rPr>\(fonte)<w:b/><w:caps/><w:color w:val="DBEAFE"/>\
                <w:sz w:val="17"/><w:spacing w:val="60"/></w:rPr>\
                <w:t xml:space="preserve">\(echapper(surTitre))</w:t></w:r></w:p>
                """
        }
        lignes += """
            <w:p><w:pPr><w:spacing w:after="\(entete.sousTitre.isEmpty ? 60 : 160)"/></w:pPr>\
            <w:r><w:rPr>\(fonte)<w:b/><w:color w:val="FFFFFF"/><w:sz w:val="44"/></w:rPr>\
            <w:t xml:space="preserve">\(echapper(entete.titre))</w:t></w:r></w:p>
            """
        if !entete.sousTitre.isEmpty {
            lignes += """
                <w:p><w:pPr><w:spacing w:after="160"/></w:pPr>\
                <w:r><w:rPr>\(fonte)<w:color w:val="E0E7FF"/><w:sz w:val="20"/></w:rPr>\
                <w:t xml:space="preserve">\(echapper(entete.sousTitre))</w:t></w:r></w:p>
                """
        }
        // Les mentions de tête, sur une seule ligne, séparées par un point
        // médian : trois colonnes imbriquées seraient illisibles à l'écran
        // dès qu'un intitulé s'allonge.
        let mentions = [(("Document"), entete.typeDocument), ("Projet", entete.projet),
                        ("Réunion du", entete.date)].filter { !$0.1.isEmpty }
        if !mentions.isEmpty {
            var suite = ""
            for (index, mention) in mentions.enumerated() {
                if index > 0 {
                    suite += "<w:r><w:rPr>\(fonte)<w:color w:val=\"7FA5F0\"/>"
                        + "<w:sz w:val=\"20\"/></w:rPr><w:t xml:space=\"preserve\">"
                        + "   ·   </w:t></w:r>"
                }
                suite += "<w:r><w:rPr>\(fonte)<w:caps/><w:color w:val=\"BFDBFE\"/>"
                    + "<w:sz w:val=\"16\"/></w:rPr><w:t xml:space=\"preserve\">"
                    + "\(echapper(mention.0)) </w:t></w:r>"
                suite += "<w:r><w:rPr>\(fonte)<w:b/><w:color w:val=\"FFFFFF\"/>"
                    + "<w:sz w:val=\"20\"/></w:rPr><w:t xml:space=\"preserve\">"
                    + "\(echapper(mention.1))</w:t></w:r>"
            }
            lignes += "<w:p><w:pPr><w:spacing w:after=\"0\"/></w:pPr>\(suite)</w:p>"
        }

        return """
            <w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/>\
            <w:tblBorders>\(bordureNulle)</w:tblBorders>\
            <w:tblCellMar><w:top w:w="340" w:type="dxa"/><w:left w:w="340" w:type="dxa"/>\
            <w:bottom w:w="340" w:type="dxa"/><w:right w:w="340" w:type="dxa"/></w:tblCellMar>\
            </w:tblPr><w:tr><w:tc><w:tcPr><w:tcW w:w="5000" w:type="pct"/>\
            <w:shd w:val="clear" w:fill="\(charte.bandeauDebut)"/></w:tcPr>\
            \(lignes)</w:tc></w:tr></w:tbl>\
            <w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:p>
            """
    }

    /// Un titre de section : son numéro en couleur d'accent, puis le titre,
    /// et le filet qui court dessous.
    func titreDeSection(numero: String?, titre: String) -> String {
        var runs = ""
        if let numero {
            runs += "<w:r><w:rPr>\(fonte)<w:b/><w:color w:val=\"\(charte.accent)\"/>"
                + "<w:sz w:val=\"32\"/></w:rPr><w:t xml:space=\"preserve\">"
                + "\(echapper(numero)) </w:t></w:r>"
        }
        for fragment in Markdown.fragments(titre) {
            runs += run(fragment, taille: 32, couleur: charte.encreForte, grasForce: true)
        }
        return """
            <w:p><w:pPr><w:pStyle w:val="Heading1"/>\
            <w:pBdr><w:bottom w:val="single" w:sz="12" w:space="4" \
            w:color="\(charte.accent)"/></w:pBdr>\
            <w:keepNext/><w:spacing w:before="440" w:after="200"/></w:pPr>\(runs)</w:p>
            """
    }

    func paragraphe(_ fragments: [Markdown.Fragment], style: String? = nil) -> String {
        let runs = fragments.map { run($0) }.joined()
        let pStyle = style.map { "<w:pStyle w:val=\"\($0)\"/>" } ?? ""
        let numeration = style == "ListePuces"
            ? "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr>"
            : style == "ListeNumerotee"
            ? "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"2\"/></w:numPr>" : ""
        return "<w:p><w:pPr>\(pStyle)\(numeration)</w:pPr>\(runs)</w:p>"
    }

    /// Un encadré : fond pâle, filet épais à gauche, comme dans le PDF.
    func encadre(_ texte: String, avertissement: Bool) -> String {
        let teinte = avertissement ? charte.avertissement : charte.information
        let runs = Markdown.fragments(texte)
            .map { run($0, couleur: RenduWord.assombrir(teinte)) }.joined()
        return """
            <w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/>\
            <w:tblBorders><w:left w:val="single" w:sz="24" w:color="\(teinte)"/>\
            <w:top w:val="nil"/><w:bottom w:val="nil"/><w:right w:val="nil"/>\
            <w:insideH w:val="nil"/><w:insideV w:val="nil"/></w:tblBorders>\
            <w:tblCellMar><w:top w:w="150" w:type="dxa"/><w:left w:w="220" w:type="dxa"/>\
            <w:bottom w:w="150" w:type="dxa"/><w:right w:w="200" w:type="dxa"/></w:tblCellMar>\
            </w:tblPr><w:tr><w:trPr><w:cantSplit/></w:trPr><w:tc><w:tcPr>\
            <w:tcW w:w="5000" w:type="pct"/>\
            <w:shd w:val="clear" w:fill="\(RenduWord.eclaircir(teinte))"/></w:tcPr>\
            <w:p><w:pPr><w:spacing w:after="0"/></w:pPr>\(runs)</w:p></w:tc></w:tr></w:tbl>\
            \(respiration)
            """
    }

    /// Un tableau : en-tête sombre en capitales, lignes alternées, filets fins.
    ///
    /// Une fiche — un tableau sans en-tête — est la carte d'identité de tête du
    /// compte rendu : son libellé à gauche, discret, et la valeur à droite.
    func tableau(entetes: [String], lignes: [[String]], fiche: Bool) -> String {
        var xml = """
            <w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:tblLayout w:type="fixed"/>\
            <w:tblBorders>\(fiche ? bordureFiche : bordureTableau)</w:tblBorders>\
            <w:tblCellMar><w:top w:w="90" w:type="dxa"/><w:left w:w="\(fiche ? 0 : 130)" \
            w:type="dxa"/><w:bottom w:w="90" w:type="dxa"/>\
            <w:right w:w="130" w:type="dxa"/></w:tblCellMar></w:tblPr>
            """
        let colonnes = max(entetes.count, lignes.map(\.count).max() ?? 1)
        // Une fiche donne sa première colonne au libellé, plus étroite : sans
        // largeur fixée, Word l'étire au plus long des libellés.
        let largeurs: [Int] = fiche && colonnes == 2
            ? [1500, 3500]
            : Array(repeating: 5000 / max(colonnes, 1), count: colonnes)
        xml += "<w:tblGrid>" + largeurs.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined()
            + "</w:tblGrid>"

        if !fiche, !entetes.isEmpty {
            var cellules = ""
            for (index, entete) in entetes.enumerated() {
                let runs = Markdown.fragments(entete)
                    .map { run($0, taille: 17, couleur: "FFFFFF", grasForce: true, capitales: true) }
                    .joined()
                cellules += """
                    <w:tc><w:tcPr><w:tcW w:w="\(largeurs[min(index, largeurs.count - 1)])" \
                    w:type="pct"/><w:shd w:val="clear" w:fill="\(charte.enteteTableau)"/>\
                    </w:tcPr><w:p><w:pPr><w:spacing w:before="40" w:after="40" \
                    w:line="240" w:lineRule="auto"/></w:pPr>\(runs)</w:p></w:tc>
                    """
            }
            xml += "<w:tr><w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>\(cellules)</w:tr>"
        }

        for (rang, ligne) in lignes.enumerated() {
            var cellules = ""
            // Le zébrage ne s'applique qu'aux vrais tableaux : sur une fiche,
            // il ferait ressembler l'identité du document à un relevé.
            let alterne = !fiche && rang % 2 == 1
            for index in 0..<colonnes {
                let contenu = index < ligne.count ? ligne[index] : ""
                let premiere = index == 0
                let runs = Markdown.fragments(contenu).map {
                    run($0, taille: 19,
                        couleur: fiche && premiere ? charte.encreDouce : charte.encre,
                        grasForce: premiere && !fiche)
                }.joined()
                let fond = alterne
                    ? "<w:shd w:val=\"clear\" w:fill=\"\(charte.fondAlterne)\"/>" : ""
                cellules += """
                    <w:tc><w:tcPr><w:tcW w:w="\(largeurs[min(index, largeurs.count - 1)])" \
                    w:type="pct"/>\(fond)</w:tcPr><w:p><w:pPr>\
                    <w:spacing w:before="40" w:after="40" w:line="264" w:lineRule="auto"/>\
                    </w:pPr>\(runs.isEmpty ? "" : runs)</w:p></w:tc>
                    """
            }
            xml += "<w:tr><w:trPr><w:cantSplit/></w:trPr>\(cellules)</w:tr>"
        }
        return xml + "</w:tbl>" + respiration
    }

    // MARK: - Les morceaux de texte

    func run(_ fragment: Markdown.Fragment, taille: Int? = nil, couleur: String? = nil,
             grasForce: Bool = false, capitales: Bool = false) -> String {
        guard !fragment.texte.isEmpty else { return "" }
        var proprietes = fragment.code
            ? "<w:rFonts w:ascii=\"Consolas\" w:hAnsi=\"Consolas\"/>" : fonte
        if fragment.gras || grasForce { proprietes += "<w:b/>" }
        if fragment.italique { proprietes += "<w:i/>" }
        if capitales { proprietes += "<w:caps/><w:spacing w:val=\"30\"/>" }
        proprietes += "<w:color w:val=\"\(couleur ?? charte.encre)\"/>"
        proprietes += "<w:sz w:val=\"\(taille ?? demiPoints)\"/>"
        if fragment.code {
            proprietes += "<w:shd w:val=\"clear\" w:fill=\"\(charte.fondAlterne)\"/>"
        }
        return "<w:r><w:rPr>\(proprietes)</w:rPr>"
            + "<w:t xml:space=\"preserve\">\(echapper(fragment.texte))</w:t></w:r>"
    }

    /// Le corps du texte, en demi-points — l'unité de Word.
    var demiPoints: Int { Int((charte.tailleCorps * 2).rounded()) }
    var fonte: String {
        "<w:rFonts w:ascii=\"\(charte.policeWord)\" w:hAnsi=\"\(charte.policeWord)\"/>"
    }
    /// Un paragraphe vide après un tableau : sans lui, deux tableaux successifs
    /// se collent et Word les fusionne à l'affichage.
    var respiration: String {
        "<w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"200\" w:lineRule=\"exact\"/></w:pPr></w:p>"
    }

    static func echapper(_ t: String) -> String {
        t.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    func echapper(_ t: String) -> String { RenduWord.echapper(t) }

    /// Le fond pâle d'un encadré, tiré de sa couleur : neuf parts de blanc
    /// pour une de teinte. Demander deux couleurs de plus à l'utilisateur pour
    /// chaque encadré serait une charte que personne ne réglerait.
    public static func eclaircir(_ hexa: String) -> String { melanger(hexa, avec: 0.92) }
    /// Le texte d'un encadré, assez sombre pour rester lisible sur ce fond.
    public static func assombrir(_ hexa: String) -> String { melanger(hexa, avec: -0.45) }

    private static func melanger(_ hexa: String, avec part: Double) -> String {
        guard Charte.estUneCouleur(hexa), let valeur = Int(hexa, radix: 16) else { return hexa }
        let composantes = [(valeur >> 16) & 0xFF, (valeur >> 8) & 0xFF, valeur & 0xFF]
        let melangees = composantes.map { composante -> Int in
            let cible = part >= 0 ? 255.0 : 0.0
            let force = abs(part)
            return Int((Double(composante) * (1 - force) + cible * force).rounded())
        }
        return melangees.map { String(format: "%02X", max(0, min(255, $0))) }.joined()
    }
}
