import AVFoundation
import Foundation

/// Réunit les deux pistes d'une visioconférence en **un seul fichier stéréo**,
/// celui qui tient à gauche et les autres à droite.
///
/// Arbitré le 19/08/2026 après écoute de deux essais. Le mélange pur — tout le
/// monde au centre — était l'autre candidat, mais il perd **définitivement**
/// l'attribution : retranscrire depuis lui redonnerait un verbatim sans
/// locuteurs, précisément ce qu'Greffier évite. La séparation gauche/droite tient
/// dans un seul fichier tout en gardant chaque canal extractible : on peut
/// retranscrire des années plus tard avec l'attribution exacte.
///
/// Le piège, mesuré avant d'écrire une ligne : **les deux pistes n'ont ni le
/// même nombre de canaux ni le même échantillonnage.** Le micro rend du mono à
/// 24 kHz, le son système du stéréo à 48 kHz. Les entrelacer sans les ramener
/// au même format donnerait un fichier accéléré d'un côté et ralenti de
/// l'autre. Leurs durées, en revanche, ne diffèrent que de 16 millisecondes :
/// l'alignement est bon, aucun décalage à corriger.
public enum FusionAudio {

    public enum Erreur: Error, LocalizedError {
        case introuvable(URL)
        case formatIllisible(String)
        case echec(String)

        public var errorDescription: String? {
            switch self {
            case .introuvable(let url):
                "La piste \(url.lastPathComponent) est introuvable."
            case .formatIllisible(let detail):
                "Le format d'une des pistes n'a pas pu être lu. \(detail)"
            case .echec(let detail):
                "Les deux pistes n'ont pas pu être réunies. \(detail)"
            }
        }
    }

    /// L'échantillonnage commun. Celui du son système, pour ne dégrader que la
    /// piste du micro — qui est déjà la moins riche.
    static let frequence: Double = 48_000

    /// Écrit un fichier stéréo où le canal gauche porte `moi` et le droit
    /// `lesAutres`.
    ///
    /// - Returns: le fichier produit et sa taille.
    @discardableResult
    public static func unifier(moi: URL, lesAutres: URL,
                               vers destination: URL,
                               progression: ((Double) -> Void)? = nil) throws
                               -> (url: URL, taille: Int) {
        let fm = FileManager.default
        for piste in [moi, lesAutres] where !fm.fileExists(atPath: piste.path) {
            throw Erreur.introuvable(piste)
        }

        let gauche = try monophonique(moi)
        let droite = try monophonique(lesAutres)

        // La piste la plus longue commande : l'autre est complétée par du
        // silence plutôt que tronquée. Mieux vaut quelques secondes muettes
        // qu'une fin de réunion coupée.
        let frames = max(gauche.count, droite.count)
        guard frames > 0 else { throw Erreur.echec("les deux pistes sont vides") }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: frequence, channels: 2) else {
            throw Erreur.formatIllisible("stéréo \(Int(frequence)) Hz refusé")
        }
        if fm.fileExists(atPath: destination.path) { try? fm.removeItem(at: destination) }
        try fm.createDirectory(at: destination.deletingLastPathComponent(),
                               withIntermediateDirectories: true)

        let fichier = try AVAudioFile(forWriting: destination, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: frequence,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ])

        // Écriture par tranches d'une seconde : une réunion d'une heure
        // occuperait sinon plus d'un gigaoctet en mémoire.
        let tranche = AVAudioFrameCount(frequence)
        var position = 0
        while position < frames {
            let combien = min(Int(tranche), frames - position)
            guard let tampon = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(combien)) else {
                throw Erreur.echec("mémoire insuffisante pour une tranche")
            }
            tampon.frameLength = AVAudioFrameCount(combien)
            guard let canaux = tampon.floatChannelData else {
                throw Erreur.echec("tampon stéréo inutilisable")
            }
            for i in 0..<combien {
                let j = position + i
                canaux[0][i] = j < gauche.count ? gauche[j] : 0
                canaux[1][i] = j < droite.count ? droite[j] : 0
            }
            try fichier.write(from: tampon)
            position += combien
            progression?(Double(position) / Double(frames))
        }

        let taille = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
        return (destination, taille)
    }

    /// Lit une piste et la rend en mono à la fréquence commune.
    ///
    /// Les canaux d'une piste stéréo sont moyennés : le son d'une
    /// visioconférence n'a pas de spatialisation utile, et n'en garder qu'un
    /// perdrait la moitié du signal si l'application d'en face n'écrit que sur
    /// un côté.
    static func monophonique(_ url: URL) throws -> [Float] {
        let fichier: AVAudioFile
        do { fichier = try AVAudioFile(forReading: url) } catch {
            throw Erreur.formatIllisible(error.localizedDescription)
        }
        let entree = fichier.processingFormat
        guard let cible = AVAudioFormat(standardFormatWithSampleRate: frequence, channels: 1) else {
            throw Erreur.formatIllisible("mono \(Int(frequence)) Hz refusé")
        }
        guard let convertisseur = AVAudioConverter(from: entree, to: cible) else {
            throw Erreur.formatIllisible("conversion depuis \(entree) impossible")
        }

        var resultat: [Float] = []
        resultat.reserveCapacity(Int(Double(fichier.length) * frequence / entree.sampleRate) + 1)

        let tailleLecture = AVAudioFrameCount(entree.sampleRate)   // une seconde
        let tailleSortie = AVAudioFrameCount(frequence * 2)        // marge pour le rééchantillonnage
        var fini = false

        while !fini {
            guard let sortie = AVAudioPCMBuffer(pcmFormat: cible, frameCapacity: tailleSortie) else {
                throw Erreur.echec("mémoire insuffisante")
            }
            var erreur: NSError?
            let statut = convertisseur.convert(to: sortie, error: &erreur) { _, etat in
                guard let tampon = AVAudioPCMBuffer(pcmFormat: entree,
                                                    frameCapacity: tailleLecture) else {
                    etat.pointee = .endOfStream; return nil
                }
                do { try fichier.read(into: tampon, frameCount: tailleLecture) } catch {
                    etat.pointee = .endOfStream; return nil
                }
                if tampon.frameLength == 0 { etat.pointee = .endOfStream; return nil }
                etat.pointee = .haveData
                return tampon
            }
            if let erreur { throw Erreur.echec(erreur.localizedDescription) }
            if let canal = sortie.floatChannelData?[0], sortie.frameLength > 0 {
                resultat.append(contentsOf: UnsafeBufferPointer(start: canal,
                                                                count: Int(sortie.frameLength)))
            }
            if statut == .endOfStream || statut == .error { fini = true }
        }
        return resultat
    }

    /// « deux pistes de 55 Mo devenues un fichier de 52 Mo ».
    public static func lisible(_ octets: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB]
        return f.string(fromByteCount: Int64(octets))
    }
}
