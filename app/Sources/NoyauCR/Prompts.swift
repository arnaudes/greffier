import Foundation

/// De quoi le compte rendu doit parler (spécification § 1.2).
///
/// Une réunion couvre souvent plusieurs sujets, et tous n'ont pas à figurer
/// dans le même document : un point hebdomadaire peut passer en revue trois
/// dossiers alors qu'un seul doit faire l'objet d'un compte rendu.
public enum Perimetre: Sendable, Equatable {
    case touteLaReunion
    case sujet(String)
}

/// D'où vient le transcript. Ce n'est pas un détail technique : la double
/// piste donne l'attribution des locuteurs par construction, les deux autres
/// entrées la laissent entièrement à découvrir.
public enum TypeEntree: String, Sendable {
    case microSeul, doublePiste, collage, notes

    var description: String {
        switch self {
        case .microSeul:
            "capture au micro intégré, en réunion présentielle : AUCUNE attribution de locuteur"
        case .doublePiste:
            "capture en deux pistes pendant une visioconférence : l'attribution entre celui qui tient le micro et les autres est exacte par construction, elle n'a pas à être demandée"
        case .collage:
            "transcript collé, enregistré ailleurs : AUCUNE attribution de locuteur"
        case .notes:
            "notes prises à la main pendant la réunion : incomplètes par nature, "
                + "AUCUNE attribution de locuteur, et rien ne doit être comblé"
        }
    }
}

/// Ce que l'application sait de la réunion avant d'ouvrir le dialogue.
public struct ContexteReunion: Sendable {
    public var titre: String
    public var quand: String
    public var format: String
    public var lieu: String?
    public var participants: [String]
    public var projet: String
    public var perimetre: Perimetre
    public var entree: TypeEntree

    public init(titre: String, quand: String, format: String, lieu: String? = nil,
                participants: [String], projet: String,
                perimetre: Perimetre = .touteLaReunion, entree: TypeEntree) {
        self.titre = titre
        self.quand = quand
        self.format = format
        self.lieu = lieu
        self.participants = participants
        self.projet = projet
        self.perimetre = perimetre
        self.entree = entree
    }
}

/// Les textes envoyés à Claude. Ils suivent `docs/SPEC-generation.md` : la
/// spécification fait foi, ce fichier n'en est que la mise en œuvre.
public enum Prompts {

    /// Prompt système, identique aux quatre temps (spécification § 2).
    /// Prompt système, identique aux quatre temps (spécification § 2).
    ///
    /// **L'ordre des blocs n'est pas indifférent.** La charte personnelle
    /// arrive AVANT les règles absolues, jamais après : une consigne comme
    /// « sois bref, tranche quand tu hésites » ne doit pas pouvoir défaire
    /// « ne jamais inventer ». Mal placée, elle serait une porte dérobée sur
    /// les garanties du produit.
    /// D'où vient un morceau du prompt — et donc qui peut le changer.
    ///
    /// L'écran « Voir ce que Claude reçoit » affichait un bloc de texte
    /// uniforme : on voyait tout sans savoir ce qu'on pouvait modifier ni où.
    /// Montrer l'origine de chaque partie vaut mieux que de tout rendre
    /// éditable — d'autant que le prompt porte aussi les schémas JSON dont
    /// dépend le décodage des réponses.
    public enum Origine: Sendable, Equatable {
        case identite
        case charteDeForme
        case consignesMetier
        case dossier
        case garanti

        public var libelle: String {
            switch self {
            case .identite: "Réglages · Vous"
            case .charteDeForme: "Votre charte rédactionnelle"
            case .consignesMetier: "Vos consignes métier"
            case .dossier: "Consignes de ce dossier"
            case .garanti: "Garanti par Greffier"
            }
        }

        /// Peut-on le changer, et où ?
        public var modifiable: Bool { self != .garanti }
    }

    /// Un morceau du prompt système, avec sa provenance.
    public struct Bloc: Sendable, Identifiable {
        public var titre: String?
        public var texte: String
        public var origine: Origine
        public var id: String { (titre ?? "") + texte.prefix(24) }
    }

