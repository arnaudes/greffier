import Foundation

/// La chaîne complète : transcript → questions → réponses → documents
/// (spécification § 1).
///
/// Les quatre temps tiennent dans **une seule conversation** : le transcript,
/// volumineux, n'est envoyé qu'au premier message, et la rédaction dispose
/// ensuite de tout ce qui précède sans qu'on ait à le renvoyer.
public actor ChaineCR {

    private let pont: PontClaude
    private let contexte: ContexteReunion
    private var questionsPosees: [Question] = []
    private var demarree = false

    /// L'identité de qui rédige : elle décide de la façon dont Claude se
    /// présente le travail, et de la charte rédactionnelle appliquée.
    public init(contexte: ContexteReunion, config: ConfigClaude = ConfigClaude(),
                identite: Identite = Identite(), consignesDossier: String = "") {
        self.contexte = contexte
        self.identite = identite
        var c = config
        c.promptSysteme = Prompts.systeme(identite: identite,
                                          consignesDossier: consignesDossier)
        self.pont = PontClaude(config: c)
    }

    private let identite: Identite

    /// Prévient des limites du forfait plutôt que de s'y heurter.
    public func surveiller(limite: @escaping @Sendable (InfoLimite) -> Void) {
        pont.surLimite = limite
    }

    /// S'abonne au texte que Claude écrit, au fil de l'eau.
    ///
    /// Le pont captait déjà ce flux et **le jetait** : personne ne s'y
    /// abonnait. C'est pourtant la seule chose qu'on puisse montrer pendant
    /// que Claude travaille — il ne dit jamais où il en est, mais on peut voir
    /// le compte rendu s'écrire.
    public func surveillerLeTexte(_ suivre: @escaping @Sendable (String) -> Void) {
        pont.surTexte = suivre
    }

    public func terminer() { pont.arreter() }

    /// Tire une consigne durable d'un reproche fait au compte rendu.
    ///
    /// - Returns: la consigne, ou `nil` si le reproche ne se généralise pas.
    public func deduireUneConsigne(_ reproche: String) async throws -> String? {
        let brut = try await pont.envoyer(Prompts.instructionConsigne(reproche: reproche))
        let propre = ChaineCR.nettoyerMarkdown(brut)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "«»\"'"))
        // Claude répond AUCUNE quand le reproche tient à cette réunion-là et
        // n'a pas à devenir une règle.
        guard !propre.isEmpty, !propre.uppercased().hasPrefix("AUCUNE") else { return nil }
        return propre
    }

    // MARK: - Temps 1 et 2

    /// Envoie le contexte et le transcript, et rend la première liste de
    /// questions.
    public func analyser(transcript: String,
                         matiere: Prompts.Matiere = .transcript,
                         lexique: [EntreeLexique],
                         comptesRendusAnterieurs: [String] = []) async throws -> [Question] {
        guard !demarree else { throw ErreurPont.dejaEnCours }
        try pont.demarrer()
        demarree = true

        let message = Prompts.messageInitial(
            contexte: contexte, transcript: transcript,
            lexique: lexique, comptesRendusAnterieurs: comptesRendusAnterieurs,
            matiere: matiere)
            + "\n\n---\n\n" + Prompts.instructionAnalyse

        let brut = try await pont.envoyer(message)
        let questions = try Self.decoderQuestions(brut)
        questionsPosees = questions
        return questions
    }

    /// Transmet les réponses. Rend la vague suivante de questions, ou un
    /// tableau vide quand Claude n'a plus rien à demander — c'est cette boucle,
    /// et non un nombre de tours figé, qui met en œuvre « autant de questions
    /// que nécessaire ».
    public func repondre(_ reponses: [Reponse]) async throws -> [Question] {
        let brut = try await pont.envoyer(
            Prompts.messageReponses(reponses, questions: questionsPosees))
        let questions = try Self.decoderQuestions(brut)
        questionsPosees = questions
        return questions
    }

    // MARK: - Temps 3 et 4

    /// Le compte rendu interne, en Markdown.
    public func rediger() async throws -> String {
        let markdown = try await pont.envoyer(Prompts.instructionRedaction(contexte: contexte, identite: identite))
        return Self.nettoyerMarkdown(markdown)
    }

    /// Le filtrage proposé, point par point, à faire valider avant l'email.
    public func proposerFiltrage() async throws -> [Question] {
        let brut = try await pont.envoyer(Prompts.instructionFiltrage)
        let questions = try Self.decoderQuestions(brut)
        questionsPosees = questions
        return questions
    }

    /// L'email client, dérivé du compte rendu déjà rédigé.
    public func redigerEmail(destinataire: String, entreprise: String,
                             pointsRetenus: [String]) async throws -> String {
        var message = Prompts.instructionEmail(destinataire: destinataire, entreprise: entreprise,
                                              identite: identite)
        if !pointsRetenus.isEmpty {
            message += "\n\nPoints retenus pour le client, et eux seuls :\n"
                + pointsRetenus.map { "- \($0)" }.joined(separator: "\n")
        }
        return Self.nettoyerMarkdown(try await pont.envoyer(message))
    }

    // MARK: - Lecture des réponses

    /// Extrait l'objet JSON d'une réponse.
    ///
    /// Claude répond parfois en encadrant le JSON d'une phrase ou d'un bloc de
    /// code, malgré la consigne. Plutôt que de faire échouer tout un compte
    /// rendu pour une politesse, on retrouve l'objet dans le texte.
    static func decoderQuestions(_ brut: String) throws -> [Question] {
        guard let json = extraireObjetJSON(brut) else {
            throw ErreurPont.reponseIllisible(brut)
        }
        do {
            return try JSONDecoder().decode(ListeQuestions.self, from: Data(json.utf8)).questions
        } catch {
            throw ErreurPont.reponseIllisible(brut)
        }
    }

    /// Retrouve le premier objet JSON équilibré du texte, en ignorant les
    /// accolades qui se trouvent à l'intérieur d'une chaîne.
    static func extraireObjetJSON(_ texte: String) -> String? {
        let c = Array(texte)
        guard let debut = c.firstIndex(of: "{") else { return nil }
        var profondeur = 0
        var dansChaine = false
        var echappe = false
        for i in debut..<c.count {
            let ch = c[i]
            if dansChaine {
                if echappe { echappe = false }
                else if ch == "\\" { echappe = true }
                else if ch == "\"" { dansChaine = false }
                continue
            }
            switch ch {
            case "\"": dansChaine = true
            case "{": profondeur += 1
            case "}":
                profondeur -= 1
                if profondeur == 0 { return String(c[debut...i]) }
            default: break
            }
        }
        return nil
    }

    /// Retire le bloc de code dont Claude entoure parfois un document, malgré
    /// la consigne.
    static func nettoyerMarkdown(_ texte: String) -> String {
        var t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        if let finPremiereLigne = t.firstIndex(of: "\n") {
            t = String(t[t.index(after: finPremiereLigne)...])
        }
        if let fin = t.range(of: "```", options: .backwards) {
            t = String(t[t.startIndex..<fin.lowerBound])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
