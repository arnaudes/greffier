import Foundation

/// Fabrique le PDF d'un compte rendu, à la charte UP.
///
/// Le PDF porte **le même contenu** que le Markdown : ce n'est pas une version
/// courte, seulement sa mise en forme (spécification § 6).
///
/// Le procédé reprend celui du gabarit `~/Documents/CHARTE-PDF-TEMPLATE.html` :
/// composer une page HTML, puis la faire rendre par Chrome sans tête. Aucune
/// dépendance supplémentaire — Chrome est déjà sur la machine.
public struct RenduPDF: Sendable {

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

    public enum Erreur: Error, LocalizedError {
        case chromeIntrouvable
        case rendulEchoue(String)

        public var errorDescription: String? {
            switch self {
            case .chromeIntrouvable:
                "Google Chrome est introuvable ; il produit le PDF à partir de la page HTML."
            case .rendulEchoue(let detail):
                "La fabrication du PDF a échoué. \(detail)"
            }
        }
    }

    static let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

    /// Les couleurs et la typographie, partagées avec le document Word.
    public var charte: Charte
    /// Ce qui s'affiche au-dessus du titre — le nom de votre société, si vous
    /// l'avez renseigné. **Rien n'est écrit en dur** : un nom dans le code
    /// serait un nom publié.
    public var surTitre: String

    public init(charte: Charte = .parDefaut, surTitre: String = "") {
        self.charte = charte
        self.surTitre = surTitre
    }

    // MARK: - Composition

    /// Compose la page HTML complète : le style de la charte, le bandeau plein
    /// bord, puis le corps du compte rendu.
    public func composerHTML(markdown: String, entete: Entete) throws -> String {
        let kicker = surTitre.isEmpty
            ? "\(icone) Greffier"
            : "\(icone) Greffier · \(echapper(surTitre.uppercased()))"
        return """
            <!DOCTYPE html>
            <html lang="fr">
            <head>
            <meta charset="utf-8">
            <title>\(echapper(entete.titre))</title>
            <style>
            \(style)
            </style>
            </head>
            <body>
            <div class="banner">
              <div class="kicker">\(kicker)</div>
              <h1>\(echapper(entete.titre))</h1>
              <div class="desc">\(echapper(entete.sousTitre))</div>
              <div class="rule"></div>
              <div class="meta">
                <div class="m"><div class="l">Document</div><div class="v">\(echapper(entete.typeDocument))</div></div>
                <div class="m"><div class="l">Projet</div><div class="v">\(echapper(entete.projet))</div></div>
                <div class="m"><div class="l">Réunion du</div><div class="v">\(echapper(entete.date))</div></div>
              </div>
            </div>
            <div class="wrap">
            \(Markdown.versHTML(markdown))
            </div>
            </body>
            </html>
            """
    }