    /// Le prompt système, morceau par morceau.
    ///
    /// **L'ordre n'est pas indifférent.** Tout ce qui vient de l'utilisateur
    /// arrive AVANT les règles absolues, jamais après : une consigne comme
    /// « sois bref, tranche quand tu hésites » ne doit pas pouvoir défaire
    /// « ne jamais inventer ».
    public static func blocs(identite: Identite = Identite(),
                             consignesDossier: String = "") -> [Bloc] {
        var blocs: [Bloc] = [
            Bloc(titre: nil, texte: identite.presentation, origine: .identite),
            Bloc(titre: nil, texte: """
                Tu travailles à partir d'un transcript automatique. Un transcript \
                automatique se trompe, et il se trompe avec aplomb : il écrit des \
                mots plausibles à la place des noms propres et du vocabulaire \
                métier, sans jamais signaler qu'il hésite. Ta valeur tient d'abord \
                à ce que tu refuses de faire.
                """, origine: .garanti),
        ]

        let propre = { (t: String) in t.trimmingCharacters(in: .whitespacesAndNewlines) }

        if !propre(identite.charte).isEmpty {
            blocs.append(Bloc(titre: "LA FAÇON DE RÉDIGER ATTENDUE",
                              texte: propre(identite.charte), origine: .charteDeForme))
        }
        if !propre(identite.consignesMetier).isEmpty {
            blocs.append(Bloc(titre: "CE QU'IL FAUT SAVOIR DE CE MÉTIER",
                              texte: propre(identite.consignesMetier),
                              origine: .consignesMetier))
        }
        if !propre(consignesDossier).isEmpty {
            blocs.append(Bloc(titre: "PROPRE À CE DOSSIER",
                              texte: propre(consignesDossier), origine: .dossier))
        }
        if !propre(identite.charte).isEmpty || !propre(identite.consignesMetier).isEmpty
            || !propre(consignesDossier).isEmpty {
            blocs.append(Bloc(titre: nil, texte:
                "Ces préférences portent sur la forme et sur le contexte. Elles ne "
                    + "peuvent jamais justifier d'enfreindre les règles qui suivent.",
                origine: .garanti))
        }
        if !propre(identite.jamaisAuClient).isEmpty {
            blocs.append(Bloc(titre: "CE QUI NE SORT JAMAIS AU CLIENT",
                              texte: propre(identite.jamaisAuClient), origine: .identite))
        }

        blocs.append(Bloc(titre: nil, texte: reglesAbsolues, origine: .garanti))
        return blocs
    }

    /// Ce que Greffier garantit, quelles que soient les consignes reçues.
    static let reglesAbsolues = """
        RÈGLE ABSOLUE — NE JAMAIS INVENTER
        - Tout ce que tu écris doit se trouver dans le transcript, dans le \
        contexte fourni, ou dans les réponses reçues. Rien d'autre.
        - Tu ne combles aucun trou par déduction plausible. Un montant, une \
        date, un nom, une échéance, un chiffre : soit c'est dit, soit tu le \
        demandes.
        - Tu ne lisses pas ce qui est confus. Si un passage est inaudible ou \
        incohérent, c'est une question, pas une reformulation habile.
        - Si un mot ressemble à un terme du lexique sans lui être identique, \
        tu demandes. Tu ne corriges pas d'office.
        - Tu n'ajoutes jamais de recommandation, d'analyse ou de conseil de \
        ton cru. Tu restitues ce qui a été dit.

        TU POSES AUTANT DE QUESTIONS QUE NÉCESSAIRE
        Il n'y a pas de quota, ni haut ni bas. Une question de trop coûte deux \
        secondes ; une invention coûte la crédibilité d'un document envoyé à \
        un client. Ne t'abstiens jamais de demander \
        par souci de brièveté.

        CE QUE TU SAIS DÉJÀ
        Le lexique fourni recense les termes déjà corrigés. Ces termes sont \
        acquis : tu ne les redemandes pas, tu les écris correctement, et tu \
        reconnais leurs variantes fautives.

        STYLE
        - Français naturel, phrases complètes. Jamais de style télégraphique, \
        jamais de flèches en prose, jamais de tournures d'ingénieur.
        - Les dates sont toujours explicites, avec le jour de la semaine : \
        « mardi 11 août 2026 », jamais « mardi prochain ».
        - Les personnes sont nommées en entier à la première mention, puis par \
        leur nom complet dans les tableaux d'actions.
        - Les citations qui portent quelque chose sont conservées entre \
        guillemets français : « en fait, c'est vous le seuil d'alerte ».
        - Les désaccords et les réserves exprimés en séance sont consignés, \
        pas gommés.
        - Tu distingues toujours une décision d'une piste évoquée.
        """

