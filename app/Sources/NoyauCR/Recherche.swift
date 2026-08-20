import Foundation

/// Retrouver une réunion parmi toutes celles qu'on a tenues.
///
/// Classer ne suffit pas. Un dossier par client et un sous-dossier par réunion
/// rendent l'arborescence lisible, mais on ne se souvient pas toujours du
/// client — on se souvient d'un mot dit en séance, d'un montant, d'un nom.
///
/// Aucun index n'est construit, et c'est délibéré : trois cents comptes rendus
/// pèsent quelques mégaoctets et se parcourent en un instant, tandis qu'un
/// index se désynchronise dès qu'on déplace un fichier à la main. La règle du
/// projet vaut ici comme ailleurs — une lecture fraîche vaut mieux qu'un cache
/// qui ment.
public enum Recherche {

    /// Une réunion trouvée, avec de quoi comprendre pourquoi elle l'a été.
    public struct Resultat: Sendable, Identifiable {
        public var projet: String
        public var reunion: Rangement.Reunion
        /// Le passage qui a fait retenir ce compte rendu, avec ce qui l'entoure.
        public var extrait: String?
        /// Là où le terme a été trouvé : dans le titre, ou dans le corps.
        public var dansLeTitre: Bool
        public var id: String { reunion.dossier.path }
    }

    /// Cherche dans les noms de dossiers et dans le corps des comptes rendus.
    ///
    /// - Parameter limite: au-delà, on s'arrête. Une recherche qui rend deux
    ///   cents résultats n'aide pas plus que zéro.
    public static func chercher(_ demande: String, racine: URL,
                                limite: Int = 40) -> [Resultat] {
        let terme = demande.trimmingCharacters(in: .whitespacesAndNewlines)
        guard terme.count >= 2 else { return [] }
        let cible = Lexique.normaliser(terme)

        let racineCR = racine.appendingPathComponent("comptes-rendus")
        let projets = (try? FileManager.default.contentsOfDirectory(atPath: racineCR.path)) ?? []
        var trouves: [Resultat] = []

        for projet in projets.sorted() where !projet.hasPrefix(".") {
            for reunion in Rangement.reunions(racine: racine, projet: projet) {
                if trouves.count >= limite { return trouves }

                // Le nom du client et l'objet de la réunion d'abord : c'est ce
                // dont on se souvient le plus souvent.
                let entete = Lexique.normaliser("\(projet) \(reunion.nom)")
                if entete.contains(cible) {
                    trouves.append(Resultat(projet: projet, reunion: reunion,
                                            extrait: nil, dansLeTitre: true))
                    continue
                }

                guard let url = reunion.compteRendu,
                      let texte = try? String(contentsOf: url, encoding: .utf8) else { continue }
                guard let extrait = extraitAutour(de: terme, dans: texte) else { continue }
                trouves.append(Resultat(projet: projet, reunion: reunion,
                                        extrait: extrait, dansLeTitre: false))
            }
        }
        return trouves
    }

    /// Toutes les réunions ayant produit un compte rendu, de la plus récente à
    /// la plus ancienne. C'est ce qu'on montre avant toute recherche.
    public static func toutes(racine: URL, limite: Int = 200) -> [Resultat] {
        let racineCR = racine.appendingPathComponent("comptes-rendus")
        let projets = (try? FileManager.default.contentsOfDirectory(atPath: racineCR.path)) ?? []
        var trouves: [Resultat] = []
        for projet in projets where !projet.hasPrefix(".") {
            for reunion in Rangement.reunions(racine: racine, projet: projet)
            where reunion.compteRendu != nil {
                trouves.append(Resultat(projet: projet, reunion: reunion,
                                        extrait: nil, dansLeTitre: false))
            }
        }
        return trouves
            .sorted { ($0.reunion.date ?? .distantPast) > ($1.reunion.date ?? .distantPast) }
            .prefix(limite)
            .map { $0 }
    }

    /// Le passage qui entoure le terme, pour comprendre sans ouvrir.
    ///
    /// Sans lui, une liste de résultats oblige à ouvrir chaque document pour
    /// savoir lequel était le bon.
    static func extraitAutour(de terme: String, dans texte: String,
                              largeur: Int = 90) -> String? {
        let normalise = Lexique.normaliser(texte)
        let cible = Lexique.normaliser(terme)
        guard let position = normalise.range(of: cible) else { return nil }

        // La normalisation change les longueurs : on revient au texte d'origine
        // par la proportion, ce qui suffit à cadrer un extrait lisible.
        let avancement = normalise.distance(from: normalise.startIndex,
                                            to: position.lowerBound)
        let approximatif = min(texte.count - 1,
                               max(0, Int(Double(avancement)
                                          * Double(texte.count)
                                          / Double(max(1, normalise.count)))))
        let centre = texte.index(texte.startIndex, offsetBy: approximatif)
        let debut = texte.index(centre, offsetBy: -largeur / 2,
                                limitedBy: texte.startIndex) ?? texte.startIndex
        let fin = texte.index(centre, offsetBy: largeur / 2,
                              limitedBy: texte.endIndex) ?? texte.endIndex

        let brut = String(texte[debut..<fin])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !brut.isEmpty else { return nil }
        return (debut == texte.startIndex ? "" : "…") + brut
            + (fin == texte.endIndex ? "" : "…")
    }
}
