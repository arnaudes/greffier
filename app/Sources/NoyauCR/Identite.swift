import Foundation

/// Qui utilise l'application, et pour qui il travaille.
///
/// **Ces informations étaient écrites dans le code.** Le prompt système
/// nommait une personne et sa société, la fusion des pistes portait ce nom en
/// valeur par défaut, et le filtrage des participants cherchait ce prénom.
/// Chez quelqu'un d'autre, ses propres propos auraient été attribués aux
/// autres, et les comptes rendus auraient été écrits pour un tiers.
///
/// Ce n'est pas qu'un nom à remplacer : le prompt explique **ce qu'est** la
/// société, ce qui ne sort jamais au client, la façon dont on y parle de soi.
/// C'est cette connaissance qui rend le compte rendu juste — d'où le champ
/// `activite`, qu'un champ vide laisserait plat.
public struct Identite: Codable, Sendable, Equatable {

    /// Comment vous nommer dans les comptes rendus, et à qui attribuer la
    /// piste du micro en visioconférence.
    public var nom: String
    /// Votre fonction, telle qu'elle apparaîtra en signature.
    public var fonction: String
    /// Votre société ou votre structure.
    public var societe: String
    /// Ce que fait votre société, en une ou deux phrases.
    ///
    /// C'est le champ qui décide de la justesse du compte rendu : sans lui,
    /// Claude ignore ce qui est un livrable, un jalon, une réserve.
    public var activite: String
    /// Ce qui ne sort jamais au client, propre à votre métier.
    public var jamaisAuClient: String
    /// Ce qu'il faut savoir de votre métier pour rédiger juste.
    ///
    /// Distinct de la charte, qui porte sur la **forme**. Celui-ci porte sur le
    /// **fond** : « nos réunions comportent toujours un point sécurité »,
    /// « distingue les jalons contractuels des jalons indicatifs ». C'est ce
    /// qui manque le plus souvent, et qu'aucune description d'activité ne
    /// capture.
    public var consignesMetier: String

    /// Votre charte rédactionnelle, en français libre.
    ///
    /// Elle s'ajoute aux règles du produit, elle ne les remplace pas : le
    /// prompt la place **avant** les règles absolues, pour qu'un « sois bref,
    /// tranche quand tu hésites » ne puisse jamais défaire « ne jamais
    /// inventer ». Mal placée, elle serait une porte dérobée sur les garanties.
    public var charte: String

    public init(nom: String = "", fonction: String = "", societe: String = "",
                activite: String = "", jamaisAuClient: String = "", charte: String = "",
                consignesMetier: String = "") {
        self.nom = nom
        self.fonction = fonction
        self.societe = societe
        self.activite = activite
        self.jamaisAuClient = jamaisAuClient
        self.charte = charte
        self.consignesMetier = consignesMetier
    }

    /// A-t-on de quoi rédiger un compte rendu qui tienne debout ?
    ///
    /// Le nom suffit à ne pas se tromper de locuteur ; le reste améliore, mais
    /// n'empêche pas de travailler. Bloquer sur un formulaire incomplet
    /// coûterait plus que de produire un compte rendu perfectible.
    public var utilisable: Bool {
        !nom.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Ce qui manque pour que les comptes rendus soient au niveau.
    public var incomplet: [String] {
        var manques: [String] = []
        if nom.trimmingCharacters(in: .whitespaces).isEmpty { manques.append("votre nom") }
        if societe.trimmingCharacters(in: .whitespaces).isEmpty {
            manques.append("votre société")
        }
        if activite.trimmingCharacters(in: .whitespaces).isEmpty {
            manques.append("ce que fait votre société")
        }
        return manques
    }

    /// Comment vous présenter à Claude. Rendu vide si rien n'est renseigné,
    /// plutôt que d'inventer une identité par défaut.
    var presentation: String {
        let personne = [nom, fonction].filter { !$0.isEmpty }.joined(separator: ", ")
        var phrase = ""
        if !personne.isEmpty && !societe.isEmpty {
            phrase = "Tu assistes \(personne) à \(societe), dans la rédaction de ses "
                + "comptes rendus de réunion."
        } else if !personne.isEmpty {
            phrase = "Tu assistes \(personne) dans la rédaction de ses comptes rendus "
                + "de réunion."
        } else {
            phrase = "Tu rédiges des comptes rendus de réunion."
        }
        if !activite.isEmpty {
            phrase += " \(activite.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return phrase
    }

    /// La signature d'un email client.
    public var signature: String {
        [nom, fonction, societe].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    /// Reconnaît la personne dans une liste de participants, pour ne pas
    /// l'attribuer aux « autres » en visioconférence.
    public func estMoi(_ participant: String) -> Bool {
        let cible = Lexique.compacterPublic(nom)
        guard !cible.isEmpty else { return false }
        let candidat = Lexique.compacterPublic(participant)
        if candidat == cible || candidat.contains(cible) || cible.contains(candidat) {
            return true
        }
        // Le prénom seul suffit souvent dans une invitation de réunion.
        guard let prenom = nom.split(separator: " ").first.map(String.init),
              prenom.count >= 3 else { return false }
        return candidat.contains(Lexique.compacterPublic(prenom))
    }

    // MARK: - Persistance

    /// Un décodage tolérant : un champ absent reprend sa valeur d'origine.
    ///
    /// **Sans cela, ajouter un champ efface l'identité de tout le monde.** Le
    /// jour où « ce qu'il faut savoir de votre métier » est apparu, les
    /// fiches écrites la veille n'avaient pas la clé : le décodage échouait en
    /// entier, `charger` rendait une identité vide, et l'application réclamait
    /// un nom déjà renseigné. Bien pire que le bandeau : les comptes rendus
    /// partaient alors sans « ce qui ne sort jamais au client », c'est-à-dire
    /// sans le filtre de l'email.
    ///
    /// Une fiche vieille d'une version doit toujours s'ouvrir. C'est vrai ici
    /// et pour tout ce qu'on ajoutera ensuite.
    public init(from decodeur: Decoder) throws {
        let c = try decodeur.container(keyedBy: CodingKeys.self)
        func lire(_ cle: CodingKeys) -> String {
            (try? c.decode(String.self, forKey: cle)) ?? ""
        }
        nom = lire(.nom)
        fonction = lire(.fonction)
        societe = lire(.societe)
        activite = lire(.activite)
        jamaisAuClient = lire(.jamaisAuClient)
        charte = lire(.charte)
        consignesMetier = lire(.consignesMetier)
    }

    public static func charger(depuis url: URL) -> Identite {
        guard let data = try? Data(contentsOf: url),
              let lue = try? JSONDecoder().decode(Identite.self, from: data) else {
            return Identite()
        }
        return lue
    }

    public func enregistrer(vers url: URL) throws {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encodeur.encode(self).write(to: url, options: .atomic)
    }
}