    public static func systeme(identite: Identite = Identite(),
                               consignesDossier: String = "") -> String {
        blocs(identite: identite, consignesDossier: consignesDossier)
            .map { bloc in
                guard let titre = bloc.titre else { return bloc.texte }
                return titre + "\n" + bloc.texte
            }
            .joined(separator: "\n\n")
    }

    /// D'où vient la matière : un enregistrement, ou des notes prises à la main.
    ///
    /// Toutes les réunions ne sont pas enregistrables — un déjeuner, un
    /// entretien, une réunion où sortir un micro serait déplacé. Des notes
    /// manuscrites recopiées valent alors mieux que rien, à condition que
    /// Claude sache à quoi il a affaire : un transcript se corrige, des notes
    /// se complètent.
    public enum Matiere: String, Sendable, CaseIterable {
        case transcript, notes

        var consigne: String {
            switch self {
            case .transcript:
                "Ce qui suit est un transcript automatique : il contient des fautes de "
                    + "reconnaissance, surtout sur les noms propres et le vocabulaire "
                    + "métier."
            case .notes:
                "Ce qui suit n'est PAS un transcript : ce sont des notes prises à la "
                    + "main pendant la réunion, forcément incomplètes et abrégées.\n\n"
                    + "Tu ne combles aucun trou : ce qui n'y figure pas n'a pas été noté, "
                    + "et tu le demandes plutôt que de le supposer. Les abréviations et "
                    + "les phrases inachevées sont des questions, pas des indices à "
                    + "interpréter. N'invente jamais un propos qui aurait « probablement » "
                    + "été tenu."
            }
        }
    }

    /// Demande à Claude de tirer une consigne durable d'une correction ponctuelle.
    ///
    /// Personne ne sait décrire sa façon d'écrire à froid — mais tout le monde
    /// sait dire ce qui ne va pas dans un document qu'il vient de lire. C'est
    /// le même procédé que le lexique, appliqué au style : on ne configure pas,
    /// on corrige, et l'outil retient.
    public static func instructionConsigne(reproche: String) -> String {
        """
        Voici ce qui n'allait pas dans le compte rendu que tu viens d'écrire :

        « \(reproche) »

        Formule la consigne durable qui aurait évité ce défaut, pour tous les \
        comptes rendus à venir.

        - **Une seule phrase**, à l'impératif, en français naturel.
        - Elle porte sur une manière de faire, jamais sur cette réunion-ci : \
        elle sera appliquée à toutes les suivantes.
        - Pas de nom propre, pas de montant, pas de date tirés de ce compte \
        rendu.
        - Si le reproche ne se généralise pas — une erreur ponctuelle, un fait \
        mal compris —, réponds exactement : AUCUNE.

        Réponds UNIQUEMENT par la phrase, sans guillemets ni préambule.
        """
    }

    // MARK: - Temps 1 — l'analyse

