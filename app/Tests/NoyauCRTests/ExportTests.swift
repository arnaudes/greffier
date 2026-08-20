import XCTest
@testable import NoyauCR

/// Faire sortir un document vers ce qui l'attend ailleurs.
///
/// Le compte rendu existe en Markdown et en PDF : assez pour lire et archiver,
/// pas pour ce qu'on en fait vraiment. Un client annote dans Word, un collègue
/// attend un email — et personne ne veut recopier à la main un document qui
/// existe déjà.
final class ExportTests: XCTestCase {

    private let compteRendu = """
        # Compte rendu de réunion — Menuiseries Vidal

        **Document interne — ne pas diffuser au client.**

        ## 1. Le devis

        Le montant s'élève à **18 200 euros**.

        - Nicolas Berthier dépose le dossier
        - Camille Roy renvoie le devis corrigé
        """

    func testLeMarkdownDevientUnDocumentLisible() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("essai-\(UUID().uuidString)")
            .appendingPathExtension(Export.extensionTraitementDeTexte)
        defer { try? FileManager.default.removeItem(at: url) }

        try Export.versTraitementDeTexte(compteRendu, vers: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Le fichier doit être relisible par ce que macOS propose — c'est la
        // garantie qu'un traitement de texte l'ouvrira.
        let relu = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        XCTAssertTrue(relu.string.contains("18 200 euros"))
        XCTAssertFalse(relu.string.contains("**"), "les marques Markdown doivent disparaître")
        XCTAssertFalse(relu.string.contains("# "), "les dièses de titre aussi")
    }

    /// Le bouton promet du Word : il doit rendre du Word.
    ///
    /// Un `.rtf` s'ouvrait bien dans Word, mais portait l'icône de TextEdit —
    /// et on cherchait en vain, dans le Finder, le fichier qu'on venait de
    /// demander. Un `.docx` est une archive ZIP : ses quatre premiers octets
    /// le disent.
    func testLeDocumentEstUnVraiFichierWord() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("essai-\(UUID().uuidString)")
            .appendingPathExtension(Export.extensionTraitementDeTexte)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(Export.extensionTraitementDeTexte, "docx")
        try Export.versTraitementDeTexte(compteRendu, vers: url)

        let debut = try Data(contentsOf: url).prefix(4)
        XCTAssertEqual(Array(debut), [0x50, 0x4B, 0x03, 0x04],
                       "un .docx commence par la signature d'une archive ZIP")
    }

    /// Le nom d'un document qui part en pièce jointe.
    func testLeNomDeFichierPorteLaDateLeClientEtLObjet() {
        let date = DateComponents(calendar: .current, year: 2026, month: 8, day: 20).date!
        let nom = Rangement.nomDeFichier(projet: "Menuiseries Vidal",
                                         objet: "Devis et subvention", date: date)
        XCTAssertEqual(nom, "2026-08-20 — Menuiseries Vidal — Devis et subvention")
    }

    /// Un client saisi « Client / Filiale » ne doit pas ouvrir un chemin.
    func testLeNomDeFichierNeContientAucunSeparateurDeChemin() {
        let date = Date()
        let nom = Rangement.nomDeFichier(projet: "Client / Filiale",
                                         objet: "Point : suite", date: date)
        XCTAssertFalse(nom.contains("/"))
        XCTAssertFalse(nom.contains(":"))
    }

    /// Sans client ni objet, il reste un nom utilisable.
    func testLeNomDeFichierNEstJamaisVide() {
        XCTAssertFalse(Rangement.nomDeFichier(projet: "", objet: "", date: Date()).isEmpty)
    }

    func testLesListesRestentDesListes() {
        let texte = Export.enTexteAttribue(compteRendu).string
        XCTAssertTrue(texte.contains("•"), "une puce vaut mieux qu'un tiret perdu")
    }

    // MARK: - Le brouillon d'email

    func testLObjetEstExtraitDeLEmail() {
        let email = """
            **À :** Nicolas Berthier (Menuiseries Vidal)
            **De :** Camille Roy — gérante
            **Objet :** Suite à notre réunion du 19 août

            Bonjour Nicolas,

            Voici ce que nous avons retenu.
            """
        let (objet, corps) = Export.decouper(email)
        XCTAssertEqual(objet, "Suite à notre réunion du 19 août")
        XCTAssertTrue(corps.hasPrefix("Bonjour Nicolas,"),
                      "l'en-tête ne doit pas se retrouver dans le corps")
        XCTAssertFalse(corps.contains("**"))
    }

    func testUnEmailSansObjetEnRecoitUnParDefaut() {
        // Mieux vaut un objet convenable qu'un message sans objet, que les
        // logiciels de courrier signalent comme suspect.
        let (objet, _) = Export.decouper("Bonjour,\n\nVoici le compte rendu.")
        XCTAssertFalse(objet.isEmpty)
    }

    func testLeCorpsNePerdPasLesParagraphes() {
        let (_, corps) = Export.decouper("**Objet :** Test\n\nUn.\n\nDeux.")
        XCTAssertTrue(corps.contains("Un."))
        XCTAssertTrue(corps.contains("Deux."))
    }
}
