import Foundation
import AppKit
import NoyauCR
import Observation

/// Là où en est le compte rendu en cours de fabrication.
enum EtapeSession: Equatable {
    case preparation
    case analyse(String)
    case interrogation
    case redaction
    case resultat
    case filtrage
    case redactionEmail
    case emailPret
    case echec(String)
}

extension EtapeSession {
    /// Vrai quand l'outil travaille et qu'il n'y a rien à faire qu'attendre.
    var estUnTraitement: Bool {
        switch self {
        case .analyse, .redaction, .redactionEmail: true
        default: false
        }
    }
}

/// L'état d'un compte rendu, du collage du transcript aux documents produits.
///
/// Toute la logique vit dans `NoyauCR` ; cette classe ne fait que la relier à
/// l'écran et retenir ce que l'utilisateur a répondu.
@Observable
@MainActor
final class Session {

    // Préparation
    var transcript = ""
    var projet = ""
    var titreReunion = ""
    /// Quand la réunion a eu lieu. C'est une vraie date, choisie au calendrier
    /// et à l'horloge : saisie en toutes lettres, elle laissait passer des
    /// « Vendredi 14 août » alors que le 14 août 2026 était un vendredi — mais
    /// rien ne le vérifiait, et l'erreur partait telle quelle dans le compte
    /// rendu.
    var quandDate = Date()
    var format = "Visioconférence"
    var participants = ""
    var lieu = ""
    var perimetreRestreint = false
    var sujet = ""
    var entree: TypeEntree = .collage

    // Déroulé
    var etape: EtapeSession = .preparation
    var questions: [Question] = []
    var reponses: [String: String] = [:]
    var vagueAffichee = 1
    var tourDInterrogation = 1

    // Résultat
    var compteRendu = ""
    var cheminPDF: URL?
    var alerteForfait: String?

    // Email client
    var destinataire = ""
    var entrepriseClient = ""
    var questionsFiltrage: [Question] = []
    var pointsRetenus: Set<String> = []
    var emailClient = ""
    var cheminEmail: URL?

    /// Ce que le lexique vient d'apprendre, annoncé à l'écran.
    ///
    /// Le message partait dans `messageCapture`, qui ne s'affiche que dans
    /// l'atelier — or l'enrichissement a lieu **au moment précis** où l'on
    /// quitte cet écran pour transmettre ses réponses. L'annonce n'était donc
    /// jamais vue là où elle comptait. C'est pourtant le moment où l'outil
    /// tient sa promesse : ces termes ne seront plus jamais redemandés.
    struct AnnonceLexique: Equatable {
        var termes: [String]
        var arbitrages: [String]
    }
    var annonceLexique: AnnonceLexique?

    /// Où en est un traitement long, quand on sait le dire.
    ///
    /// `nil` quand aucun pourcentage n'a de sens — Claude ne dit jamais où il
    /// en est. Une barre qui avancerait au hasard vaudrait moins que pas de
    /// barre du tout.
    var avancement: Double?
    /// Ce que le traitement en cours a déjà produit, montré au fil de l'eau.
    var apercuEnCours = ""

    // Capture
    var enregistrementEnCours = false
    var secondesEnregistrees: TimeInterval = 0
    var messageCapture: String?

    /// Le fichier audio du dernier enregistrement, pour pouvoir le montrer.
    /// Sans cette information à l'écran, on voit un fichier apparaître sans
    /// savoir ce qu'il devient.
    var dernierEnregistrement: String?
    var urlDernierEnregistrement: URL?
    var etapeEchouee: EtapeEchouee?

    /// Le dossier retenu pour cette réunion, une fois qu'on y a écrit.
    var dossierRetenu: URL?

    /// Ce qui est demandé en plus pour le dossier en cours.
    var consignesDuDossier = ConsignesDossier()
    /// La consigne que Claude propose après une correction, en attente de
    /// validation : rien n'entre dans une charte sans un accord explicite.
    var consigneProposee: String?
    var deductionEnCours = false

    /// Où une consigne validée doit vivre.
    enum PorteeConsigne { case ceDossier, tousLesDossiers }

    var chaine: ChaineCR?
    let racine: URL

