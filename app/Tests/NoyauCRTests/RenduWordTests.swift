import XCTest
@testable import NoyauCR

/// Le document Word d'un compte rendu.
///
/// L'export produisait un fichier que Word ouvrait sans en faire un document :
/// le gras était retiré au lieu d'être rendu, les tableaux réduits à des lignes
/// de texte trouées. La conversion offerte par macOS a été essayée, puis
/// écartée sur mesure : elle perd **tous** les tableaux.
final class RenduWordTests: XCTestCase {

    private let compteRendu = """
        # Compte rendu de réunion — Menuiseries Vidal

        **Document interne — ne pas diffuser au client.**

        | | |
        |---|---|
        | Objet | Devis et subvention |
        | Date | Le 20 août 2026 |

        > **Périmètre.** Toute la séance.

        ## 1. Le devis

        Le montant s'élève à **18 200 euros**, et le délai reste *indicatif*.

        | Poste | Montant |
        |---|---|
        | Fourniture | 12 000 € |
        | Pose | 6 200 € |

        - Nicolas Berthier dépose le dossier
        - Camille Roy renvoie le devis corrigé
        """

    private func produire(_ charte: Charte = .parDefaut,
                          surTitre: String = "") throws -> (URL, String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("essai-\(UUID().uuidString).docx")
        let rendu = RenduWord(charte: charte, surTitre: surTitre)
        try rendu.ecrire(markdown: compteRendu,
                         entete: .init(titre: "Compte rendu", projet: "Menuiseries Vidal"),
                         vers: url)
        return (url, rendu.document(markdown: compteRendu, entete: .init(titre: "Compte rendu")))
    }

    /// Ce que la conversion de macOS perdait, et qui vaut tout le chantier.
    func testLesTableauxSontDeVraisTableaux() throws {
        let (url, xml) = try produire()
        defer { try? FileManager.default.removeItem(at: url) }
        // La fiche de tête, le tableau des montants, l'encadré et le bandeau :
        // quatre, là où la conversion du système n'en rendait aucun.
        XCTAssertEqual(xml.components(separatedBy: "<w:tbl>").count - 1, 4)
        XCTAssertTrue(xml.contains("Fourniture"), "le tableau garde ses cellules")
        XCTAssertTrue(xml.contains("<w:tblHeader/>"),
                      "l'en-tête se répète en haut de chaque page")
    }

    /// Le gras était **retiré** au lieu d'être rendu : l'emphase disparaissait.
    func testLeGrasEstRenduEtNonEfface() throws {
        let (url, xml) = try produire()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(xml.contains("<w:b/>"))
        XCTAssertTrue(xml.contains("18 200 euros"))
        XCTAssertFalse(xml.contains("**"), "les astérisques ne doivent pas rester")
        XCTAssertTrue(xml.contains("<w:i/>"), "l'italique aussi doit être rendu")
    }

    /// Sans styles nommés, Word affiche du texte gras, pas des titres : le
    /// volet de navigation reste vide et la charte n'est pas reprenable.
    func testLesTitresPortentUnStyleWordNomme() throws {
        let (url, xml) = try produire()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Heading1\"/>"))
        XCTAssertTrue(RenduWord().styles.contains("<w:name w:val=\"heading 1\"/>"))
    }

    /// Une archive dont la somme de contrôle est fausse s'ouvre en apparence,
    /// puis Word annonce un document corrompu.
    func testLArchiveEstUnZipValide() throws {
        let (url, _) = try produire()
        defer { try? FileManager.default.removeItem(at: url) }
        let donnees = try Data(contentsOf: url)
        XCTAssertEqual(Array(donnees.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        // Le lecteur du système doit retrouver le texte : c'est la preuve que
        // l'archive, les relations et le XML tiennent ensemble.
        let relu = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        XCTAssertTrue(relu.string.contains("18 200 euros"))
        XCTAssertTrue(relu.string.contains("Fourniture"), "le tableau doit être relisible")
    }

    func testLaSommeDeControleEstCelleDuFormatZip() {
        // Valeur de référence du CRC-32 pour cette chaîne.
        XCTAssertEqual(ArchiveZip.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    /// Aucun nom propre ne doit être écrit par le code.
    func testAucunNomNEstEcritEnDur() throws {
        let (url, xml) = try produire()
        defer { try? FileManager.default.removeItem(at: url) }
        // Sans société renseignée, la ligne de sur-titre n'existe pas du tout :
        // c'est la seule garantie qu'aucun nom ne puisse s'y glisser en dur.
        XCTAssertFalse(xml.contains("<w:caps/><w:color w:val=\"DBEAFE\"/>"))

        let (url2, avecSociete) = try produire(surTitre: "Ateliers Marbot")
        defer { try? FileManager.default.removeItem(at: url2) }
        XCTAssertTrue(avecSociete.contains("Ateliers Marbot"),
                      "seule la société renseignée apparaît")
    }

    /// Une charte réglée doit se retrouver dans le document.
    func testLaCharteChoisiePiloteLeDocument() throws {
        var charte = Charte.parDefaut
        charte.accent = "AA3311"
        charte.police = "Georgia"
        let (url, xml) = try produire(charte)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(xml.contains("AA3311"))
        XCTAssertTrue(xml.contains("w:ascii=\"Georgia\""))
    }

    /// Une charte écrite à la main où il manque une couleur doit s'ouvrir
    /// quand même : une faute de frappe ne doit pas priver de tout document.
    func testUneCharteIncompleteRepartSurLesValeursDOrigine() throws {
        let json = Data("""
            {"accent":"112233","police":"Arial","tailleCorps":99}
            """.utf8)
        let charte = try JSONDecoder().decode(Charte.self, from: json)
        XCTAssertEqual(charte.accent, "112233")
        XCTAssertEqual(charte.police, "Arial")
        XCTAssertEqual(charte.tailleCorps, Charte.parDefaut.tailleCorps,
                       "une taille absurde retombe sur celle d'origine")
        XCTAssertEqual(charte.encre, Charte.parDefaut.encre)
    }

    func testUneCouleurMalEcriteEstRefusee() {
        XCTAssertTrue(Charte.estUneCouleur("2563EB"))
        XCTAssertFalse(Charte.estUneCouleur("#2563EB"))
        XCTAssertFalse(Charte.estUneCouleur("2563E"))
        XCTAssertFalse(Charte.estUneCouleur("ZZZZZZ"))
    }

    /// Les astérisques d'un calcul ne doivent pas basculer la ligne en italique.
    func testUneAsterisqueIsoleeNOuvreRien() {
        let fragments = Markdown.fragments("Le lot 3*4 reste ouvert.")
        XCTAssertEqual(fragments.count, 1)
        XCTAssertFalse(fragments[0].italique)
        XCTAssertEqual(fragments[0].texte, "Le lot 3*4 reste ouvert.")
    }
}