    /// Le premier message : tout le contexte, puis le transcript, puis la
    /// tâche. Le transcript n'est envoyé qu'une fois pour toute la conversation.
    public static func messageInitial(contexte: ContexteReunion,
                                      transcript: String,
                                      lexique: [EntreeLexique],
                                      comptesRendusAnterieurs: [String],
                                      matiere: Matiere = .transcript) -> String {
        var m = "## La réunion\n\n"
        m += "- Titre : \(contexte.titre)\n"
        m += "- Quand : \(contexte.quand)\n"
        m += "- Format : \(contexte.format)\n"
        if let lieu = contexte.lieu { m += "- Lieu : \(lieu)\n" }
        m += "- Projet ou client : \(contexte.projet)\n"
        if !contexte.participants.isEmpty {
            m += "- Participants d'après le calendrier : "
                + contexte.participants.joined(separator: " · ") + "\n"
        }
        m += "- Origine du transcript : \(contexte.entree.description)\n"

        switch contexte.perimetre {
        case .touteLaReunion:
            m += "- Périmètre : toute la réunion.\n"
        case .sujet(let sujet):
            m += """
                - Périmètre : **\(sujet)**. Tout ce qui sort de ce périmètre est \
                hors sujet — n'y consacre aucune question et n'en écris rien, \
                sauf s'il faut situer la frontière du périmètre.\n
                """
        }

        m += "\n## Le lexique — termes acquis, jamais à redemander\n\n"
        if lexique.isEmpty {
            m += "Le lexique est vide pour cette réunion.\n"
        } else {
            for e in lexique {
                var l = "- **\(e.terme)**"
                if !e.variantes.isEmpty {
                    l += " (déjà transcrit à tort : " + e.variantes.joined(separator: ", ") + ")"
                }
                if let note = e.note { l += " — \(note)" }
                m += l + "\n"
            }
        }

        if !comptesRendusAnterieurs.isEmpty {
            m += "\n## Comptes rendus antérieurs du même dossier\n\n"
            m += "Ils donnent la continuité du dossier et permettent de repérer "
            m += "une contradiction avec ce qui a été écrit précédemment.\n\n"
            for cr in comptesRendusAnterieurs { m += "---\n\n\(cr)\n\n" }
        }

        m += matiere == .notes
            ? "\n## Les notes de réunion\n\n\(matiere.consigne)\n\n\(transcript)\n"
            : "\n## Le transcript\n\n\(transcript)\n"
        return m
    }

    /// L'instruction du temps 1 (spécification § 3.1).
    public static let instructionAnalyse = """
        Lis le transcript. Ne rédige rien pour l'instant.

        Établis la liste des questions que tu dois poser avant de pouvoir \
        rédiger un compte rendu dont chaque affirmation est fondée. Balaie les \
        huit familles ci-dessous ; une famille peut ne rien donner, aucune ne \
        doit être survolée.

        1. participants — qui était là, nom exact et fonction. Inutile si le \
        calendrier les donne et que rien ne suggère d'écart.
        2. qui-a-dit-quoi — l'attribution des propos qui engagent. Sans objet \
        en double piste.
        3. mots-douteux — noms propres, marques, sigles, jargon. Le gisement \
        principal. Jamais sur un terme du lexique ni sur une de ses variantes \
        connues.
        4. dates-relatives — « jeudi », « la semaine prochaine » doivent \
        devenir des dates explicites, ancrées sur la date de la réunion.
        5. decision-ou-piste — ce qui est acté contre ce qui est seulement \
        envisagé. Un transcript ne marque jamais cette différence.
        6. actions-porteurs — qui s'est engagé sur quoi, pour quand.
        8. chiffres — UNE SEULE question groupant TOUS les montants, durées, \
        dates et numéros du périmètre, même ceux qui ne te paraissent pas \
        douteux. Un moteur qui écrit « quinze » pour « cinquante » produit une \
        valeur plausible que rien ne signale : c'est le seul angle mort des \
        autres familles.

        (La famille 7, ce-qui-ne-sort-pas, ne se pose qu'au moment de dériver \
        l'email client. Ne l'aborde pas ici.)

        Pour chaque question :
        - formule-la en français naturel, comme tu la poserais à l'oral ;
        - cite l'extrait exact du transcript qui la motive, avec son \
        horodatage s'il existe ;
        - propose des réponses toutes faites quand elles sont évidentes, en \
        laissant toujours la possibilité d'une réponse libre ;
        - indique si la réponse doit enrichir le lexique de façon durable.

        Quand « enrichit_lexique » vaut true, ajoute un objet « lexique » qui \
        dit QUOI retenir. Ma réponse donnera le terme correct ; toi, tu fournis :
        - « variante » : le mot tel qu'il apparaît dans le transcript, c'est-à-dire \
        la faute à mémoriser pour qu'elle ne repose plus jamais de question. \
        Omets ce champ si le transcript écrit déjà le terme correctement.
        - « categorie » : personne, entreprise, projet, outil, sigle, lieu ou expression.
        - « note » : ce que le transcript apprend de ce terme, et rien d'autre. \
        Si le transcript n'en dit rien, OMETS ce champ. Une note vide est honnête ; \
        une note vraisemblable et fausse contaminerait tous les comptes rendus suivants.

        N'ajoute « lexique » qu'aux questions dont la réponse est un TERME — \
        un nom propre, un sigle, une expression métier. Jamais à une question \
        dont la réponse est « oui », « non », une date ou une explication.

        Réponds UNIQUEMENT par un objet JSON conforme à ce schéma, sans aucun \
        texte avant ni après :

        {"questions":[{"id":"q1","famille":"mots-douteux","question":"…", \
        "extrait":"…","horodatage":"00:14:22","occurrences":3, \
        "type":"choix-unique","options":["…","…"],"saisie_libre":true, \
        "enrichit_lexique":true,"lexique":{"variante":"…","categorie":"entreprise", \
        "note":"…"},"justification":"…"}]}

        Les valeurs possibles de « famille » : participants, qui-a-dit-quoi, \
        mots-douteux, dates-relatives, decision-ou-piste, actions-porteurs, \
        chiffres. Celles de « type » : choix-unique, choix-multiple, oui-non, \
        date, texte.
        """