    /// La forme des documents produits — le PDF comme le Word. Elle vit dans
    /// le dossier de travail, pas dans le code : chacun a la sienne, et aucun
    /// nom de société n'est écrit en dur nulle part.
    var charte: Charte
    let capture: Capture
    let captureDouble: CaptureDoublePiste
    /// Le chronomètre d'un enregistrement en cours.
    var minuterie: Timer?
    /// Le déclenchement d'un enregistrement programmé.
    ///
    /// **Séparée du chronomètre**, et pas par élégance : les deux partageaient
    /// la même variable, si bien qu'armer pour une réunion puis enregistrer
    /// autre chose entre-temps annulait l'armement en silence — la réunion
    /// programmée n'aurait jamais été captée.
    var minuterieArmement: Timer?
    /// Accessible aux vues : elles y lisent la tenue choisie, et la bascule de
    /// l'en-tête y écrit.
    let reglages: Reglages

    init(reglages: Reglages = Reglages(), racine: URL? = nil) {
        self.reglages = reglages
        let racine = racine ?? reglages.dossierDeTravail
        self.racine = racine
        self.charte = Charte.charger(racine: racine)
        // Le dossier peut ne pas exister au tout premier lancement, ou avoir
        // été déplacé depuis : le créer ici évite que la première écriture
        // échoue en silence.
        try? FileManager.default.createDirectory(
            at: racine.appendingPathComponent("comptes-rendus"),
            withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: racine.appendingPathComponent("lexique"),
            withIntermediateDirectories: true)
        let enregistrements = racine.appendingPathComponent("enregistrements")
        self.capture = Capture(dossier: enregistrements)
        self.captureDouble = CaptureDoublePiste(dossier: enregistrements)
    }

    /// La date de la réunion telle qu'elle est écrite dans le compte rendu et
    /// transmise à Claude : « Lundi 17 août 2026, 14h30 ».
    var quand: String { Session.lisible(quandDate) }

    static func lisible(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM yyyy, HH'h'mm"
        return f.string(from: date).capitalizedPremiereLettre
    }

    // MARK: - Ce que l'écran a besoin de savoir

    var pretAAnalyser: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !projet.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Les questions du tour, rangées par coût de réponse (spécification § 3.4).
    var questionsOrdonnees: [Question] { ListeQuestions(questions: questions).ordonnees }

    var vagues: [Int] { Array(Set(questionsOrdonnees.map(\.vague))).sorted() }

    var questionsDeLaVague: [Question] {
        questionsOrdonnees.filter { $0.vague == vagueAffichee }
    }

    var nombreRepondu: Int {
        questions.count { reponses[$0.id]?.isEmpty == false }
    }

    /// A-t-on répondu à tout dans cette vague ? Sert à marquer les vagues
    /// terminées : sans ce repère, revenir en arrière obligeait à parcourir
    /// toutes les questions pour savoir s'il en restait.
    func vagueEstComplete(_ vague: Int) -> Bool {
        let dedans = questionsOrdonnees.filter { $0.vague == vague }
        return !dedans.isEmpty && dedans.allSatisfy { reponses[$0.id]?.isEmpty == false }
    }

    var libelleVague: String {
        switch vagueAffichee {
        case 1: "Un clic, sans réfléchir"
        case 2: "Un clic, après lecture de l'extrait"
        case 3: "Ces points demandent un arbitrage"
        default: "À écrire vous-même"
        }
    }

    // MARK: - Ce que les panneaux latéraux montrent

    struct Dossier: Sendable { var nom: String; var nombre: Int }
    struct CRAnterieur: Sendable {
        var titre: String
        var apercu: String
        var url: URL
        /// Le PDF s'il a été produit — c'est lui qu'on veut ouvrir le plus souvent.
        var pdf: URL?
    }

    var dossiers: [Dossier] = []
    var comptesRendusAnterieurs: [CRAnterieur] = []
    var lexiqueTotal = 0
    var lexiqueRetenu = 0
    var apercuLexique = ""

    var motsDuTranscript: Int {
        transcript.split(whereSeparator: \.isWhitespace).count
    }

