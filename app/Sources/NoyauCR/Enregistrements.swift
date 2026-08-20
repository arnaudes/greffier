import Foundation

/// L'inventaire des fichiers audio : ceux qui n'ont rien produit, et ceux qui
/// accompagnent un compte rendu.
///
/// Arbitré le 19/08/2026. Un enregistrement qui reste dans la zone de transit
/// n'a, par construction, produit aucun compte rendu — l'audio n'en sort qu'au
/// moment où le compte rendu est enregistré. Mais **l'âge ne dit rien de sa
/// valeur** : un orphelin ancien est soit une réunion oubliée, et on veut la
/// traiter, soit un raté, et il n'y avait aucune raison d'attendre pour
/// l'effacer. C'est la **durée** qui discrimine.
public enum Enregistrements {

    /// Sous cette durée, ce n'est pas une réunion. Même seuil que l'alerte sur
    /// les transcripts anormalement courts.
    public static let dureeDUnEssai: TimeInterval = 120

    /// Au-delà de cet âge, un orphelin qu'on n'a pas traité est compressé de
    /// lui-même : il ne perd rien et cesse de peser vingt-cinq fois son poids.
    public static let ageAvantCompression: TimeInterval = 30 * 24 * 3600

    /// L'audio d'une réunion traitée est proposé à la suppression au-delà de
    /// douze mois. Arbitré long à dessein : garder coûte quelques gigaoctets,
    /// supprimer est irréversible, et un engagement pris en réunion ressort à
    /// l'échéance d'un dossier — six à douze mois.
    public static let ageAvantSuggestion: TimeInterval = 365 * 24 * 3600

    /// Au-delà de ce total, la suggestion se fait plus visible : c'est là que
    /// le volume devient un vrai sujet, pas avant.
    public static let volumeQuiInterpelle = 5 * 1024 * 1024 * 1024

    // MARK: - Ce qui n'a rien produit

    public struct Orphelin: Sendable, Identifiable {
        public var url: URL
        public var date: Date
        public var duree: TimeInterval
        public var taille: Int
        public var id: String { url.path }

        /// Trop court pour être une réunion : un essai, un faux départ.
        public var estUnEssai: Bool { duree < dureeDUnEssai }
        public var estCompresse: Bool { url.pathExtension.lowercased() == "m4a" }

        /// Ce que l'application propose d'en faire.
        public var conseil: String {
            if estUnEssai {
                return "Trop court pour être une réunion : sans doute un essai."
            }
            return "Cet enregistrement n'a jamais donné de compte rendu. "
                + "Vous pouvez encore le transcrire."
        }
    }

    /// Ce qui traîne dans la zone de transit, du plus récent au plus ancien.
    public static func orphelins(racine: URL) -> [Orphelin] {
        let dossier = racine.appendingPathComponent("enregistrements")
        let fm = FileManager.default
        let noms = (try? fm.contentsOfDirectory(atPath: dossier.path)) ?? []
        return noms
            .filter { ["caf", "m4a"].contains(($0 as NSString).pathExtension.lowercased()) }
            .map { nom -> Orphelin in
                let url = dossier.appendingPathComponent(nom)
                let attributs = try? fm.attributesOfItem(atPath: url.path)
                return Orphelin(url: url,
                                date: (attributs?[.creationDate] as? Date) ?? Date(),
                                duree: dureeAudio(url),
                                taille: (attributs?[.size] as? Int) ?? 0)
            }
            .sorted { $0.date > $1.date }
    }

    /// Les orphelins assez vieux et assez longs pour mériter d'être compressés
    /// sans qu'on le demande.
    ///
    /// **Seul automatisme accepté**, parce qu'il ne détruit rien : le fichier
    /// reste transcriptible, il cesse simplement de peser vingt-cinq fois son
    /// poids. Les essais en sont exclus — les compresser occuperait le
    /// processeur pour économiser quelques mégaoctets sur des fichiers qu'on va
    /// effacer.
    public static func aCompresser(racine: URL, maintenant: Date = Date()) -> [Orphelin] {
        orphelins(racine: racine).filter {
            !$0.estUnEssai && !$0.estCompresse
                && maintenant.timeIntervalSince($0.date) > ageAvantCompression
        }
    }

    // MARK: - Ce qui accompagne un compte rendu

    public struct AudioRange: Sendable, Identifiable {
        public var url: URL
        public var projet: String
        public var reunion: String
        public var date: Date?
        public var taille: Int
        public var id: String { url.path }

        /// Le compte rendu a-t-il assez vieilli pour qu'on propose d'effacer
        /// son audio ?
        public func perime(maintenant: Date = Date()) -> Bool {
            guard let date else { return false }
            return maintenant.timeIntervalSince(date) > ageAvantSuggestion
        }
    }

    /// Tout l'audio rangé avec les comptes rendus, du plus récent au plus
    /// ancien.
    public static func rangés(racine: URL) -> [AudioRange] {
        let fm = FileManager.default
        let racineCR = racine.appendingPathComponent("comptes-rendus")
        let projets = (try? fm.contentsOfDirectory(atPath: racineCR.path)) ?? []
        var trouves: [AudioRange] = []

        for projet in projets where !projet.hasPrefix(".") {
            for reunion in Rangement.reunions(racine: racine, projet: projet) {
                let fabrication = Rangement.dossierFabrication(dans: reunion.dossier)
                let fichiers = (try? fm.contentsOfDirectory(atPath: fabrication.path)) ?? []
                for nom in fichiers
                where ["caf", "m4a"].contains((nom as NSString).pathExtension.lowercased()) {
                    let url = fabrication.appendingPathComponent(nom)
                    let taille = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                    trouves.append(AudioRange(url: url, projet: projet,
                                              reunion: reunion.titre, date: reunion.date,
                                              taille: taille))
                }
            }
        }
        return trouves.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    // MARK: - Dire les choses

    public static func lisible(_ octets: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB]
        return f.string(fromByteCount: Int64(octets))
    }

    public static func dureeLisible(_ secondes: TimeInterval) -> String {
        if secondes < 1 { return "vide" }
        if secondes < 60 { return "\(Int(secondes)) s" }
        let minutes = Int(secondes) / 60
        if minutes < 60 { return "\(minutes) min" }
        let reste = minutes % 60
        return reste == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(reste)"
    }

    static func dureeAudio(_ url: URL) -> TimeInterval {
        Transcription.duree(de: url)
    }
}
