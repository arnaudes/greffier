import XCTest
@testable import NoyauCR

/// Les cas reprennent la forme réelle d'un compte rendu produit
/// (`MenuiserieVidal/CR-interne-MenuiserieVidal-2026-08-14.md`).
final class MarkdownTests: XCTestCase {

    func testLeTitreDeNiveau1NEstPasDansLeCorps() {
        // Il vit dans le bandeau : le répéter ferait doublon sur la page.
        let html = Markdown.versHTML("# Compte rendu de réunion — MenuiserieVidal\n\nUn texte.")
        XCTAssertFalse(html.contains("Compte rendu de réunion"))
        XCTAssertTrue(html.contains("<p>Un texte.</p>"))
    }

    func testUneSectionNumeroteeSepareSonNumero() {
        let html = Markdown.versHTML("## 4. Charge de travail et chiffrage")
        XCTAssertTrue(html.contains("<span class=\"n\">4.</span>"))
        XCTAssertTrue(html.contains("<h2>Charge de travail et chiffrage</h2>"))
    }

    func testUneSectionSansNumeroResteEntiere() {
        let html = Markdown.versHTML("## Décisions")
        XCTAssertTrue(html.contains("<h2>Décisions</h2>"))
        XCTAssertFalse(html.contains("class=\"n\""))
    }

    func testUnEncadreDAvertissementSeDistingueDUneSimpleReserve() {
        let alerte = Markdown.versHTML("> ⚠️ **Point à arbitrer.** Vingt jours dépassent l'enveloppe.")
        XCTAssertTrue(alerte.contains("class=\"call warn\""))

        let reserve = Markdown.versHTML("> Les montants cités sont des ordres de grandeur.")
        XCTAssertTrue(reserve.contains("class=\"call info\""))
    }

    func testUnEncadreSurPlusieursLignesResteUnSeulBloc() {
        let html = Markdown.versHTML("> Première ligne\n> et sa suite.")
        XCTAssertEqual(html.components(separatedBy: "class=\"call").count - 1, 1)
        XCTAssertTrue(html.contains("Première ligne et sa suite."))
    }

    func testUnTableauDeDonneesGardeSesEntetes() {
        let html = Markdown.versHTML("""
            | Situation | Tarif |
            |---|---|
            | Halle Nord | **750 €** |
            """)
        XCTAssertTrue(html.contains("<th>Situation</th>"))
        XCTAssertTrue(html.contains("<td><b>750 €</b></td>"))
        XCTAssertFalse(html.contains("class=\"fiche\""))
    }

    func testLaFicheDIdentiteNAPasDEnteteAffichee() {
        // Le bandeau de tête d'un compte rendu est un tableau à colonnes sans
        // titre : il se rend autrement qu'un tableau de données.
        let html = Markdown.versHTML("""
            | | |
            |---|---|
            | **Format** | Visioconférence |
            """)
        XCTAssertTrue(html.contains("class=\"fiche\""))
        XCTAssertFalse(html.contains("<thead>"))
    }

    func testListesAPucesEtNumerotees() {
        XCTAssertTrue(Markdown.versHTML("- premier\n- second").contains("<ul>\n<li>premier</li>"))
        let ol = Markdown.versHTML("1. premier\n2. second")
        XCTAssertTrue(ol.contains("<ol>"))
        XCTAssertTrue(ol.contains("<li>second</li>"))
    }

    func testUnePhraseCommencantParUnNombreNEstPasUneListe() {
        // « 2026. » en début de phrase ne doit pas ouvrir une liste numérotée.
        let html = Markdown.versHTML("15 000 € annoncés au client.")
        XCTAssertFalse(html.contains("<ol>"))
        XCTAssertTrue(html.contains("<p>"))
    }

    func testGrasItaliqueEtCode() {
        let html = Markdown.versHTML("Un **gras**, un *italique* et du `code`.")
        XCTAssertTrue(html.contains("<b>gras</b>"))
        XCTAssertTrue(html.contains("<i>italique</i>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
    }

    func testLesChevronsDuTexteNeCassentPasLaPage() {
        let html = Markdown.versHTML("Le format <AAAA.MM.JJ> & la suite.")
        XCTAssertTrue(html.contains("&lt;AAAA.MM.JJ&gt;"))
        XCTAssertTrue(html.contains("&amp;"))
    }

    /// La charte ne dépend plus d'un fichier posé à côté de l'application.
    ///
    /// Elle en dépendait, et l'effet était sévère : qui n'avait pas ce
    /// gabarit — c'est-à-dire tout le monde sauf une machine — n'obtenait
    /// aucun PDF. Le style doit se composer avec les seules valeurs par défaut.
    func testLeStyleSeComposeSansAucunFichierExterieur() {
        let style = RenduPDF().style
        XCTAssertTrue(style.contains(".banner"), "le style doit porter le bandeau")
        XCTAssertTrue(style.contains("#\(Charte.parDefaut.accent)"),
                      "les couleurs viennent de la charte")
    }

    /// Aucun nom propre ne doit être écrit dans le document par le code.
    ///
    /// Un nom de société l'a été, et s'est retrouvé publié. Le sur-titre vient
    /// de ce que l'utilisateur a renseigné, et de nulle part ailleurs.
    func testAucunNomNEstEcritEnDurDansLeBandeau() {
        let page = try! RenduPDF().composerHTML(
            markdown: "## 1. Point\n\nUn paragraphe.",
            entete: .init(titre: "Titre", sousTitre: "", projet: "Projet", date: "Le 20"))
        XCTAssertTrue(page.contains("Greffier</div>"),
                      "sans société renseignée, le sur-titre se limite au nom du logiciel")

        let signee = try! RenduPDF(surTitre: "Ateliers Marbot").composerHTML(
            markdown: "", entete: .init(titre: "Titre"))
        XCTAssertTrue(signee.contains("ATELIERS MARBOT"),
                      "la société renseignée, et elle seule, apparaît")
    }
}
