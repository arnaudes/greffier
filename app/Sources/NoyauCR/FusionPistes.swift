import Foundation

/// Recompose un transcript unique à partir des deux pistes d'une
/// visioconférence, en rendant à chacun ce qu'il a dit.
///
/// C'est ici que se paie l'avantage de la double piste : l'attribution n'est
/// pas devinée par un modèle, elle est **exacte par construction**. Ce qui
/// vient du micro est de l'utilisateur, ce qui vient du son système est des autres.
public enum FusionPistes {

    /// Un tour de parole reconstitué.
    public struct Tour: Sendable, Equatable {
        public var locuteur: String
        public var texte: String
        public var debut: TimeInterval
    }

    /// Au-delà de ce silence, un même locuteur est considéré comme ayant
    /// entamé un nouveau tour de parole. Une seconde et demie sépare une
    /// respiration d'une reprise après l'autre — valeur à ajuster à l'usage.
    public static let silenceQuiSepare: TimeInterval = 1.5

    /// Assemble les deux pistes en un transcript horodaté et attribué.
    ///
    /// - Parameters:
    ///   - moi: les segments du micro.
    ///   - lesAutres: les segments du son système.
    ///   - nomMoi: comment nommer celui qui tient le micro.
    ///   - nomAutres: comment nommer le reste. Sans liste de participants, on
    ///     ne peut pas distinguer plusieurs interlocuteurs : la double piste
    ///     sépare « moi » et « les autres », pas les autres entre eux.
    public static func fusionner(moi: [Transcription.Segment],
                                 lesAutres: [Transcription.Segment],
                                 nomMoi: String,
                                 nomAutres: String = "Les autres participants") -> String {
        let tours = (regrouper(moi, locuteur: nomMoi)
                     + regrouper(lesAutres, locuteur: nomAutres))
            .sorted { $0.debut < $1.debut }

        return tours.map { tour in
            "\(horodatage(tour.debut)) **\(tour.locuteur)** — \(tour.texte)"
        }.joined(separator: "\n\n")
    }

    /// Regroupe les segments d'une même piste en tours de parole.
    ///
    /// Sans ce regroupement, le transcript arriverait mot par mot et
    /// deviendrait illisible : la reconnaissance rend un segment par mot.
    public static func regrouper(_ segments: [Transcription.Segment],
                                 locuteur: String,
                                 silence: TimeInterval = silenceQuiSepare) -> [Tour] {
        var tours: [Tour] = []
        var mots: [String] = []
        var debut: TimeInterval = 0
        var finPrecedente: TimeInterval = -.infinity

        func clore() {
            guard !mots.isEmpty else { return }
            tours.append(Tour(locuteur: locuteur,
                              texte: assembler(mots),
                              debut: debut))
            mots = []
        }

        for segment in segments.sorted(by: { $0.debut < $1.debut }) {
            let texte = segment.texte.trimmingCharacters(in: .whitespaces)
            guard !texte.isEmpty else { continue }
            if mots.isEmpty || segment.debut - finPrecedente > silence {
                clore()
                debut = segment.debut
            }
            mots.append(texte)
            finPrecedente = segment.fin
        }
        clore()
        return tours
    }

    /// Recolle les mots en respectant la ponctuation **française** : la
    /// reconnaissance rend « bonjour » puis « , » comme deux segments distincts.
    ///
    /// La règle n'est pas la même pour tous les signes. Le point et la virgule
    /// se collent au mot ; le point d'interrogation, le point d'exclamation, le
    /// point-virgule, les deux-points et le guillemet fermant prennent une
    /// espace insécable devant. Un compte rendu qui finit chez un client se doit
    /// d'être correct là-dessus, et l'espace doit être insécable pour qu'aucun
    /// retour à la ligne ne sépare le signe du mot.
    static func assembler(_ mots: [String]) -> String {
        let collants: Set<Character> = [",", ".", "…", ")", "]"]
        let precedesDEspace: Set<Character> = ["?", "!", ";", ":", "»"]
        let insecable = "\u{00A0}"

        var phrase = ""
        for mot in mots {
            guard let premier = mot.first else { continue }
            if phrase.isEmpty {
                phrase = mot
            } else if collants.contains(premier) {
                phrase += mot
            } else if precedesDEspace.contains(premier) {
                phrase += insecable + mot
            } else if phrase.last == "«" {
                phrase += insecable + mot
            } else if phrase.last == "'" || phrase.last == "’" || phrase.last == "(" {
                phrase += mot
            } else {
                phrase += " " + mot
            }
        }
        return phrase
    }

    static func horodatage(_ secondes: TimeInterval) -> String {
        let total = Int(secondes.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// L'en-tête que porte un transcript issu d'une double piste, pour qu'on
    /// sache d'où vient l'attribution en le relisant dans six mois.
    public static func enTete(reunion: String, quand: String,
                              nomMoi: String) -> String {
        """
        # Transcript — \(reunion)

        **Quand :** \(quand)
        **Capture :** visioconférence en deux pistes, micro et son du système.
        **Attribution :** exacte par construction — ce qui vient du micro est \
        de \(nomMoi), le reste des autres participants. La double piste ne \
        distingue pas les autres entre eux.

        ---

        """
    }
}
