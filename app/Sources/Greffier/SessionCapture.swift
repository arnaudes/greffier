import AVFoundation
import AppKit
import Foundation
import NoyauCR

/// Tout ce qui touche à la capture d'une réunion : enregistrer, arrêter,
/// transcrire, ranger l'audio.
///
/// Extrait de `Session` le 20/08/2026, quand ce fichier a dépassé mille deux
/// cents lignes. Ce bloc est celui qui s'isole le mieux : il ne touche ni aux
/// questions, ni aux documents produits — seulement au son et au texte qu'il
/// devient.
@MainActor
extension Session {

    // MARK: - Enregistrer une réunion


    /// Vrai quand le message en cours parle d'une autorisation refusée : c'est
    /// le seul cas où proposer d'ouvrir les réglages a du sens.
    var autorisationManquante: Bool {
        guard let m = messageCapture else { return false }
        return m.contains("n'a pas accès") || m.contains("n'a pas l'autorisation")
            || m.contains("dictée est désactivée")
    }

    func ouvrirLesReglagesSysteme() {
        let cible = (messageCapture?.contains("dictée") ?? false)
            ? "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        if let url = URL(string: cible) { NSWorkspace.shared.open(url) }
    }

    /// macOS ne rafraîchit pas une autorisation pour un processus déjà lancé.
    /// Plutôt que de le dire et de laisser faire, on le fait.
    func relancerLApplication() {
        let chemin = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: chemin, configuration: config) { _, _ in
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }

    func montrerLEnregistrement() {
        guard let url = urlDernierEnregistrement else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Ce que le menu affichera en clair — « Enregistrement en cours depuis
    /// 12 min » — plutôt qu'une pastille rouge, refusée à la conception.
    var depuisCombienDeTemps: String {
        Capture.lisible(secondesEnregistrees)
    }

    /// L'enregistrement suit le mode choisi dans les réglages : en
    /// visioconférence, deux pistes séparées ; sinon, le micro seul.
    /// Compresse d'elle-même les orphelins anciens.
    ///
    /// **Seul automatisme de toute l'application**, et il ne doit son existence
    /// qu'à une chose : il ne détruit rien. Le fichier reste transcriptible, il
    /// cesse seulement de peser vingt-cinq fois son poids — 875 Mo devenus
    /// 55 Mo sur la mesure du 19/08/2026.
    ///
    /// Les essais en sont exclus : occuper le processeur pour gagner quelques
    /// mégaoctets sur des fichiers destinés à être effacés n'aurait pas de sens.
    func compresserLesVieuxOrphelins() {
        let aFaire = Enregistrements.aCompresser(racine: racine)
        guard !aFaire.isEmpty else { return }
        Task.detached(priority: .background) {
            for orphelin in aFaire {
                _ = try? await CompressionAudio.compresser(orphelin.url)
            }
        }
    }

    /// Transcrit un enregistrement resté sans compte rendu.
    ///
    /// C'est l'action qui compte le plus dans la fenêtre des enregistrements :
    /// un orphelin long n'est pas un déchet, c'est une réunion qu'on a oublié
    /// de traiter. Le 19/08/2026, une visioconférence de trente minutes a été
    /// récupérée ainsi, depuis son seul audio.
    ///
    /// En visioconférence, la piste jumelle est retrouvée par son nom : les
    /// deux ont été écrites ensemble, et les séparer perdrait l'attribution.
    func transcrireUnOrphelin(_ url: URL) async {
        let moteur = Transcription()
        let jumelle = pisteJumelle(de: url)
        let duree = Capture.duree(de: url) ?? 0
        let combien = Capture.lisible(duree)

        do {
            if let jumelle {
                entree = .doublePiste
                messageCapture = "Transcription de la première piste (\(combien))…"
                let moi = try await moteur.segmenter(url) { ou in
                    Task { @MainActor [weak self] in
                        self?.avancement = ou.fraction / 2
                        self?.messageCapture = "Première piste — \(ou.pourcentage) %, "
                            + "\(ou.mots) mots."
                    }
                }
                messageCapture = "Transcription de la seconde piste…"
                let autres = try await moteur.segmenter(jumelle) { ou in
                    Task { @MainActor [weak self] in
                        self?.avancement = 0.5 + ou.fraction / 2
                        self?.messageCapture = "Seconde piste — \(ou.pourcentage) %, "
                            + "\(ou.mots) mots."
                    }
                }
                let nomMoi = reglages.identite.nom.isEmpty ? "Moi" : reglages.identite.nom
                transcript = FusionPistes.enTete(
                    reunion: titreReunion.isEmpty ? "Réunion à traiter" : titreReunion,
                    quand: quand, nomMoi: nomMoi)
                    + FusionPistes.fusionner(moi: moi, lesAutres: autres, nomMoi: nomMoi)
            } else {
                entree = .microSeul
                messageCapture = "Transcription de l'enregistrement (\(combien))…"
                transcript = try await moteur.transcrire(url) { ou in
                    Task { @MainActor [weak self] in
                        self?.avancement = ou.fraction
                        self?.messageCapture = "Transcription — \(ou.pourcentage) %, "
                            + "\(ou.mots) mots reconnus."
                    }
                }
            }
            avancement = nil
            urlDernierEnregistrement = url
            dernierEnregistrement = url.lastPathComponent
            // La date de l'enregistrement vaut mieux que celle du jour : la
            // réunion a eu lieu quand elle a été captée.
            if let quandFichier = (try? url.resourceValues(forKeys: [.creationDateKey]))?
                .creationDate {
                quandDate = quandFichier
            }
            messageCapture = Transcription.alerteSiTropCourt(transcript, duree: duree)
                ?? "Transcription terminée. Choisissez le dossier, puis analysez."
            rafraichirLeContexte()
        } catch {
            avancement = nil
            messageCapture = error.localizedDescription
                + " L'enregistrement est conservé : rien n'est perdu."
        }
    }

    /// L'autre piste d'une visioconférence, si elle existe.
    private func pisteJumelle(de url: URL) -> URL? {
        let nom = url.lastPathComponent
        let autreNom: String
        if nom.contains("-moi.") {
            autreNom = nom.replacingOccurrences(of: "-moi.", with: "-les-autres.")
        } else if nom.contains("-les-autres.") {
            autreNom = nom.replacingOccurrences(of: "-les-autres.", with: "-moi.")
        } else {
            return nil
        }
        let autre = url.deletingLastPathComponent().appendingPathComponent(autreNom)
        return FileManager.default.fileExists(atPath: autre.path) ? autre : nil
    }

    /// Enregistrer sans réunion au calendrier — depuis la barre de menus, à
    /// l'instant où l'on en a besoin.
    ///
    /// Toutes les réunions ne sont pas dans le calendrier : un appel qui
    /// s'improvise, un point qui s'invite, un client qui rappelle. Il fallait
    /// jusqu'ici ouvrir la fenêtre et régler l'origine avant de pouvoir lancer
    /// quoi que ce soit — le temps de le faire, la réunion avait commencé.
    ///
    /// L'heure de la réunion est celle du démarrage, et le dossier reste à
    /// désigner : il se demandera au moment de rédiger, jamais pendant.
    func enregistrerSansReunion(_ origine: TypeEntree) async {
        entree = origine
        quandDate = Date()
        await demarrerEnregistrement()
    }

    func demarrerEnregistrement() async {
        let nom = (projet.isEmpty ? "reunion" : projet) + "-" + Session.horodatageFichier()
        do {
            if entree == .doublePiste {
                let droits = await CaptureDoublePiste.autoriser()
                guard droits.micro else {
                    messageCapture = CaptureDoublePiste.Erreur.microRefuse.errorDescription; return
                }
                guard droits.ecran else {
                    messageCapture = CaptureDoublePiste.Erreur.ecranRefuse.errorDescription; return
                }
                // Une piste qui meurt en cours de route doit se dire tout de
                // suite : l'enregistrement paraîtrait normal jusqu'à la
                // transcription, où il ne resterait qu'une voix.
                captureDouble.surPerteDuSysteme = { [weak self] message in
                    Task { @MainActor in self?.messageCapture = "⚠️ " + message }
                }
                try await captureDouble.demarrer(nom: nom)
            } else {
                guard await Capture.autoriserLeMicro() else {
                    messageCapture = Capture.Erreur.microRefuse.errorDescription; return
                }
                try capture.demarrer(nom: nom)
            }
            enregistrementEnCours = true
            secondesEnregistrees = 0
            messageCapture = nil
            minuterie = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    secondesEnregistrees = (entree == .doublePiste
                                            ? captureDouble.depuis : capture.depuis) ?? 0
                }
            }
        } catch {
            messageCapture = error.localizedDescription
        }
    }

    /// Arrête, puis transcrit — **jamais pendant la réunion** : transcrire en
    /// direct chaufferait le processeur et viderait la batterie (chantier § 4.6).
    func arreterEtTranscrire() async {
        minuterie?.invalidate(); minuterie = nil
        enregistrementEnCours = false

        guard await Transcription.autoriser() else {
            messageCapture = Transcription.Erreur.autorisationRefusee.errorDescription
            return
        }

        if entree == .doublePiste {
            await transcrireLesDeuxPistes()
            return
        }

        let url: URL
        do { url = try capture.arreter() } catch {
            messageCapture = error.localizedDescription; return
        }

        urlDernierEnregistrement = url
        dernierEnregistrement = url.lastPathComponent
        let duree = Capture.duree(de: url).map(Capture.lisible) ?? "durée inconnue"
        messageCapture = "Enregistrement de \(duree) terminé. Transcription en cours…"
        do {
            let texte = try await Transcription().transcrire(url) { ou in
                Task { @MainActor [weak self] in
                    self?.avancement = ou.fraction
                    self?.messageCapture = "Transcription — \(ou.pourcentage) %, "
                        + "\(ou.mots) mots reconnus."
                }
            }
            avancement = nil
            transcript = texte
            entree = .microSeul
            if let alerte = Transcription.alerteSiTropCourt(
                texte, duree: Capture.duree(de: url) ?? 0) {
                messageCapture = alerte
                rafraichirLeContexte()
                return
            }
            messageCapture = "Transcription terminée. L'enregistrement est conservé dans "
                + "enregistrements/\(url.lastPathComponent)."
        } catch {
            messageCapture = error.localizedDescription
                + " L'enregistrement, lui, est conservé : rien n'est perdu."
        }
    }

    /// Transcrit les deux pistes séparément, puis les entrelace. C'est ici que
    /// l'attribution devient exacte : aucun modèle ne devine qui parle, la
    /// provenance du son suffit à le dire.
    private func transcrireLesDeuxPistes() async {
        let pistes: CaptureDoublePiste.Pistes
        do { pistes = try await captureDouble.arreter() } catch {
            messageCapture = error.localizedDescription; return
        }
        urlDernierEnregistrement = pistes.moi
        dernierEnregistrement = pistes.moi.lastPathComponent
            + " et " + pistes.lesAutres.lastPathComponent

        let moteur = Transcription()
        do {
            let duree = Capture.duree(de: pistes.moi) ?? 0
            let combien = Capture.lisible(duree)

            messageCapture = "Transcription de votre piste (\(combien))…"
            let moi = try await moteur.segmenter(pistes.moi) { ou in
                Task { @MainActor [weak self] in
                    // Deux pistes à transcrire : la première occupe la première
                    // moitié de la barre, la seconde l'autre. Sans cela, la
                    // progression retomberait à zéro au milieu du travail.
                    self?.avancement = ou.fraction / 2
                    self?.messageCapture = "Votre piste — \(ou.pourcentage) %, "
                        + "\(ou.mots) mots."
                }
            }
            messageCapture = "Transcription de la piste des autres participants…"
            let autres = try await moteur.segmenter(pistes.lesAutres) { ou in
                Task { @MainActor [weak self] in
                    self?.avancement = 0.5 + ou.fraction / 2
                    self?.messageCapture = "Piste des autres participants — "
                        + "\(ou.pourcentage) %, \(ou.mots) mots."
                }
            }
            avancement = nil

            let nomsDesAutres = participants
                .components(separatedBy: CharacterSet(charactersIn: ",·"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !reglages.identite.estMoi($0) }

            let nomMoi = reglages.identite.nom.isEmpty ? "Moi" : reglages.identite.nom
            transcript = FusionPistes.enTete(
                reunion: titreReunion.isEmpty ? "Réunion \(projet)" : titreReunion,
                quand: quand, nomMoi: nomMoi)
                + FusionPistes.fusionner(
                    moi: moi, lesAutres: autres, nomMoi: nomMoi,
                    nomAutres: nomsDesAutres.count == 1
                        ? nomsDesAutres[0] : "Les autres participants")

            messageCapture = Transcription.alerteSiTropCourt(transcript, duree: duree)
                ?? "Transcription terminée. L'attribution est exacte : elle vient de la "
                 + "piste d'où le son provient, pas d'une supposition."
        } catch {
            messageCapture = error.localizedDescription
                + " Les deux enregistrements sont conservés : rien n'est perdu."
        }
    }

    /// Reprend d'une réunion du calendrier tout ce qu'il est inutile de
    /// ressaisir. Le projet reste à confirmer : le titre d'une réunion ne dit
    /// pas toujours le nom du dossier, et c'est lui qui décide du rangement.
    func preparerDepuis(_ reunion: Calendrier.Reunion) {
        titreReunion = reunion.titre
        quandDate = reunion.debut
        format = reunion.mode == .visio ? "Visioconférence" : "Présentiel"
        if let lieu = reunion.lieu, reunion.mode != .visio { self.lieu = lieu }
        participants = reunion.participants.joined(separator: ", ")
        entree = reunion.mode == .visio ? .doublePiste : .microSeul
        if projet.isEmpty { projet = projetProbable(depuis: reunion.titre) }
    }

    /// Le titre d'une réunion contient souvent le nom du dossier — « Point avec
    /// l'utilisateur - Menuiseries Vidal ». On le propose, on ne l'impose pas.
    func projetProbable(depuis titre: String) -> String {
        let connus = (try? FileManager.default.contentsOfDirectory(
            atPath: racine.appendingPathComponent("comptes-rendus").path)) ?? []
        let normalise = { (t: String) in
            t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .filter { $0.isLetter || $0.isNumber }
        }
        let cible = normalise(titre)
        return connus.first { !$0.hasPrefix(".") && cible.contains(normalise($0)) } ?? ""
    }

    /// Pré-armement : l'enregistrement démarrera tout seul à l'heure dite.
    func armer(pour debut: Date) {
        minuterieArmement?.invalidate()
        let delai = max(0, debut.timeIntervalSinceNow)
        minuterieArmement = Timer.scheduledTimer(withTimeInterval: delai, repeats: false) { _ in
            Task { @MainActor [weak self] in await self?.demarrerEnregistrement() }
        }
    }

    /// Ce que fait le raccourci clavier : démarrer, ou arrêter.
    ///
    /// Un seul geste pour les deux, parce qu'au moment où une réunion commence
    /// on ne veut pas choisir — et parce qu'à la fin, on veut la même touche.
    func basculerLEnregistrement(reunionEnVisio: Bool) async {
        if enregistrementEnCours {
            await arreterEtTranscrire()
        } else {
            await enregistrerSansReunion(reunionEnVisio ? .doublePiste : .microSeul)
        }
    }

    /// Écrit le compte rendu dans un vrai document Word.
    ///
    /// Le PDF reste le document de référence ; celui-ci sert à annoter, ce
    /// qu'un PDF ne permet pas commodément.
    ///
    /// Le fichier est nommé d'après la réunion et non « Compte rendu » : il a
    /// vocation à partir en pièce jointe, où il se retrouvera au milieu de
    /// vingt autres fichiers du même nom.
    func exporterVersTraitementDeTexte() {
        let dossier = dossierDeLaReunion
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let nom = Rangement.nomDeFichier(projet: projet, objet: titreReunion, date: quandDate)
        let url = dossier.appendingPathComponent(
            "\(nom).\(Export.extensionTraitementDeTexte)")
        do {
            try Export.versTraitementDeTexte(
                compteRendu, vers: url, charte: charte,
                surTitre: reglages.identite.societe,
                enteteWord: enteteWord(titre: titreReunion))
            NSWorkspace.shared.activateFileViewerSelecting([url])
            messageCapture = "Le document Word « \(url.lastPathComponent) » est prêt : "
                + "le Finder vient de s'ouvrir dessus."
        } catch {
            messageCapture = "Le document Word n'a pas pu être écrit. "
                + "\(error.localizedDescription)"
        }
    }

    /// Prépare l'email dans le logiciel de courrier, sans jamais l'envoyer.
    func ouvrirLeBrouillon() {
        let (objet, corps) = Export.decouper(emailClient)
        let adresse = destinataire.contains("@") ? destinataire : ""
        if !Export.brouillonEmail(objet: objet, corps: corps, destinataire: adresse) {
            messageCapture = "Aucun logiciel de courrier n'a pu être ouvert. "
                + "Le texte reste disponible ici, et le bouton Copier fonctionne."
        }
    }

    /// Demande à Claude ce qu'il faudrait retenir de ce reproche.
    ///
    /// À la demande, jamais après chaque compte rendu : une application qui
    /// réclame un avis à chaque fois finit par n'en recevoir aucun.
    func deduireUneConsigne(_ reproche: String) async {
        guard !reproche.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        deductionEnCours = true
        defer { deductionEnCours = false }

        // Le dialogue de la réunion est le bon interlocuteur : il a le compte
        // rendu sous les yeux et sait de quoi le reproche parle.
        guard let chaine else {
            messageCapture = "Le dialogue avec Claude est terminé : la consigne ne peut "
                + "plus être déduite pour ce compte rendu."
            return
        }
        do {
            consigneProposee = try await chaine.deduireUneConsigne(reproche)
            if consigneProposee == nil {
                messageCapture = "Ce reproche tient à cette réunion-là : il n'y a pas de "
                    + "règle générale à en tirer."
            }
        } catch {
            messageCapture = error.localizedDescription
        }
    }

    /// Retient une consigne validée, pour ce dossier ou pour tous.
    func retenir(_ consigne: String, portee: PorteeConsigne) {
        switch portee {
        case .ceDossier:
            var consignes = consignesDuDossier
            consignes.ajouter(consigne)
            try? consignes.enregistrer(racine: racine, projet: projet)
            consignesDuDossier = consignes
        case .tousLesDossiers:
            var identite = reglages.identite
            let propre = consigne.trimmingCharacters(in: .whitespacesAndNewlines)
            let ligne = propre.hasPrefix("-") ? propre : "- " + propre
            identite.charte = identite.charte.isEmpty ? ligne : identite.charte + "\n" + ligne
            reglages.identite = identite
        }
        consigneProposee = nil
        messageCapture = portee == .ceDossier
            ? "Consigne retenue pour \(projet). Elle s'appliquera aux prochains comptes "
              + "rendus de ce dossier."
            : "Consigne ajoutée à votre charte. Elle s'appliquera à tous vos comptes rendus."
    }

    /// L'étape qui a échoué, pour pouvoir la relancer.
    ///
    /// Un échec en pleine rédaction faisait tout perdre : le transcript et les
    /// réponses restaient en mémoire, mais il fallait repartir de l'analyse —
    /// donc reposer toutes les questions. Or l'échec le plus courant est une
    /// limite de forfait ou un réseau qui tombe : la matière est intacte, seul
    /// le dialogue s'est interrompu.
    enum EtapeEchouee: Equatable { case analyse, reponses, redaction, filtrage, email }

    /// Relance ce qui a échoué, sans refaire ce qui a réussi.
    func reessayer() async {
        guard let quoi = etapeEchouee else { return }
        etapeEchouee = nil
        switch quoi {
        case .analyse: await lancerAnalyse()
        case .reponses: await transmettreReponses()
        case .redaction:
            // Le dialogue est perdu avec le processus : on repart de l'analyse,
            // mais les réponses déjà données sont conservées et retransmises.
            await lancerAnalyse()
        case .filtrage: await demanderFiltrage()
        case .email: await redigerEmail()
        }
    }

    /// Reprend un compte rendu déjà produit, pour le corriger et refaire son PDF.
    ///
    /// Un compte rendu se relit des mois plus tard, et parfois se corrige : une
    /// phrase mal comprise, un montant qu'on a vérifié depuis. Sans cela, il
    /// fallait rouvrir le Markdown dans un éditeur, puis refaire le PDF à la
    /// main — donc ne jamais le faire.
    /// Un compte rendu en cours serait-il perdu si l'on en rouvrait un autre ?
    var rouvrirEcraseraitLeTravail: Bool { travailNonEnregistre }

    func rouvrir(_ reunion: Rangement.Reunion, projet: String, contenu: String) {
        // Le dialogue en cours porte sur une autre réunion : le laisser vivre
        // garderait un processus ouvert pour rien.
        if let ancienne = chaine {
            chaine = nil
            Task { await ancienne.terminer() }
        }
        // Écrire là où le document a été trouvé, et non dans un dossier
        // recalculé : corriger un compte rendu ne doit pas en créer un second
        // à côté.
        dossierRetenu = reunion.dossier
        compteRendu = contenu
        self.projet = projet
        titreReunion = reunion.objet
        if let date = reunion.date { quandDate = date }
        // Le transcript revient avec, s'il est là : sans lui, on ne peut plus
        // vérifier d'où vient une phrase.
        let transcriptURL = Rangement.chemin(.transcript, dans: reunion.dossier)
        transcript = (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
        cheminPDF = reunion.pdf
        emailClient = (try? String(contentsOf: Rangement.chemin(.email, dans: reunion.dossier),
                                   encoding: .utf8)) ?? ""
        cheminEmail = emailClient.isEmpty ? nil : Rangement.chemin(.email, dans: reunion.dossier)
        questions = []
        reponses = [:]
        etapeAvantAccueil = nil
        etape = .resultat
        rafraichirLeContexte()
    }

    /// Ferme proprement ce qui est en cours avant que l'application ne parte.
    ///
    /// Un fichier audio est écrit au fil de l'eau, mais son en-tête n'est
    /// complété qu'à la fermeture : quitter sans cela pouvait rendre une
    /// réunion entière illisible. La transcription, elle, n'est pas lancée —
    /// elle prendrait trop de temps ; l'enregistrement sera retrouvé au
    /// prochain lancement dans la fenêtre des enregistrements.
    func cloreAvantDeQuitter() async {
        guard enregistrementEnCours else { return }
        minuterie?.invalidate(); minuterie = nil
        enregistrementEnCours = false
        if entree == .doublePiste {
            _ = try? await captureDouble.arreter()
        } else {
            _ = try? capture.arreter()
        }
        await chaine?.terminer()
    }

    /// Annule un enregistrement programmé.
    ///
    /// On pouvait armer, jamais se dédire : il fallait ouvrir la fenêtre, et
    /// même là rien ne le permettait. Une réunion annulée laissait donc un
    /// enregistrement se déclencher tout seul, dans le vide.
    func desarmer() {
        minuterieArmement?.invalidate()
        minuterieArmement = nil
    }

    /// Le compte rendu le plus récent, tous dossiers confondus.
    ///
    /// Sert au menu : ouvrir le PDF ou son dossier sont deux gestes qui n'ont
    /// aucune raison de passer par la fenêtre principale.
    var dernierCompteRendu: (projet: String, reunion: Rangement.Reunion)? {
        let racineCR = racine.appendingPathComponent("comptes-rendus")
        let projets = (try? FileManager.default.contentsOfDirectory(atPath: racineCR.path)) ?? []
        var meilleur: (projet: String, reunion: Rangement.Reunion)?
        for projet in projets where !projet.hasPrefix(".") {
            guard let derniere = Rangement.reunions(racine: racine, projet: projet)
                .first(where: { $0.compteRendu != nil }) else { continue }
            let date = derniere.date ?? .distantPast
            if meilleur == nil || date > (meilleur!.reunion.date ?? .distantPast) {
                meilleur = (projet, derniere)
            }
        }
        return meilleur
    }

    static func horodatageFichier() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: Date())
    }

}