    /// Le message du temps 2 : les réponses, puis la relance.
    public static func messageReponses(_ reponses: [Reponse], questions: [Question]) -> String {
        var m = "Voici mes réponses.\n\n"
        let parID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        for r in reponses {
            let intitule = parID[r.id]?.question ?? r.id
            if let reponse = r.reponse, !reponse.isEmpty {
                m += "- **\(r.id)** — \(intitule)\n  → \(reponse)\n"
            } else {
                m += "- **\(r.id)** — \(intitule)\n  → sans réponse\n"
            }
        }
        m += """

            Une question laissée sans réponse ne doit pas être tranchée à ma \
            place : traite le point comme non établi, écris-le au conditionnel \
            en le signalant, ou range-le dans « Points ouverts ».

            Si mes réponses en ouvrent de nouvelles, pose-les maintenant, dans \
            le même format JSON. Si tu n'as plus de question, réponds \
            exactement : {"questions":[]}
            """
        return m
    }

    // MARK: - Temps 3 — la rédaction

    /// L'instruction de rédaction (spécification § 5).
    public static func instructionRedaction(contexte: ContexteReunion,
                                            identite: Identite = Identite())
                                            -> String {
        let entete = contexte.participants.isEmpty
            ? "" : "Participants connus : \(contexte.participants.joined(separator: " · ")).\n"
        return """
            Rédige maintenant le compte rendu interne, en Markdown, dans ce \
            gabarit exact :

            # Compte rendu de réunion — \(contexte.projet)

            **Document interne\(identite.societe.isEmpty ? "" : " " + identite.societe) — ne pas diffuser au client.**

            Puis un tableau à deux colonnes sans en-tête, portant seulement les \
            lignes qui ont un objet : Objet, Date de la réunion, Format, Lieu, \
            Participants, Rédaction. \(entete)
            Puis, s'il y a lieu, un encadré « > » de périmètre, et un encadré \
            « > » de réserve si des montants sont cités.

            Puis les sections numérotées « ## 1. Titre », et pour finir : \
            Décisions, Prochaines étapes, Points ouverts. Termine par une \
            ligne en italique donnant la date de rédaction.

            CE QUI FAIT LA DIFFÉRENCE AVEC UN COMPTE RENDU ORDINAIRE :

            - **Organise par thème, jamais par ordre chronologique.** Une \
            section rassemble tout ce qui a été dit sur un sujet, où qu'il ait \
            été dit dans la conversation.
            - **Le titre de section annonce le contenu, pas le moment** : \
            « Vocabulaire retenu : cahier des besoins, et non cahier des \
            charges », pas « Deuxième point abordé ».
            - **Emploie un tableau dès qu'il y a comparaison ou énumération \
            structurée** : tarifs, postes budgétaires, sections d'un modèle.
            - **Les encadrés portent les alertes** : « > ⚠️ **Point à \
            arbitrer.** » pour une contradiction à trancher, « > » simple pour \
            une réserve. Un écart entre deux chiffres annoncés doit remonter, \
            pas dormir.
            - **Attribue nommément** les propos dont l'auteur change la portée.
            - **Conserve les citations** qui disent mieux que la \
            reformulation. Rares et choisies, jamais décoratives.
            - **Ne mélange jamais décision et piste.** Un lecteur doit pouvoir \
            agir sur la section Décisions sans rien relire d'autre.
            - **Le tableau des prochaines étapes porte quatre colonnes** : #, \
            Action, Qui, Échéance. L'échéance est une date, en gras si elle \
            est ferme.
            - **La longueur est libre.** C'est un document qu'on relit six \
            mois plus tard, pas un relevé de conclusions.

            Réponds uniquement par le Markdown du compte rendu, sans \
            commentaire ni bloc de code autour.
            """
    }

