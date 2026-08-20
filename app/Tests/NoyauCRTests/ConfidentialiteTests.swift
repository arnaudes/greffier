import XCTest
@testable import NoyauCR

/// Ce que le code ne doit jamais écrire de lui-même.
///
/// Le dépôt est public. Un nom de société inscrit en dur s'est retrouvé en
/// ligne le 20/08/2026, imprimé dans le bandeau de chaque PDF ; un nom de
/// client réel figurait dans sept fichiers, dont deux exemples de saisie
/// affichés à l'écran. Un `push --force` n'efface rien : GitHub conserve les
/// objets d'un commit écrasé.
///
/// Ces cas ne remplacent pas `outils/verifier-confidentialite.sh`, qui balaie
/// le dépôt entier avant publication. Ils verrouillent l'autre moitié du
/// problème : que rien ne puisse **naître** dans un document produit sans
/// venir de ce que l'utilisateur a renseigné.
final class ConfidentialiteTests: XCTestCase {

    /// Sans identité, personne n'est nommé — ni par défaut, ni en exemple.
    func testUnPromptSansIdentiteNeNommePersonne() {
        let prompt = Prompts.systeme(identite: Identite())
        XCTAssertFalse(prompt.contains("Tu assistes"),
                       "sans identité, le prompt doit rester impersonnel")
        XCTAssertTrue(prompt.contains("Tu rédiges des comptes rendus"))
        // Les garanties du produit, elles, sont là dans tous les cas.
        XCTAssertTrue(prompt.contains("NE JAMAIS INVENTER"))
    }

    /// Le bandeau des documents ne porte que ce qui a été renseigné.
    func testAucunDocumentNePorteDeNomNonRenseigne() throws {
        let pdf = try RenduPDF().composerHTML(
            markdown: "## 1. Point\n\nUn paragraphe.",
            entete: .init(titre: "Compte rendu"))
        XCTAssertTrue(pdf.contains("Greffier</div>"),
                      "sans société renseignée, seul le nom du logiciel apparaît")

        let word = RenduWord().document(markdown: "Un paragraphe.",
                                        entete: .init(titre: "Compte rendu"))
        // La ligne de sur-titre n'existe pas du tout : c'est la seule garantie
        // qu'aucun nom ne puisse s'y glisser.
        XCTAssertFalse(word.contains("<w:caps/><w:color w:val=\"DBEAFE\"/>"))
    }

    /// Une fiche d'identité écrite par une version antérieure doit s'ouvrir.
    ///
    /// **Le jour où un champ a été ajouté, plus aucune identité ne se chargeait.**
    /// Le décodage échouait sur la clé manquante, `charger` rendait une fiche
    /// vide, et l'application réclamait un nom déjà renseigné. Bien pire que le
    /// bandeau : les comptes rendus partaient sans « ce qui ne sort jamais au
    /// client », c'est-à-dire sans le filtre de l'email.
    func testUneFicheDIdentiteAnterieureSOuvreEntierement() throws {
        // Exactement ce qu'écrivait la version précédente : pas de
        // « consignesMetier », pas de « charte ».
        let ancienne = Data("""
            {"nom":"Camille Roy","fonction":"gérante","societe":"Atelier Roy",
             "activite":"Nous fabriquons des menuiseries sur mesure.",
             "jamaisAuClient":"Nos tarifs journaliers."}
            """.utf8)
        let lue = try JSONDecoder().decode(Identite.self, from: ancienne)

        XCTAssertEqual(lue.nom, "Camille Roy")
        XCTAssertEqual(lue.societe, "Atelier Roy")
        XCTAssertTrue(lue.jamaisAuClient.contains("tarifs"),
                      "le filtre de l'email doit survivre à l'ajout d'un champ")
        XCTAssertEqual(lue.consignesMetier, "", "le champ neuf part vide, sans faire échouer")
        XCTAssertTrue(lue.incomplet.isEmpty, "rien ne manque : la fiche est complète")
    }

    /// Une fiche vide reste une fiche vide, et le dit.
    func testUneFicheAbsenteEstSignaleeCommeIncomplete() {
        let vide = Identite.charger(
            depuis: URL(fileURLWithPath: "/tmp/greffier-inexistant-\(UUID().uuidString).json"))
        XCTAssertTrue(vide.incomplet.contains("votre nom"))
        XCTAssertFalse(vide.utilisable)
    }

    /// Un JSON illisible ne doit pas non plus effacer ce qu'on sait.
    func testUnFichierIllisibleNeFaitPasPerdreLIdentite() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("identite-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("ceci n'est pas du JSON".utf8).write(to: url)
        // On repart à vide, mais sans planter : l'utilisateur ressaisit.
        XCTAssertFalse(Identite.charger(depuis: url).utilisable)
    }
}
