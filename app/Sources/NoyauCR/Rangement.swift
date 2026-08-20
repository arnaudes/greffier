import Foundation

/// Où vivent les documents d'une réunion, et sous quels noms.
///
/// **L'unité de rangement est la réunion, pas le type de fichier.** Le premier
/// classement mettait les comptes rendus ensemble, les transcripts ensemble, et
/// répétait le contexte dans chaque nom : `CR-interne-MENUISERIES VIDAL-2026-08-19.md`.
/// Deux réunions suffisaient à mettre neuf fichiers à plat dans un dossier
/// client, et dix réunions en auraient mis quarante-cinq. Or ce qu'on cherche
/// six mois plus tard, c'est une réunion entière — le compte rendu, ce qui a
/// été dit, l'email envoyé.
///
/// ```
/// comptes-rendus/
///   MENUISERIES VIDAL/
///     19-08-2026 — Devis et subvention/
///       Compte rendu.md
///       Compte rendu.pdf
///       Transcript.md
///       Email client.md
///       Fabrication/          ← le HTML du PDF et l'audio compressé
/// ```
///
/// Le contexte venant du dossier, les noms de fichiers redeviennent courts.
public enum Rangement {

    /// Les noms de fichiers, une bonne fois : les écrire à la main ailleurs
    /// ferait diverger l'écriture de la lecture.
    public enum Fichier: String, CaseIterable {
        case compteRendu = "Compte rendu.md"
        case pdf = "Compte rendu.pdf"
        case transcript = "Transcript.md"
        case email = "Email client.md"
    }

    /// Ce qui ne s'ouvre jamais à la main : la page HTML dont le PDF est tiré,
    /// et l'enregistrement audio.
    public static let fabrication = "Fabrication"

    /// La date en tête du nom de dossier, année d'abord.
    ///
    /// Arbitré le 19/08/2026 : `DD-MM-YYYY` se lit mieux, mais il place
    /// « 01-09-2026 » avant « 19-08-2026 » dans le Finder — l'ordre du temps
    /// s'y perd. L'année d'abord, l'ordre alphabétique **est** l'ordre
    /// chronologique, partout et sans code.
    public static func dateDossier(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Relit la date qu'un nom de dossier porte, pour classer sans se fier à
    /// l'ordre alphabétique.
    public static func dateDe(dossier nom: String) -> Date? {
        let debut = nom.prefix(10)
        guard debut.count == 10 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(debut))
    }

    /// Le nom du dossier d'une réunion : sa date, puis son objet.
    public static func nomDeReunion(date: Date, objet: String) -> String {
        let propre = assainir(objet)
        return propre.isEmpty
            ? dateDossier(date)
            : "\(dateDossier(date)) — \(propre)"
    }

    /// Le nom d'un document destiné à sortir de Greffier.
    ///
    /// Dans le dossier de la réunion, « Compte rendu » suffit : le dossier dit
    /// déjà de quelle réunion il s'agit. En pièce jointe, ce nom ne dit plus
    /// rien — un destinataire se retrouve avec vingt fichiers homonymes dans
    /// ses téléchargements. Le nom porte donc la date, le client et l'objet.
    public static func nomDeFichier(projet: String, objet: String, date: Date) -> String {
        let morceaux = [dateDossier(date), assainir(projet), assainir(objet)]
            .filter { !$0.isEmpty }
        let nom = morceaux.joined(separator: " — ")
        return nom.isEmpty ? "Compte rendu" : nom
    }