    /// Relit ce qui est sur le disque. Appelé à l'ouverture et à chaque
    /// changement de dossier — c'est peu de fichiers, et une lecture fraîche
    /// vaut mieux qu'un cache qui ment.
    func rafraichirLeContexte() {
        consignesDuDossier = projet.isEmpty
            ? ConsignesDossier()
            : ConsignesDossier.charger(racine: racine, projet: projet)
        let racineCR = racine.appendingPathComponent("comptes-rendus")
        let noms = (try? FileManager.default.contentsOfDirectory(atPath: racineCR.path)) ?? []
        dossiers = noms
            .filter { !$0.hasPrefix(".") }
            .compactMap { nom in
                let nombre = Rangement.nombreDeComptesRendus(racine: racine, projet: nom)
                return Dossier(nom: nom, nombre: nombre)
            }
            .sorted { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }

        comptesRendusAnterieurs = reunionsDuDossier().prefix(3).compactMap { reunion in
            guard let cr = reunion.compteRendu else { return nil }
            let texte = (try? String(contentsOf: cr, encoding: .utf8)) ?? ""
            return CRAnterieur(titre: reunion.titre,
                               apercu: Session.apercu(de: texte),
                               url: cr,
                               pdf: reunion.pdf)
        }

        guard let lexique = try? Lexique.charger(depuis: racine
            .appendingPathComponent("lexique/lexique.json")) else { return }
        lexiqueTotal = lexique.entrees.count

        // La sélection compare chaque terme au transcript entier : 0,3 s pour
        // vingt-et-une entrées, mesuré, et le coût croît avec le lexique. Sur
        // le fil principal, elle figerait l'interface à chaque frappe.
        let texte = transcript
        Task.detached(priority: .userInitiated) {
            let retenues = texte.isEmpty ? [] : lexique.selectionner(pourTranscript: texte)
            let noms = (retenues.isEmpty ? lexique.entrees : retenues).prefix(3).map(\.terme)
            let apercu = noms.isEmpty
                ? "Le lexique est vide : il se remplira de vos réponses."
                : noms.joined(separator: ", ") + "… ne seront plus jamais redemandés."
            await MainActor.run { [weak self] in
                self?.lexiqueRetenu = retenues.count
                self?.apercuLexique = apercu
            }
        }
    }

    private func reunionsDuDossier() -> [Rangement.Reunion] {
        guard !projet.isEmpty else { return [] }
        return Rangement.reunions(racine: racine, projet: projet)
    }

    static func apercu(de texte: String) -> String {
        for ligne in texte.components(separatedBy: .newlines) {
            if ligne.hasPrefix("| **Objet**") {
                let bouts = ligne.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if bouts.count >= 2 { return String(bouts[1].prefix(90)) }
            }
            if ligne.hasPrefix("## ") { return String(ligne.dropFirst(3).prefix(90)) }
        }
        return "—"
    }

    func ouvrir(_ cr: CRAnterieur) {
        NSWorkspace.shared.open(cr.pdf ?? cr.url)
    }

    /// Écrit un document Word d'un compte rendu déjà rangé.
    ///
    /// L'export ne vivait que sur l'écran du compte rendu qu'on vient de
    /// produire, puis dans la fenêtre de recherche. Or c'est ici qu'on regarde
    /// quand on veut envoyer un compte rendu ancien : le panneau du dossier le
    /// montre déjà, il doit aussi savoir le sortir.
    func exporterEnWord(_ cr: CRAnterieur) {
        guard let texte = try? String(contentsOf: cr.url, encoding: .utf8),
              !texte.isEmpty else {
            messageCapture = "Ce compte rendu est illisible : il n'y a rien à exporter."
            return
        }
        let dossier = cr.url.deletingLastPathComponent()
        let nom = Rangement.nomDeFichier(projet: projet, objet: cr.titre,
                                         date: Rangement.dateDe(dossier: dossier.lastPathComponent)
                                            ?? Date())
        let url = dossier.appendingPathComponent(
            "\(nom).\(Export.extensionTraitementDeTexte)")
        do {
            try Export.versTraitementDeTexte(
                texte, vers: url, charte: charte,
                surTitre: reglages.identite.societe,
                enteteWord: enteteWord(titre: cr.titre))
            NSWorkspace.shared.activateFileViewerSelecting([url])
            messageCapture = "Le document Word « \(url.lastPathComponent) » est prêt : "
                + "le Finder vient de s'ouvrir dessus."
        } catch {
            messageCapture = "Le document Word n'a pas pu être écrit. "
                + "\(error.localizedDescription)"
        }
    }

    /// Le bandeau de tête d'un document Word.
    func enteteWord(titre: String) -> RenduWord.Entete {
        RenduWord.Entete(titre: "Compte rendu de réunion — \(projet)",
                         sousTitre: titre, projet: projet, date: quand)
    }