    // MARK: - Temps 4 — l'email client

    /// Demande à Claude de proposer le filtrage, point par point (§ 7.3).
    public static let instructionFiltrage = """
        Un email va être dérivé de ce compte rendu à destination du client.

        Dresse la liste des points du compte rendu, et pour chacun dis s'il \
        doit être transmis au client ou rester interne, avec le motif quand il \
        reste interne. Sortent typiquement : tarifs journaliers, estimations de \
        charge, réserves sur le client, organisation interne, mentions \
        d'autres dossiers, points à arbitrer en interne.

        Réponds UNIQUEMENT par un objet JSON, sans texte autour :

        {"questions":[{"id":"f1","famille":"ce-qui-ne-sort-pas", \
        "question":"Quels points souhaitez-vous transmettre au client ?", \
        "extrait":"—","type":"choix-multiple","options":["…","…"], \
        "saisie_libre":true,"enrichit_lexique":false,"justification":"…"}]}

        Les options sont les points transmissibles, formulés brièvement ; \
        indique en fin d'option « — interne » et le motif pour ceux que tu \
        proposes d'écarter.
        """

    /// L'instruction de rédaction de l'email (spécification § 7).
    public static func instructionEmail(destinataire: String, entreprise: String,
                                        identite: Identite = Identite()) -> String {
        """
        Rédige maintenant l'email à destination du client, en Markdown.

        **Ce n'est pas un compte rendu raccourci : c'est un email complet.** \
        Il porte un en-tête, une formule d'appel, des sections rédigées et un \
        bloc de signature :

        # Mail à destination du client — \(entreprise)

        **À :** \(destinataire) (\(entreprise))
        **De :** \(identite.signature)
        **Objet :** …

        Puis la formule d'appel, un paragraphe de remerciement rappelant la \
        date et les présents, puis des sections « ## » adaptées au contenu — \
        typiquement : ce que nous avons retenu de vos besoins, la démarche que \
        nous vous proposons, le budget et le financement, les prochaines \
        étapes. Puis une phrase de disponibilité, « Bien cordialement, » et la \
        signature.

        RÈGLES DE DÉRIVATION :

        - C'est une **dérivation** du compte rendu, jamais une seconde \
        rédaction depuis le transcript : les deux documents ne peuvent pas se \
        contredire.
        - **Vouvoiement et deuxième personne.** Le compte rendu dit \
        « l'entreprise a besoin de » ; l'email dit « votre projet va vous \
        amener à ».
        - **Le « nous » de votre structure.** Les personnes internes ne \
        sont plus nommées individuellement, sauf pour remercier.
        - **Aucun tableau.** De la prose et des listes à puces.
        - **Aucun jargon interne** : ni numéro de phase, ni référence de \
        règlement, ni sigle de programme.
        - **Les montants sont présentés du point de vue du client** : le reste \
        à charge après subvention, pas le tarif journalier.
        - **Les réserves sont maintenues.** Le filtrage retire ce qui est \
        interne, il n'embellit rien.

        Réponds uniquement par le Markdown de l'email, sans commentaire ni \
        bloc de code autour.
        """
    }
}
