import AVFoundation
import Foundation

/// Réduit un enregistrement une fois qu'il a servi.
///
/// La capture écrit sans compression, et c'est délibéré : compresser pendant la
/// réunion coûterait du processeur et de la batterie, précisément ce qu'on
/// cherche à éviter (chantier § 4.6). Mais rien n'oblige à conserver ce format
/// ensuite.
///
/// **Mesuré le 19/08/2026 : trois essais d'enregistrement occupaient 863 Mo**,
/// dont 700 Mo pour une seule visioconférence de trente minutes. À ce rythme,
/// cent réunions demanderaient une trentaine de gigaoctets. En AAC, la même
/// réunion tient dans quelques dizaines de mégaoctets.
///
/// La compression n'intervient **qu'après validation du transcript** : tant que
/// le texte n'est pas relu et jugé bon, l'original reste intact — on peut avoir
/// à retranscrire, et une transcription travaille mieux sur le son d'origine.
public enum CompressionAudio {

    public enum Erreur: Error, LocalizedError {
        case introuvable(URL)
        case echec(String)

        public var errorDescription: String? {
            switch self {
            case .introuvable(let url):
                "L'enregistrement \(url.lastPathComponent) est introuvable."
            case .echec(let detail):
                "L'enregistrement n'a pas pu être compressé. \(detail)"
            }
        }
    }

    /// Compresse en `.m4a` et **supprime l'original seulement en cas de
    /// succès** : un enregistrement effacé ne se retrouve jamais.
    ///
    /// - Returns: le fichier produit, et ce qu'il a fait gagner.
    @discardableResult
    public static func compresser(_ source: URL,
                                  vers destination: URL? = nil) async throws -> (url: URL,
                                                                                 avant: Int,
                                                                                 apres: Int) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw Erreur.introuvable(source) }
        let avant = (try? fm.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0

        let cible = destination ?? source.deletingPathExtension().appendingPathExtension("m4a")
        if fm.fileExists(atPath: cible.path) { try? fm.removeItem(at: cible) }

        let actif = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: actif,
                                                presetName: AVAssetExportPresetAppleM4A) else {
            throw Erreur.echec("le format de cet enregistrement n'est pas convertible")
        }
        export.outputURL = cible
        export.outputFileType = .m4a

        do {
            try await export.export(to: cible, as: .m4a)
        } catch {
            try? fm.removeItem(at: cible)
            throw Erreur.echec(error.localizedDescription)
        }

        guard fm.fileExists(atPath: cible.path) else {
            throw Erreur.echec("aucun fichier n'a été produit")
        }
        let apres = (try? fm.attributesOfItem(atPath: cible.path)[.size] as? Int) ?? 0
        // L'original ne part qu'une fois le remplaçant écrit et mesuré.
        try? fm.removeItem(at: source)
        return (cible, avant, apres)
    }

    /// « 700 Mo devenus 28 Mo » — ce que l'écran a besoin de dire.
    public static func gain(avant: Int, apres: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB]
        return "\(f.string(fromByteCount: Int64(avant))) devenus "
            + "\(f.string(fromByteCount: Int64(apres)))"
    }
}