    /// Enregistre la charte et refait le contexte : les prochains documents
    /// la prennent aussitôt, sans qu'il faille relancer l'application.
    func enregistrerLaCharte(_ nouvelle: Charte) {
        charte = nouvelle
        do {
            try nouvelle.enregistrer(racine: racine)
        } catch {
            messageCapture = "La charte n'a pas pu être enregistrée. "
                + "\(error.localizedDescription)"
        }
    }

    func montrerLeDossier() {
        guard !projet.isEmpty else { return }
        let dossier = racine.appendingPathComponent("comptes-rendus/\(projet)")
        NSWorkspace.shared.activateFileViewerSelecting([dossier])
    }

    var racineDuProjet: URL { racine }

    func choisirDossier(_ nom: String) {
        projet = nom
        rafraichirLeContexte()
    }

    /// Repart de zéro sans perdre le dossier en cours : on enchaîne le plus
    /// souvent deux comptes rendus du même client.
    /// L'étape quittée pour revenir à l'accueil, s'il y en a une.
    ///
    /// Revenir à l'accueil ne devait rien détruire : c'est ce qui permet
    /// d'aller consulter un dossier ou le lexique en pleine interrogation, puis
    /// de reprendre là où l'on en était.
    var etapeAvantAccueil: EtapeSession?

    /// Peut-on quitter cette étape pour l'accueil ?
    ///
    /// Pas pendant un traitement : Claude est en train de lire ou d'écrire, et
    /// l'interrompre à mi-course ne produirait rien d'utilisable.
    var peutRevenirALAccueil: Bool {
        switch etape {
        case .preparation, .analyse, .redaction, .redactionEmail: false
        default: true
        }
    }

    func revenirALAccueil() {
        guard peutRevenirALAccueil else { return }
        etapeAvantAccueil = etape
        etape = .preparation
        rafraichirLeContexte()
    }

    /// Repart où l'on en était avant d'être passé par l'accueil.
    func reprendre() {
        guard let precedente = etapeAvantAccueil else { return }
        etapeAvantAccueil = nil
        etape = precedente
    }

    /// Y a-t-il un travail que « Nouveau compte rendu » ferait disparaître ?
    ///
    /// Un compte rendu produit mais pas encore enregistré n'existe qu'en
    /// mémoire : le perdre imposerait de tout recommencer, questions comprises.
    var travailNonEnregistre: Bool {
        !compteRendu.isEmpty && cheminPDF == nil
    }

    /// Comment nommer l'étape interrompue, pour proposer d'y revenir.
    var libelleEtapeInterrompue: String? {
        switch etapeAvantAccueil {
        case .interrogation: "Reprendre les questions"
        case .resultat: "Revenir au compte rendu"
        case .filtrage: "Reprendre le filtrage"
        case .emailPret: "Revenir à l'email"
        case .echec: nil
        default: nil
        }
    }

    func recommencer() {
        etape = .preparation
        transcript = ""
        titreReunion = ""
        compteRendu = ""
        emailClient = ""
        questions = []
        reponses = [:]
        questionsFiltrage = []
        pointsRetenus = []
        cheminPDF = nil
        cheminEmail = nil
        messageCapture = nil
        tourDInterrogation = 1
        etapeAvantAccueil = nil
        dossierRetenu = nil
        annonceLexique = nil
        avancement = nil
        apercuEnCours = ""
        if let ancienne = chaine {
            chaine = nil
            Task { await ancienne.terminer() }
        }
        rafraichirLeContexte()
    }

    // MARK: - Le déroulé