    /// La feuille de style, écrite à partir de la charte.
    ///
    /// Elle vivait dans un gabarit posé à côté de l'application. L'intention
    /// était juste — les couleurs d'une société n'ont rien à faire dans un
    /// dépôt public — mais qui n'avait pas ce fichier **n'obtenait aucun PDF**.
    var style: String {
        let c = charte
        return """
            :root{ --accent:#\(c.accent); --encre:#\(c.encre); --encreForte:#\(c.encreForte);
              --encreDouce:#\(c.encreDouce); --encreFaible:#\(c.encreFaible);
              --filet:#\(c.filet); --alterne:#\(c.fondAlterne); --entete:#\(c.enteteTableau); }
            *{box-sizing:border-box;}
            html{-webkit-print-color-adjust:exact; print-color-adjust:exact;}
            body{margin:0; color:var(--encre); font-family:\(c.pileCSS);
              font-size:\(c.tailleCorps)px; line-height:1.6;}
            @page{ size:A4; margin:15mm 0 14mm 0;
              @bottom-center{ content:"Page " counter(page) " / " counter(pages);
                font-family:\(c.pileCSS); font-size:8.5px; color:var(--encreFaible); }}
            @page:first{ margin-top:0; }
            h1,h2,h3,h4{margin:0; line-height:1.2;}
            p{margin:0 0 9px;} b,strong{font-weight:700;}
            code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
              font-size:9px; background:var(--alterne); border:1px solid var(--filet);
              border-radius:5px; padding:1px 5px; color:var(--encreForte); white-space:nowrap;}
            .banner{margin:0 0 20px; padding:15mm 14mm 13mm; border-radius:0 0 36px 36px;
              color:#fff; background:linear-gradient(135deg,#\(c.bandeauDebut) 0%,
              #\(c.bandeauFin) 100%);}
            .banner .kicker{font-size:11px; font-weight:800; letter-spacing:.16em;
              text-transform:uppercase; color:#DBEAFE; display:flex; align-items:center;
              gap:9px; margin-bottom:14px;}
            .banner .kicker svg{width:17px;height:17px;stroke:#DBEAFE;fill:none;
              stroke-width:2;stroke-linecap:round;stroke-linejoin:round;flex:none;}
            .banner h1{font-size:27px; font-weight:800; letter-spacing:-.01em;
              line-height:1.14; max-width:165mm;}
            .banner .desc{font-size:11px; color:#E0E7FF; margin-top:12px; max-width:172mm;
              line-height:1.5;}
            .banner .rule{height:1px; background:rgba(255,255,255,.28); margin:16px 0 12px;}
            .meta{display:flex; gap:40px;}
            .meta .m .l{font-size:8.5px; font-weight:800; letter-spacing:.1em;
              text-transform:uppercase; color:#BFDBFE;}
            .meta .m .v{font-size:11px; font-weight:600; color:#fff; margin-top:2px;}
            .wrap{padding:0 14mm;}
            .sec{margin-top:22px;}
            .sec-h{display:flex; align-items:baseline; gap:9px; break-after:avoid;
              page-break-after:avoid;}
            .sec-h .n{color:var(--accent); font-weight:800; font-size:17px;}
            .sec-h h2{font-size:16.5px; font-weight:800; color:var(--encreForte);
              letter-spacing:-.01em;}
            .sec-rule{height:2px; background:var(--accent); margin:6px 0 12px;
              border-radius:2px; break-after:avoid; page-break-after:avoid;}
            h3{font-size:12px; font-weight:700; color:var(--encre); margin:14px 0 6px;}
            ul{margin:0 0 10px; padding-left:18px;} li{margin:3px 0;}
            ol{margin:0 0 9px; padding-left:18px;}
            table{width:100%; border-collapse:collapse; margin:10px 0; font-size:9.5px;}
            thead{display:table-header-group;}
            tr{page-break-inside:avoid; break-inside:avoid;}
            thead th{background:var(--entete); color:#fff; text-align:left; padding:8px 10px;
              font-size:8.5px; font-weight:800; text-transform:uppercase; letter-spacing:.06em;}
            tbody td{padding:7px 10px; border-bottom:1px solid var(--filet);
              vertical-align:top;}
            tbody tr:nth-child(even){background:var(--alterne);}
            tbody tr td:first-child{font-weight:700; color:var(--encre);}
            table.fiche{width:100%; border-collapse:collapse; margin:0 0 14px;}
            table.fiche td{border:none; padding:3px 0; vertical-align:top;}
            table.fiche td:first-child{width:42mm; color:var(--encreDouce);}
            table.fiche tbody tr:nth-child(even){background:transparent;}
            .call{border-radius:8px; padding:11px 14px 11px 15px; margin:11px 0;
              font-size:10px; border-left:4px solid; page-break-inside:avoid;}
            .call b{font-weight:700;}
            .call.info{background:#\(RenduWord.eclaircir(c.information));
              border-color:#\(c.information); color:#\(RenduWord.assombrir(c.information));}
            .call.warn{background:#\(RenduWord.eclaircir(c.avertissement));
              border-color:#\(c.avertissement); color:#\(RenduWord.assombrir(c.avertissement));}
            """
    }

    /// Le graphique de la banque d'icônes du gabarit : c'est celle qui parle
    /// d'un rapport. La consigne de la charte — jamais un simple losange —
    /// s'applique.
    private var icone: String {
        #"<svg viewBox="0 0 24 24"><path d="M3 3v16a2 2 0 0 0 2 2h16"/>"# +
        #"<path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/></svg>"#
    }

    static func echapper(_ t: String) -> String {
        t.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    func echapper(_ t: String) -> String { Self.echapper(t) }

    // MARK: - Rendu

    /// Écrit le PDF. La page HTML intermédiaire est conservée à côté : sans
    /// son source, un PDF ne peut plus être mis à jour, seulement refait.
    @discardableResult
    /// - Parameter sourceHTML: où déposer la page dont le PDF est tiré. Par
    ///   défaut à côté du PDF — mais elle n'a rien à faire sous les yeux : elle
    ///   sert à refaire le document, jamais à être ouverte.
    public func ecrire(markdown: String, entete: Entete, vers pdf: URL,
                       sourceHTML: URL? = nil) throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: Self.chrome) else {
            throw Erreur.chromeIntrouvable
        }
        let html = try composerHTML(markdown: markdown, entete: entete)
        let source = sourceHTML ?? pdf.deletingPathExtension().appendingPathExtension("html")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try html.write(to: source, atomically: true, encoding: .utf8)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.chrome)
        p.arguments = [
            "--headless", "--disable-gpu", "--no-pdf-header-footer",
            "--print-to-pdf=\(pdf.path)", source.absoluteString,
        ]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()

        guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: pdf.path) else {
            let detail = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            throw Erreur.rendulEchoue(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return pdf
    }
}
