import Foundation
import NoyauCR
import Observation
import SwiftUI

/// Les réglages de l'application, conservés d'une exécution à l'autre.
///
/// Aucun secret n'y transite : l'authentification est celle de Claude Code,
/// déjà en place sur la machine.
@Observable
@MainActor
final class Reglages {

    /// Les calendriers dont Greffier tient compte. Par défaut le seul calendrier
    /// professionnel : sans cette liste, l'outil proposerait d'enregistrer
    /// l'Assomption (chantier § 4.2).
    var calendriersRetenus: Set<String> {
        didSet { defaults.set(Array(calendriersRetenus), forKey: Cle.calendriers) }
    }

    /// Le modèle demandé à Claude. Les deux étapes qui passent par lui —
    /// repérer les ambiguïtés dans quarante-cinq minutes de verbatim, puis
    /// rédiger — sont les plus exigeantes de la chaîne : aucune tâche mécanique
    /// ne justifierait un petit modèle. Vide signifie « celui de la session ».
    var modele: String {
        didSet { defaults.set(modele, forKey: Cle.modele) }
    }

    /// Le modèle de repli. Il évite que l'application s'arrête net en pleine
    /// rédaction quand la limite du forfait tombe : le dialogue continue sur un
    /// modèle plus léger, et le bandeau le dit.
    var modeleRepli: String {
        didSet { defaults.set(modeleRepli, forKey: Cle.modeleRepli) }
    }

    /// Faut-il conserver les enregistrements une fois le transcript produit ?
    /// Ce sont des fichiers volumineux, et le transcript corrigé suffit le plus
    /// souvent — mais un audio effacé ne se retrouve jamais.
    var conserverLesEnregistrements: Bool {
        didSet { defaults.set(conserverLesEnregistrements, forKey: Cle.conserverAudio) }
    }

    /// Prévenir quand une version plus récente est publiée.
    ///
    /// Activé par défaut : celui qui reçoit l'application n'ira pas consulter
    /// un dépôt de son propre chef. Désactivable, parce qu'une notification
    /// qu'on ne peut pas faire taire devient un reproche — et parce qu'on
    /// travaille parfois sans réseau.
    var previenirDesMisesAJour: Bool {
        didSet { defaults.set(previenirDesMisesAJour, forKey: Cle.previenir) }
    }

    /// Le parcours de premier lancement a-t-il été suivi ?
    ///
    /// Les pièces existaient — conditions vérifiées, écran d'identité, demandes
    /// d'autorisation — mais rien ne les mettait bout à bout : on découvrait
    /// qu'il fallait Claude Code au moment où la rédaction échouait. L'écran de
    /// bienvenue ne s'affiche qu'une fois, et se laisse écarter.
    var accueilFait: Bool {
        didSet { defaults.set(accueilFait, forKey: Cle.accueilFait) }
    }

    /// La version qui tournait au lancement précédent.
    ///
    /// Sert à dire « Greffier a été mis à jour » une fois l'installation faite.
    /// Sans cela, on installe, l'application redémarre, et **rien ne dit si
    /// c'est passé** — on rouvre le menu pour vérifier, on n'en est pas sûr,
    /// et on finit par ne plus se mettre à jour du tout.
    var derniereVersionLancee: String {
        didSet { defaults.set(derniereVersionLancee, forKey: Cle.derniereVersionLancee) }
    }

    /// Quand on a regardé pour la dernière fois. Une fois par jour suffit.
    var derniereVerification: Date? {
        didSet { defaults.set(derniereVerification, forKey: Cle.derniereVerification) }
    }

    /// La version qu'on a choisi d'ignorer. Écarter une mise à jour ne doit pas
    /// la faire revenir le lendemain.
    var versionEcartee: String {
        didSet { defaults.set(versionEcartee, forKey: Cle.versionEcartee) }
    }

    /// Qui vous êtes, et pour qui vous travaillez.
    ///
    /// Rangée avec les données plutôt que dans les préférences du système :
    /// elle appartient au dossier de travail, se sauvegarde avec lui, et se
    /// relit en clair. Ce sont vos mots, pas un réglage technique.
    var identite: Identite {
        didSet { try? identite.enregistrer(vers: Reglages.cheminIdentite(dossierDeTravail)) }
    }

    static func cheminIdentite(_ dossier: URL) -> URL {
        dossier.appendingPathComponent("identite.json")
    }

    /// Où vivent les comptes rendus, le lexique et les enregistrements.
    ///
    /// **Ce chemin était écrit en dur dans le code**, et pointait sur le dépôt
    /// des sources : les documents étaient liés à l'emplacement du code, et
    /// l'application n'avait tout simplement nulle part où écrire sur une autre
    /// machine.
    ///
    /// Les données quittent donc le dépôt. Deux bénéfices d'un seul geste : le
    /// code devient publiable sans emporter de comptes rendus clients, et
    /// déplacer le dépôt ne casse plus rien.
    var dossierDeTravail: URL {
        didSet { defaults.set(dossierDeTravail.path, forKey: Cle.dossierDeTravail) }
    }

