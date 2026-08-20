import XCTest
@testable import NoyauCR

/// L'enrichissement du lexique et la détection des doublons.
///
/// Ces cas viennent d'un constat du 19/08/2026 : le lexique ne s'incrémentait
/// **jamais**. Le champ `enrichit_lexique` était calculé par Claude, transmis,
/// puis ignoré — aucun appel à `integrer` n'existait dans l'application. Les
/// 21 entrées étaient celles amorcées à la main le 14 août, et le dixième
/// compte rendu d'un dossier coûtait donc autant que le premier.
final class AmorceLexiqueTests: XCTestCase {

    func testLaReponseDonneLeTermeEtClaudeLaFaute() {
        // Le cas réel : le transcript disait « MenuiserieVidal », Camille répond
        // « Menuiseries Vidal ».
        let amorce = AmorceLexique(variante: "MenuiserieVidal", categorie: .entreprise,
                                   note: "Fabricant de menuiseries, client de l'Atelier.")
        let entree = amorce.entree(pourTerme: "Menuiseries Vidal")

        XCTAssertEqual(entree.terme, "Menuiseries Vidal")
        XCTAssertEqual(entree.variantes, ["MenuiserieVidal"])
        XCTAssertEqual(entree.categorie, .entreprise)
        XCTAssertNotNil(entree.note)
    }

    func testUneVarianteIdentiqueAuTermeNEstPasRetenue() {
        // Quand le transcript écrivait déjà correctement, il n'y a pas de faute
        // à mémoriser : l'inscrire ferait doublon avec le terme lui-même.
        let amorce = AmorceLexique(variante: "Menuiseries Vidal", categorie: .entreprise)
        XCTAssertTrue(amorce.entree(pourTerme: "Menuiseries Vidal").variantes.isEmpty)
    }

    func testUneNoteVideResteVide() {
        // Spécification § 8.2 : une note vide est honnête, une note plausible
        // et fausse contaminerait tous les comptes rendus suivants.
        let amorce = AmorceLexique(categorie: .projet, note: "   ")
        XCTAssertNil(amorce.entree(pourTerme: "Halle Nord").note)
    }

    func testLaFusionNEcrasePasUneNoteDejaValidee() {
        var lexique = Lexique(entrees: [
            EntreeLexique(terme: "Deployo", categorie: .outil, note: "Plateforme de déploiement.")
        ])
        let neuve = AmorceLexique(variante: "Deploio", categorie: .outil,
                                  note: "Une autre note, moins sûre.")
        let creee = lexique.integrer(neuve.entree(pourTerme: "Deployo"))

        XCTAssertFalse(creee, "le terme est connu : il faut fusionner, pas dupliquer")
        XCTAssertEqual(lexique.entrees.count, 1)
        XCTAssertEqual(lexique.entrees[0].note, "Plateforme de déploiement.")
        XCTAssertEqual(lexique.entrees[0].variantes, ["Deploio"])
    }
}

/// Le garde-fou contre les doublons, posé le 19/08/2026 après « MenuiserieVidal »
/// et « Menuiseries Vidal » — le même défaut que les deux dossiers en double.
final class RessemblancesLexiqueTests: XCTestCase {

    private let lexique = Lexique(entrees: [
        EntreeLexique(terme: "MenuiserieVidal", categorie: .entreprise, note: "Fabricant de menuiseries."),
        EntreeLexique(terme: "Deployo", categorie: .outil),
        EntreeLexique(terme: "Halle Nord", categorie: .lieu),
    ])

    func testUnDoublonProbableEstRepere() {
        XCTAssertEqual(lexique.entreeProche(de: "Menuiseries Vidal")?.terme, "MenuiserieVidal")
    }

    func testUnTermeDejaConnuNEstPasUnDoublon() {
        // Identique : c'est une fusion, pas un arbitrage à demander.
        XCTAssertNil(lexique.entreeProche(de: "MenuiserieVidal"))
        XCTAssertNil(lexique.entreeProche(de: "charpentesRenaud"))
    }

    func testUnTermeSansRapportNAlertePas() {
        XCTAssertNil(lexique.entreeProche(de: "la plateforme"))
        XCTAssertNil(lexique.entreeProche(de: "Nicolas Berthier"))
    }

    func testLesPairesSuspectesSontListees() {
        var avecDoublon = lexique
        avecDoublon.entrees.append(EntreeLexique(terme: "Menuiseries Vidal", categorie: .entreprise))
        let paires = avecDoublon.ressemblances()

        XCTAssertEqual(paires.count, 1)
        XCTAssertTrue([paires[0].0.terme, paires[0].1.terme].sorted()
                      == ["MenuiserieVidal", "Menuiseries Vidal"])
    }

    func testUnLexiqueSainNaAucunePaireSuspecte() {
        XCTAssertTrue(lexique.ressemblances().isEmpty)
    }

    func testFusionnerGardeLaNoteEtFaitDuTermeAbandonneUneVariante() {
        var avecDoublon = lexique
        avecDoublon.entrees.append(EntreeLexique(terme: "Menuiseries Vidal", variantes: ["Menuiserie Vidal"],
                                                 categorie: .entreprise))
        avecDoublon.fusionner("MenuiserieVidal", dans: "Menuiseries Vidal")

        XCTAssertEqual(avecDoublon.entrees.count, 3)
        let retenue = avecDoublon.entrees.first { $0.terme == "Menuiseries Vidal" }
        XCTAssertNotNil(retenue)
        XCTAssertEqual(retenue?.note, "Fabricant de menuiseries.",
                       "la note de l'entrée abandonnée ne doit pas être perdue")
        XCTAssertTrue(retenue!.variantes.contains("MenuiserieVidal"),
                      "le terme abandonné devient une faute connue")
        XCTAssertTrue(retenue!.variantes.contains("Menuiserie Vidal"))
    }

    func testFusionnerUnTermeInconnuNeCasseRien() {
        var copie = lexique
        copie.fusionner("Inexistant", dans: "Deployo")
        XCTAssertEqual(copie.entrees.count, 3)
    }
}
