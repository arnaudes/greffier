import XCTest
@testable import NoyauCR

/// Les consignes de rédaction : celles du métier, celles d'un dossier, et ce
/// qu'elles ne peuvent jamais défaire.
final class ConsignesTests: XCTestCase {

    private var racine: URL!

    override func setUp() {
        racine = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("greffier-consignes-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: racine) }

    // MARK: - Les consignes d'un dossier

    func testElleSEcriventEtSeRelisent() throws {
        var consignes = ConsignesDossier()
        consignes.ajouter("Cite systématiquement le numéro de lot.")
        try consignes.enregistrer(racine: racine, projet: "Menuiseries Vidal")

        let relues = ConsignesDossier.charger(racine: racine, projet: "Menuiseries Vidal")
        XCTAssertTrue(relues.texte.contains("numéro de lot"))
    }

    func testLEnteteExplicativeNEstPasTransmise() throws {
        // Le fichier doit s'expliquer quand on tombe dessus dans le Finder,
        // sans que cette explication parte chez Claude.
        var consignes = ConsignesDossier()
        consignes.ajouter("Sois bref.")
        try consignes.enregistrer(racine: racine, projet: "Client")

        let relues = ConsignesDossier.charger(racine: racine, projet: "Client")
        XCTAssertFalse(relues.texte.contains("Consignes de rédaction —"))
        XCTAssertFalse(relues.texte.contains("Ce qui suit est ajouté"))
        XCTAssertTrue(relues.texte.contains("Sois bref."))
    }

    func testUneConsigneNEstPasAjouteeDeuxFois() {
        var consignes = ConsignesDossier()
        consignes.ajouter("Sois bref.")
        consignes.ajouter("Sois bref.")
        XCTAssertEqual(consignes.texte.components(separatedBy: "Sois bref.").count - 1, 1)
    }

    func testDesConsignesVidesNeLaissentPasDeFichier() throws {
        try ConsignesDossier(texte: "Quelque chose").enregistrer(racine: racine, projet: "X")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: ConsignesDossier.chemin(racine: racine, projet: "X").path))

        try ConsignesDossier(texte: "  ").enregistrer(racine: racine, projet: "X")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ConsignesDossier.chemin(racine: racine, projet: "X").path),
            "un fichier vide traînerait dans le dossier du client")
    }

    func testUnDossierSansFichierNEstPasUneErreur() {
        XCTAssertTrue(ConsignesDossier.charger(racine: racine, projet: "Jamais vu").estVide)
    }

    // MARK: - Les blocs du prompt

    private let identite = Identite(
        nom: "Camille Roy", fonction: "gérante", societe: "Atelier Roy",
        activite: "L'Atelier Roy fabrique des menuiseries.",
        jamaisAuClient: "Nos tarifs journaliers.",
        charte: "Vouvoiement. Paragraphes courts.",
        consignesMetier: "Distingue les jalons contractuels des indicatifs.")

    func testChaqueBlocDitDOuIlVient() {
        let blocs = Prompts.blocs(identite: identite, consignesDossier: "Cite le lot.")
        let origines = Set(blocs.map(\.origine))
        XCTAssertTrue(origines.contains(.identite))
        XCTAssertTrue(origines.contains(.charteDeForme))
        XCTAssertTrue(origines.contains(.consignesMetier))
        XCTAssertTrue(origines.contains(.dossier))
        XCTAssertTrue(origines.contains(.garanti))
    }

    func testLesReglesNeSontJamaisModifiables() {
        let blocs = Prompts.blocs(identite: identite)
        let regles = blocs.first { $0.texte.contains("NE JAMAIS INVENTER") }
        XCTAssertNotNil(regles)
        XCTAssertFalse(regles!.origine.modifiable,
                       "les garanties du produit ne doivent pas être présentées comme "
                       + "modifiables")
    }

    func testToutCeQuiVientDeLUtilisateurPrecedeLesRegles() {
        // Le point qui décide de tout : une consigne placée après les règles
        // pourrait les défaire.
        let prompt = Prompts.systeme(identite: identite, consignesDossier: "Cite le lot.")
        let regles = prompt.range(of: "NE JAMAIS INVENTER")!.lowerBound
        for extrait in ["Vouvoiement", "jalons contractuels", "Cite le lot"] {
            XCTAssertTrue(prompt.range(of: extrait)!.lowerBound < regles,
                          "« \(extrait) » doit précéder les règles absolues")
        }
        XCTAssertTrue(prompt.contains("ne peuvent jamais justifier"))
    }

    func testSansConsignesLeRappelDePrimauteNApparaitPas() {
        // Rappeler qu'une charte ne prime pas, quand il n'y a aucune charte,
        // n'apprendrait rien et coûterait des jetons.
        let prompt = Prompts.systeme(identite: Identite(nom: "Camille Roy"))
        XCTAssertFalse(prompt.contains("ne peuvent jamais justifier"))
    }

    func testLesConsignesDuDossierArriventDansLePrompt() {
        let prompt = Prompts.systeme(identite: identite,
                                     consignesDossier: "Cite le numéro de lot.")
        XCTAssertTrue(prompt.contains("PROPRE À CE DOSSIER"))
        XCTAssertTrue(prompt.contains("Cite le numéro de lot."))
    }

    // MARK: - Déduire une consigne d'un reproche

    func testLInstructionDemandeUneRegleGeneralePasUnCorrectif() {
        let instruction = Prompts.instructionConsigne(
            reproche: "Tu as rangé la phase 2 en décision alors que rien n'était acté.")
        XCTAssertTrue(instruction.contains("phase 2"))
        XCTAssertTrue(instruction.contains("Une seule phrase"))
        XCTAssertTrue(instruction.contains("AUCUNE"),
                      "un reproche qui ne se généralise pas ne doit pas devenir une règle")
        XCTAssertTrue(instruction.contains("Pas de nom propre"))
    }
}