    /// Là où les documents vont quand rien n'a été choisi : à côté des autres
    /// documents de l'utilisateur, pas dans un dossier de code.
    static var dossierParDefaut: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents")
            .appendingPathComponent("Greffier")
    }

    /// La tenue de l'application. Sombre par défaut — c'est la direction
    /// retenue — mais une salle de réunion en plein soleil demande l'inverse.
    var apparence: Apparence {
        didSet { defaults.set(apparence.rawValue, forKey: Cle.apparence) }
    }

    enum Apparence: String, CaseIterable, Identifiable {
        case sombre, clair, systeme
        var id: String { rawValue }

        var libelle: String {
            switch self {
            case .sombre: "Sombre"
            case .clair: "Clair"
            case .systeme: "Comme macOS"
            }
        }

        var symbole: String {
            switch self {
            case .sombre: "moon.fill"
            case .clair: "sun.max.fill"
            case .systeme: "circle.lefthalf.filled"
            }
        }

        /// `nil` laisse la fenêtre suivre le réglage du système.
        var schema: ColorScheme? {
            switch self {
            case .sombre: .dark
            case .clair: .light
            case .systeme: nil
            }
        }

        /// La tenue suivante dans la bascule. « Comme macOS » n'y figure pas :
        /// c'est un choix qu'on pose dans les réglages, pas une étape par
        /// laquelle passer chaque fois qu'on veut changer de lumière.
        var suivante: Apparence { self == .clair ? .sombre : .clair }
    }

    /// Le chemin du programme Claude Code, quand la détection automatique n'y
    /// arrive pas. Vide signifie « cherche-le tout seul », ce qui est le cas
    /// courant : ce réglage n'existe que pour ne jamais rester bloqué sur une
    /// installation inhabituelle.
    var cheminClaude: String {
        didSet { defaults.set(cheminClaude, forKey: Cle.cheminClaude) }
    }

    private enum Cle {
        static let calendriers = "calendriersRetenus"
        static let modele = "modele"
        static let modeleRepli = "modeleRepli"
        static let conserverAudio = "conserverLesEnregistrements"
        static let cheminClaude = "cheminClaude"
        static let apparence = "apparence"
        static let dossierDeTravail = "dossierDeTravail"
        static let previenir = "previenirDesMisesAJour"
        static let accueilFait = "accueilFait"
        static let derniereVersionLancee = "derniereVersionLancee"
        static let derniereVerification = "derniereVerification"
        static let versionEcartee = "versionEcartee"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enregistres = defaults.stringArray(forKey: Cle.calendriers)
        calendriersRetenus = Set(enregistres ?? ["Calendrier"])
        modele = defaults.string(forKey: Cle.modele) ?? ""
        modeleRepli = defaults.string(forKey: Cle.modeleRepli) ?? ""
        conserverLesEnregistrements = defaults.object(forKey: Cle.conserverAudio) as? Bool ?? true
        cheminClaude = defaults.string(forKey: Cle.cheminClaude) ?? ""
        apparence = Apparence(rawValue: defaults.string(forKey: Cle.apparence) ?? "")
            ?? .sombre
        let dossier = (defaults.string(forKey: Cle.dossierDeTravail)?.isEmpty == false)
            ? URL(fileURLWithPath: defaults.string(forKey: Cle.dossierDeTravail)!)
            : Reglages.dossierParDefaut
        dossierDeTravail = dossier
        identite = Identite.charger(depuis: Reglages.cheminIdentite(dossier))
        previenirDesMisesAJour = defaults.object(forKey: Cle.previenir) as? Bool ?? true
        derniereVerification = defaults.object(forKey: Cle.derniereVerification) as? Date
        versionEcartee = defaults.string(forKey: Cle.versionEcartee) ?? ""
        accueilFait = defaults.bool(forKey: Cle.accueilFait)
        derniereVersionLancee = defaults.string(forKey: Cle.derniereVersionLancee) ?? ""
    }

    var configClaude: ConfigClaude {
        let voulu = cheminClaude.trimmingCharacters(in: .whitespaces)
        return ConfigClaude(binaire: voulu.isEmpty ? "claude" : voulu,
                            modele: modele.isEmpty ? nil : modele,
                            modeleRepli: modeleRepli.isEmpty ? nil : modeleRepli)
    }

    var calendrier: Calendrier { Calendrier(calendriersRetenus: calendriersRetenus) }
}