    /// Un intitulé de réunion tel qu'un nom de dossier l'accepte.
    ///
    /// La barre oblique sépare les dossiers et les deux-points restent
    /// interdits sur macOS : les laisser passer casserait l'écriture sans rien
    /// dire. Les noms très longs sont coupés — un intitulé de réunion tient en
    /// quelques mots, et le compte rendu porte le titre complet.
    public static func assainir(_ texte: String) -> String {
        let interdits = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let propre = texte.components(separatedBy: interdits).joined(separator: " ")
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Un nom réduit à des points désignerait le dossier courant ou son
        // parent : il ouvrirait un chemin relatif au lieu de nommer un dossier.
        if propre.allSatisfy({ $0 == "." }) { return "" }
        guard propre.count > 70 else { return propre }
        return String(propre.prefix(70)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Les chemins

    /// Le dossier d'un client ou d'un projet.
    ///
    /// **Le nom est assaini, comme celui d'une réunion.** Il ne l'était pas :
    /// un client saisi « Client / Filiale » créait deux niveaux de dossiers, et
    /// le compte rendu disparaissait de la liste. Un nom commençant par deux
    /// points aurait écrit hors du dossier de travail.
    public static func dossierProjet(racine: URL, projet: String) -> URL {
        let propre = assainir(projet)
        return racine.appendingPathComponent("comptes-rendus")
            .appendingPathComponent(propre.isEmpty ? "Sans dossier" : propre)
    }

    public static func dossierReunion(racine: URL, projet: String,
                                      date: Date, objet: String) -> URL {
        dossierProjet(racine: racine, projet: projet)
            .appendingPathComponent(nomDeReunion(date: date, objet: objet))
    }

    /// Un dossier de réunion qui n'écrase aucun autre.
    ///
    /// **Deux réunions le même jour, chez le même client, sans intitulé,
    /// partageaient le même dossier** — et la seconde écrasait la première,
    /// compte rendu, transcript et audio compris. Le cas n'a rien de rare : on
    /// ne saisit pas toujours un titre, et une journée compte parfois deux
    /// points avec le même interlocuteur.
    ///
    /// Un dossier déjà occupé par un autre compte rendu reçoit donc un rang.
    public static func dossierLibre(racine: URL, projet: String,
                                    date: Date, objet: String) -> URL {
        let vise = dossierReunion(racine: racine, projet: projet, date: date, objet: objet)
        let fm = FileManager.default
        // Libre, ou déjà le nôtre : un dossier sans compte rendu est celui
        // qu'on vient de commencer.
        if !fm.fileExists(atPath: chemin(.compteRendu, dans: vise).path) { return vise }

        for rang in 2...20 {
            let suivant = vise.deletingLastPathComponent()
                .appendingPathComponent("\(vise.lastPathComponent) (\(rang))")
            if !fm.fileExists(atPath: chemin(.compteRendu, dans: suivant).path) {
                return suivant
            }
        }
        return vise
    }

    public static func chemin(_ fichier: Fichier, dans reunion: URL) -> URL {
        reunion.appendingPathComponent(fichier.rawValue)
    }

    public static func dossierFabrication(dans reunion: URL) -> URL {
        reunion.appendingPathComponent(fabrication)
    }

    // MARK: - Lire ce qui est rangé

    /// Une réunion trouvée sur le disque.
    public struct Reunion: Sendable {
        public var dossier: URL
        public var nom: String
        public var date: Date?
        /// L'objet, tel que le nom du dossier le porte.
        public var objet: String
        public var compteRendu: URL?
        public var pdf: URL?

        /// Comment la nommer dans une liste.
        public var titre: String {
            objet.isEmpty ? nom : objet
        }
    }

    /// Les réunions d'un projet, **de la plus récente à la plus ancienne**.
    ///
    /// Le tri se fait sur la date lue plutôt que sur le nom : un dossier
    /// renommé à la main, ou sans date en tête, ne doit pas désordonner la
    /// liste ni disparaître.
    public static func reunions(racine: URL, projet: String) -> [Reunion] {
        let dossier = dossierProjet(racine: racine, projet: projet)
        let noms = (try? FileManager.default.contentsOfDirectory(atPath: dossier.path)) ?? []
        return noms
            .filter { !$0.hasPrefix(".") }
            .compactMap { nom -> Reunion? in
                let url = dossier.appendingPathComponent(nom)
                var estDossier: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &estDossier),
                      estDossier.boolValue else { return nil }

                let cr = chemin(.compteRendu, dans: url)
                let pdf = chemin(.pdf, dans: url)
                let existe = FileManager.default.fileExists(atPath:)
                let date = dateDe(dossier: nom)
                let objet = date == nil
                    ? nom
                    : nom.dropFirst(10).trimmingCharacters(in: CharacterSet(charactersIn: " —-"))
                return Reunion(dossier: url, nom: nom, date: date, objet: objet,
                               compteRendu: existe(cr.path) ? cr : nil,
                               pdf: existe(pdf.path) ? pdf : nil)
            }
            .sorted { a, b in
                switch (a.date, b.date) {
                case let (x?, y?): x > y
                case (nil, _?): false
                case (_?, nil): true
                default: a.nom > b.nom
                }
            }
    }

    /// Combien de comptes rendus ce projet contient — ce que la colonne des
    /// dossiers affiche.
    public static func nombreDeComptesRendus(racine: URL, projet: String) -> Int {
        reunions(racine: racine, projet: projet).count { $0.compteRendu != nil }
    }
}