    func lancerAnalyse() async {
        apercuEnCours = ""
        etape = .analyse("Lecture du transcript et du lexique…")
        do {
            let lexique = try Lexique.charger(depuis: racine
                .appendingPathComponent("lexique/lexique.json"))
            // Hors du fil principal : la sélection compare chaque terme au
            // transcript entier, et l'écran « analyse en cours » n'aurait pas
            // le temps de se dessiner avant le gel.
            let texteDuTranscript = transcript
            let retenues = await Task.detached(priority: .userInitiated) {
                lexique.selectionner(pourTranscript: texteDuTranscript)
            }.value

            etape = .analyse("\(retenues.count) termes du lexique retenus. "
                             + "Claude lit la réunion et prépare ses questions…")

            let contexte = ContexteReunion(
                titre: titreReunion.isEmpty ? "Réunion \(projet)" : titreReunion,
                quand: quand, format: format,
                lieu: lieu.isEmpty ? nil : lieu,
                participants: participants
                    .components(separatedBy: CharacterSet(charactersIn: ",·"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
                projet: projet,
                perimetre: perimetreRestreint && !sujet.isEmpty
                    ? .sujet(sujet) : .touteLaReunion,
                entree: entree)

            // Le dialogue précédent, s'il en reste un, tient encore un
            // processus claude ouvert sur son entrée : sans cet arrêt, chaque
            // compte rendu en laissait un vivant jusqu'à la fermeture.
            await self.chaine?.terminer()
            let chaine = ChaineCR(contexte: contexte, config: reglages.configClaude,
                                  identite: reglages.identite,
                                  consignesDossier: consignesDuDossier.texte)
            self.chaine = chaine
            // Ce que Claude écrit, montré au fil de l'eau : c'est la seule
            // façon de combler une attente dont on ne peut pas dire le
            // pourcentage.
            await chaine.surveillerLeTexte { [weak self] texte in
                Task { @MainActor in self?.apercuEnCours = texte }
            }
            await chaine.surveiller { [weak self] limite in
                Task { @MainActor in self?.noterLimite(limite) }
            }

            etapeEchouee = .analyse
            questions = try await chaine.analyser(
                transcript: transcript,
                matiere: entree == .notes ? .notes : .transcript,
                lexique: retenues,
                comptesRendusAnterieurs: comptesRendusDuDossier())

            if questions.isEmpty {
                await rediger()
            } else {
                vagueAffichee = vagues.first ?? 1
                etape = .interrogation
            }
        } catch {
            etapeEchouee = .analyse
            etape = .echec(error.localizedDescription)
        }
    }

    /// Transmet les réponses du tour. Claude peut en poser d'autres : c'est
    /// cette boucle qui met en œuvre « autant de questions que nécessaire ».
    func transmettreReponses() async {
        guard let chaine else { return }
        // Avant tout envoi : ce qui a été appris ne doit pas dépendre de ce qui
        // sera produit. Une correction reste vraie même si le compte rendu est
        // abandonné en cours de route (spécification § 8.2).
        enrichirLeLexique()
        apercuEnCours = ""
        etape = .analyse("Claude prend connaissance de vos réponses…")
        let lot = questions.map { Reponse(id: $0.id, reponse: reponses[$0.id]) }
        do {
            let suite = try await chaine.repondre(lot)
            if suite.isEmpty {
                await rediger()
            } else {
                questions = suite
                reponses = [:]
                tourDInterrogation += 1
                vagueAffichee = vagues.first ?? 1
                etape = .interrogation
            }
        } catch {
            etapeEchouee = .reponses
            etape = .echec(error.localizedDescription)
        }
    }

    /// Passe outre les questions restantes. Les points sans réponse seront
    /// signalés dans le compte rendu, jamais tranchés à la place de l'utilisateur.
    func redigerSansAttendre() async {
        await transmettreReponses()
    }

    /// Ce que vos réponses ont appris, écrit dans le lexique.
    ///
    /// **Ce chaînon manquait entièrement jusqu'au 19/08/2026.** Le champ
    /// `enrichit_lexique` était calculé par Claude, transmis, puis ignoré : le
    /// lexique ne grandissait jamais, et la promesse de l'outil — le dixième
    /// compte rendu d'un dossier coûte moins que le premier — ne se réalisait
    /// pas.
    ///
    /// Rien n'est créé sans réponse de l'utilisateur : c'est sa réponse qui donne le
    /// terme, Claude ne fournit que la faute rencontrée, la catégorie et la
    /// note tirée du transcript.
    func enrichirLeLexique() {
        let url = racine.appendingPathComponent("lexique/lexique.json")
        // Un fichier présent mais illisible ne doit jamais être écrasé par un
        // lexique vide : des mois de termes appris disparaîtraient.
        if let sauve = Lexique.mettreDeCote(url) {
            messageCapture = "⚠️ Le lexique était illisible. Il a été mis de côté sous "
                + "« \(sauve) » et un lexique neuf a été créé. Rien n'est effacé."
        }
        // Relu à l'instant plutôt que gardé en mémoire : la fenêtre du lexique
        // peut être ouverte au même moment, et travailler sur une copie plus
        // ancienne écraserait ce qu'on vient d'apprendre.
        var lexique = (try? Lexique.charger(depuis: url)) ?? Lexique()
        var appris: [String] = []
        var aArbitrer: [String] = []

        for question in questions where question.enrichitLexique {
            guard let amorce = question.lexique,
                  let terme = Session.termeRetenu(reponses[question.id]) else { continue }

            // Un terme très proche d'un autre déjà connu n'est pas fusionné
            // d'office : « Menuiseries Vidal » et « MenuiserieVidal » peuvent être la même
            // entreprise ou deux clients différents, et vous seul le savez.
            if let proche = lexique.entreeProche(de: terme) {
                aArbitrer.append("« \(terme) » ressemble à « \(proche.terme) »")
            }
            if lexique.integrer(amorce.entree(pourTerme: terme)) {
                appris.append(terme)
            }
        }

        guard !appris.isEmpty || !aArbitrer.isEmpty else { return }
        try? lexique.enregistrer(vers: url)
        rafraichirLeContexte()

        // Une annonce à part, visible sur n'importe quel écran : celui qui
        // transmet ses réponses ne voit plus l'atelier.
        annonceLexique = AnnonceLexique(termes: appris, arbitrages: aArbitrer)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            await MainActor.run { self?.annonceLexique = nil }
        }
    }

    /// La réponse est-elle un terme à retenir, ou autre chose ?
    ///
    /// Un « Oui » n'est pas un nom d'entreprise, et une explication de trois
    /// lignes non plus : les faire entrer dans le lexique le remplirait de
    /// bruit, et ce bruit repartirait dans chaque analyse.
    static func termeRetenu(_ reponse: String?) -> String? {
        guard let brut = reponse?.trimmingCharacters(in: .whitespacesAndNewlines),
              !brut.isEmpty, brut.count <= 60 else { return nil }
        let sansAccent = Lexique.normaliser(brut)
        guard !["oui", "non", "je ne sais pas", "aucune idee"].contains(sansAccent) else {
            return nil
        }
        // Une réponse à choix multiple porte plusieurs valeurs : aucune n'est
        // « le » terme.
        guard !brut.contains(" · ") else { return nil }
        return brut
    }

    private func rediger() async {
        guard let chaine else { return }
        apercuEnCours = ""
        etape = .redaction
        do {
            compteRendu = try await chaine.rediger()
            etapeEchouee = nil
            etape = .resultat
        } catch {
            etapeEchouee = .redaction
            etape = .echec(error.localizedDescription)
        }
    }

    // MARK: - L'email client

    var pretAFiltrer: Bool {
        !destinataire.trimmingCharacters(in: .whitespaces).isEmpty
            && !entrepriseClient.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Demande à Claude ce qui peut sortir vers le client. C'est la huitième
    /// famille de questions, et elle n'intervient qu'ici — elle n'a pas de sens
    /// tant que le compte rendu interne n'est pas écrit.
    func demanderFiltrage() async {
        guard let chaine else { return }
        apercuEnCours = ""
        etape = .analyse("Claude relit le compte rendu et propose ce qui peut sortir…")
        do {
            questionsFiltrage = try await chaine.proposerFiltrage()
            // Tout est proposé coché sauf ce que Claude signale comme interne :
            // c'est sa proposition, l'utilisateur l'ajuste.
            pointsRetenus = Set(questionsFiltrage
                .flatMap { $0.options ?? [] }
                .filter { !$0.localizedCaseInsensitiveContains("— interne") })
            etape = .filtrage
        } catch {
            etapeEchouee = .filtrage
            etape = .echec(error.localizedDescription)
        }
    }

    func redigerEmail() async {
        guard let chaine else { return }
        apercuEnCours = ""
        etape = .redactionEmail
        do {
            emailClient = try await chaine.redigerEmail(
                destinataire: destinataire, entreprise: entrepriseClient,
                pointsRetenus: Array(pointsRetenus).sorted())
            etape = .emailPret
        } catch {
            etapeEchouee = .email
            etape = .echec(error.localizedDescription)
        }
    }

    /// L'email est écrit sur disque, jamais envoyé : c'est vous qui envoyez.
    func enregistrerEmail() {
        let dossier = dossierDeLaReunion
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let url = Rangement.chemin(.email, dans: dossier)
        do {
            try emailClient.write(to: url, atomically: true, encoding: .utf8)
            cheminEmail = url
        } catch {
            messageCapture = "⚠️ L'email n'a pas pu être enregistré. "
                + "\(error.localizedDescription) Copiez-le avant de fermer."
        }
    }

    // MARK: - Les documents

    func enregistrer() {
        let dossier = dossierDeLaReunion
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let fabrication = Rangement.dossierFabrication(dans: dossier)
        try? FileManager.default.createDirectory(at: fabrication, withIntermediateDirectories: true)

        // Une écriture qui échoue en silence est le pire des cas : l'écran
        // annoncerait « rangé dans… » alors que le compte rendu n'existe que
        // dans la mémoire de l'application, et disparaîtrait à la fermeture.
        do {
            try compteRendu.write(to: Rangement.chemin(.compteRendu, dans: dossier),
                                  atomically: true, encoding: .utf8)
        } catch {
            messageCapture = "⚠️ Le compte rendu n'a PAS pu être enregistré dans "
                + "\(dossier.lastPathComponent). \(error.localizedDescription) "
                + "Copiez-le avant de fermer l'application."
            return
        }

        // Le transcript part avec le compte rendu : sans lui, on ne peut plus
        // rejouer la chaîne après avoir modifié un prompt, ni vérifier d'où
        // vient une phrase six mois plus tard (spécification § 1.3 et § 9).
        if (try? transcript.write(to: Rangement.chemin(.transcript, dans: dossier),
                                  atomically: true, encoding: .utf8)) == nil {
            messageCapture = "Le compte rendu est enregistré, mais pas le transcript. "
                + "Vous ne pourrez pas rejouer cette réunion plus tard."
        }

        let entete = RenduPDF.Entete(
            titre: "Compte rendu de réunion — \(projet)",
            sousTitre: titreReunion.isEmpty ? "Compte rendu interne" : titreReunion,
            projet: projet, date: quand)
        // Le HTML dont le PDF est tiré va dans « Fabrication » : il sert à
        // refaire le PDF, jamais à être ouvert à la main.
        do {
            cheminPDF = try RenduPDF(charte: charte,
                                     surTitre: reglages.identite.societe).ecrire(
                markdown: compteRendu, entete: entete,
                vers: Rangement.chemin(.pdf, dans: dossier),
                sourceHTML: fabrication.appendingPathComponent("compte-rendu.html"))
        } catch {
            // Le compte rendu est écrit, lui : le PDF n'est qu'une mise en
            // forme. Mais son absence doit être dite, sinon on cherche un
            // bouton « Ouvrir le PDF » qui n'apparaît jamais.
            cheminPDF = nil
            messageCapture = "Le compte rendu est enregistré, mais le PDF n'a pas pu être "
                + "produit. \(error.localizedDescription)"
        }

        rangerLEnregistrement(dans: fabrication)
        rafraichirLeContexte()
    }

    /// Déplace l'enregistrement dans le dossier de la réunion, et le compresse.
    ///
    /// L'audio était écrit dans un dossier commun à tous les projets, sous un
    /// nom qui ne disait ni le client ni le sujet : rien ne permettait de
    /// savoir à quel compte rendu appartenait `reunion-2026-08-19-1524-moi.caf`.
    ///
    /// La compression n'a lieu qu'ici, c'est-à-dire une fois le transcript relu
    /// et le compte rendu produit : tant que le texte n'est pas jugé bon, on
    /// peut avoir à retranscrire, et la reconnaissance travaille mieux sur le
    /// son d'origine.
    private func rangerLEnregistrement(dans fabrication: URL) {
        let pistes = urlsDesEnregistrements
        guard !pistes.isEmpty else { return }
        guard reglages.conserverLesEnregistrements else {
            for piste in pistes { try? FileManager.default.removeItem(at: piste) }
            urlDernierEnregistrement = nil
            dernierEnregistrement = nil
            return
        }

        let enDeuxPistes = entree == .doublePiste && pistes.count == 2
        Task { [pistes, fabrication, enDeuxPistes] in
            var deplacees: [URL] = []
            for piste in pistes {
                let cible = fabrication.appendingPathComponent(piste.lastPathComponent)
                try? FileManager.default.removeItem(at: cible)
                guard (try? FileManager.default.moveItem(at: piste, to: cible)) != nil else {
                    continue
                }
                deplacees.append(cible)
            }
            guard !deplacees.isEmpty else { return }

            let avant = deplacees.reduce(0) { total, url in
                total + ((try? FileManager.default
                    .attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
            }
            var produit: URL?
            var apres = 0

            if enDeuxPistes, deplacees.count == 2 {
                // Un seul fichier stéréo, vous à gauche et les autres à droite,
                // écrit directement depuis le brut : compresser chaque piste
                // avant de les réunir ferait deux encodages là où un suffit.
                let cible = fabrication.appendingPathComponent("audio.m4a")
                if let bilan = try? FusionAudio.unifier(
                    moi: deplacees[0], lesAutres: deplacees[1], vers: cible,
                    progression: { ou in
                        Task { @MainActor [weak self] in
                            self?.avancement = ou
                            self?.messageCapture = "Les deux pistes sont réunies en un "
                                + "seul fichier — \(Int((ou * 100).rounded())) %."
                        }
                    }) {
                    produit = bilan.url
                    apres = bilan.taille
                    for piste in deplacees { try? FileManager.default.removeItem(at: piste) }
                }
            } else if let bilan = try? await CompressionAudio.compresser(deplacees[0]) {
                produit = bilan.url
                apres = bilan.apres
            }

            await MainActor.run {
                self.avancement = nil
                self.urlDernierEnregistrement = produit
                self.dernierEnregistrement = produit == nil
                    ? nil : "rangé avec le compte rendu"
                guard let produit, avant > 0 else { return }
                let quoi = enDeuxPistes
                    ? "Les deux pistes ont été réunies en un seul fichier, vous à gauche "
                      + "et les autres à droite : "
                    : "Enregistrement rangé avec le compte rendu et compressé : "
                self.messageCapture = quoi
                    + "\(CompressionAudio.gain(avant: avant, apres: apres)). "
                    + "Il est dans « \(produit.deletingLastPathComponent().lastPathComponent) »."
            }
        }
    }

    /// Les fichiers audio de la dernière capture — une piste, ou deux en visio.
    private var urlsDesEnregistrements: [URL] {
        guard let premiere = urlDernierEnregistrement,
              FileManager.default.fileExists(atPath: premiere.path) else { return [] }
        guard entree == .doublePiste else { return [premiere] }
        let autre = premiere.deletingLastPathComponent()
            .appendingPathComponent(premiere.lastPathComponent
                .replacingOccurrences(of: "-moi.caf", with: "-les-autres.caf"))
        return FileManager.default.fileExists(atPath: autre.path) ? [premiere, autre] : [premiere]
    }

    /// Le dossier de cette réunion : sa date, puis son objet.
    var dossierDeLaReunion: URL {
        // Choisi une fois, puis conservé : le recalculer à chaque écriture
        // ferait glisser l'email dans un autre dossier que le compte rendu.
        if let dejaChoisi = dossierRetenu { return dejaChoisi }
        let libre = Rangement.dossierLibre(racine: racine, projet: projet,
                                           date: quandDate, objet: titreReunion)
        dossierRetenu = libre
        return libre
    }

    /// Combien de comptes rendus antérieurs Claude relit, et jusqu'à quel poids.
    ///
    /// **Ils étaient envoyés TOUS, sans limite.** À la soixantième réunion d'un
    /// client, cela aurait fait près d'un mégaoctet à chaque analyse — bien
    /// au-delà de ce qu'un modèle accepte, et coûteux longtemps avant. Le
    /// panneau de droite n'en montrait que trois : l'écart entre ce qu'on
    /// voyait et ce qui partait était invisible.
    ///
    /// Trois suffisent à donner la continuité d'un dossier et à repérer une
    /// contradiction. Au-delà, on relit une histoire, pas un contexte.
    static let comptesRendusRelus = 3
    /// Un plafond en octets, parce que trois comptes rendus très longs pèsent
    /// plus que dix courts.
    static let poidsMaximalRelu = 120_000

    private func comptesRendusDuDossier() -> [String] {
        var retenus: [String] = []
        var poids = 0
        for reunion in reunionsDuDossier().prefix(Session.comptesRendusRelus) {
            guard let url = reunion.compteRendu,
                  let texte = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let taille = texte.utf8.count
            guard poids + taille <= Session.poidsMaximalRelu else { break }
            retenus.append(texte)
            poids += taille
        }
        // Du plus ancien au plus récent : la chronologie aide à suivre un
        // dossier.
        return retenus.reversed()
    }

    private func noterLimite(_ limite: InfoLimite) {
        guard limite.statut != "allowed" else { alerteForfait = nil; return }
        var texte = "La limite d'utilisation du forfait est atteinte."
        if let quand = limite.reinitialisationLe {
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.dateFormat = "HH'h'mm"
            texte += " Elle se réinitialise à \(f.string(from: quand))."
        }
        alerteForfait = texte
    }
}

extension String {
    var capitalizedPremiereLettre: String {
        isEmpty ? self : prefix(1).uppercased() + dropFirst()
    }
}
