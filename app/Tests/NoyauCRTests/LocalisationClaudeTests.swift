import XCTest
@testable import NoyauCR

/// La recherche du programme Claude Code.
///
/// Le défaut que ces cas verrouillent a coûté un compte rendu perdu le
/// 17/08/2026 : l'application, lancée depuis le Finder, n'héritait pas du
/// `PATH` du terminal et échouait sur un « code 127 » incompréhensible, après
/// avoir pourtant enregistré et transcrit toute la réunion.
final class LocalisationClaudeTests: XCTestCase {

    func testUnCheminCompletEstPrisTelQuel() {
        // `/bin/ls` existe sur toute machine macOS et sert ici de programme
        // témoin : ce qui est vérifié, c'est qu'un chemin explicite court-
        // circuite entièrement la détection automatique.
        XCTAssertEqual(LocalisationClaude.resoudre("/bin/ls"), "/bin/ls")
    }

    func testUnCheminInexistantNeRendRien() {
        XCTAssertNil(LocalisationClaude.resoudre("/usr/local/n-existe-pas/claude"))
    }

    func testUnCheminAvecTildeEstDilate() {
        // Le réglage est saisi à la main : Camille écrira « ~/.local/bin/claude »
        // aussi naturellement que le chemin complet.
        let candidats = LocalisationClaude.candidats(nom: "claude")
        XCTAssertFalse(candidats.contains { $0.hasPrefix("~") },
                       "aucun candidat ne doit garder un tilde non dilaté")
    }

    func testLesEmplacementsHabituelsSontCouverts() {
        let candidats = LocalisationClaude.candidats(nom: "claude")
        let maison = NSHomeDirectory()
        for attendu in ["\(maison)/.claude/local/claude",
                        "\(maison)/.local/bin/claude",
                        "/opt/homebrew/bin/claude",
                        "/usr/local/bin/claude"] {
            XCTAssertTrue(candidats.contains(attendu), "manque : \(attendu)")
        }
    }

    func testLeDossierDuProgrammeArriveEnTeteDuChemin() {
        let env = LocalisationClaude.environnement(pour: "/opt/truc/bin/claude")
        let chemins = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        XCTAssertEqual(chemins.first, "/opt/truc/bin")
        // Claude Code appelle git et d'autres outils : les dossiers du système
        // doivent rester présents.
        XCTAssertTrue(chemins.contains("/usr/bin"))
    }

    func testLeCheminNeRepeteJamaisUnDossier() {
        let env = LocalisationClaude.environnement(pour: "/usr/bin/claude")
        let chemins = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        XCTAssertEqual(chemins.count, Set(chemins).count,
                       "un PATH avec des doublons s'allonge à chaque exécution")
    }
}
