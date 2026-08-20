import Compression
import Foundation

/// Écrit une archive ZIP, parce qu'un document Word en est une.
///
/// Un `.docx` est un ZIP contenant quelques fichiers XML. On l'a longtemps
/// évité pour cette raison, en produisant du RTF à la place. C'était un mauvais
/// calcul : l'archive tient en une centaine de lignes, et sans elle on ne
/// contrôle ni les styles, ni les tableaux, ni la pagination.
///
/// Seul le strict nécessaire est écrit : pas de dossier, pas de chiffrement,
/// pas d'archive de plus de quatre gigaoctets. Un compte rendu de réunion n'en
/// approche pas.
enum ArchiveZip {

    struct Fichier {
        let nom: String
        let contenu: Data
    }

    static func ecrire(_ fichiers: [Fichier]) -> Data {
        var archive = Data()
        var index = Data()
        var decalages: [Int] = []

        for fichier in fichiers {
            decalages.append(archive.count)
            let brut = fichier.contenu
            let comprime = deflate(brut)
            // Un fichier minuscule grossit à la compression : on le range tel
            // quel plutôt que de l'alourdir.
            let (methode, charge) = (comprime != nil && comprime!.count < brut.count)
                ? (UInt16(8), comprime!) : (UInt16(0), brut)
            let crc = crc32(brut)
            let nom = Data(fichier.nom.utf8)

            archive.append(entier32(0x0403_4B50))
            archive.append(entier16(20))          // version minimale
            archive.append(entier16(0))           // aucun indicateur
            archive.append(entier16(methode))
            archive.append(entier16(0))           // heure, figée
            archive.append(entier16(0x0021))      // date, figée au 1er janvier 1980
            archive.append(entier32(crc))
            archive.append(entier32(UInt32(charge.count)))
            archive.append(entier32(UInt32(brut.count)))
            archive.append(entier16(UInt16(nom.count)))
            archive.append(entier16(0))           // aucun champ supplémentaire
            archive.append(nom)
            archive.append(charge)

            index.append(entier32(0x0201_4B50))
            index.append(entier16(20))            // version d'écriture
            index.append(entier16(20))            // version minimale
            index.append(entier16(0))
            index.append(entier16(methode))
            index.append(entier16(0))
            index.append(entier16(0x0021))
            index.append(entier32(crc))
            index.append(entier32(UInt32(charge.count)))
            index.append(entier32(UInt32(brut.count)))
            index.append(entier16(UInt16(nom.count)))
            index.append(entier16(0))             // champ supplémentaire
            index.append(entier16(0))             // commentaire
            index.append(entier16(0))             // numéro de disque
            index.append(entier16(0))             // attributs internes
            index.append(entier32(0))             // attributs externes
            index.append(entier32(UInt32(decalages.last!)))
            index.append(nom)
        }

        let debutIndex = archive.count
        archive.append(index)
        archive.append(entier32(0x0605_4B50))
        archive.append(entier16(0))               // disque courant
        archive.append(entier16(0))               // disque de l'index
        archive.append(entier16(UInt16(fichiers.count)))
        archive.append(entier16(UInt16(fichiers.count)))
        archive.append(entier32(UInt32(index.count)))
        archive.append(entier32(UInt32(debutIndex)))
        archive.append(entier16(0))               // aucun commentaire
        return archive
    }

    // MARK: - Les briques

    /// Compression « deflate » brute, celle que le format ZIP attend.
    private static func deflate(_ source: Data) -> Data? {
        guard !source.isEmpty else { return nil }
        var sortie: Data?
        source.withUnsafeBytes { entree in
            guard let depart = entree.bindMemory(to: UInt8.self).baseAddress else { return }
            let capacite = source.count + 64
            let tampon = UnsafeMutablePointer<UInt8>.allocate(capacity: capacite)
            defer { tampon.deallocate() }
            let ecrits = compression_encode_buffer(tampon, capacite, depart, source.count,
                                                   nil, COMPRESSION_ZLIB)
            // Zéro signifie que le résultat n'aurait pas tenu : on renonce.
            if ecrits > 0 { sortie = Data(bytes: tampon, count: ecrits) }
        }
        return sortie
    }

    /// La somme de contrôle du format ZIP. Une archive dont le CRC est faux
    /// s'ouvre en apparence, puis Word annonce un document corrompu.
    static func crc32(_ donnees: Data) -> UInt32 {
        var somme: UInt32 = 0xFFFF_FFFF
        for octet in donnees {
            somme ^= UInt32(octet)
            for _ in 0..<8 {
                somme = (somme & 1) == 1 ? (somme >> 1) ^ 0xEDB8_8320 : somme >> 1
            }
        }
        return somme ^ 0xFFFF_FFFF
    }

    private static func entier16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }
    private static func entier32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
              UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }
}
