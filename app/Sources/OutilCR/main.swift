import Foundation
import NoyauCR

// Outil en ligne de commande servant à éprouver le noyau pendant la
// construction. Il ne fait pas partie de l'application livrée.
//
//   greffier-outil selection <lexique.json> <transcript.md>
//   greffier-outil version

let args = CommandLine.arguments

func sortir(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

switch args.count > 1 ? args[1] : "aide" {

case "version":
    print(versionGreffier)

case "selection":
    guard args.count == 4 else {
        sortir("Usage : greffier-outil selection <lexique.json> <transcript.md>")
    }
    let lexique: Lexique
    do {
        lexique = try Lexique.charger(depuis: URL(fileURLWithPath: args[2]))
    } catch {
        sortir("Lexique illisible : \(error.localizedDescription)")
    }
    guard let transcript = try? String(contentsOfFile: args[3], encoding: .utf8) else {
        sortir("Transcript illisible : \(args[3])")
    }

    let debut = Date()
    let retenues = lexique.selectionner(pourTranscript: transcript)
    let duree = Date().timeIntervalSince(debut)

    let poidsTotal = lexique.entrees.reduce(0) { $0 + poids($1) }
    let poidsRetenu = retenues.reduce(0) { $0 + poids($1) }

    print("Lexique : \(lexique.entrees.count) entrées, \(poidsTotal) octets")
    print("Retenues : \(retenues.count) entrées, \(poidsRetenu) octets")
    print(String(format: "Sélection faite en %.2f s", duree))
    print("")
    for e in retenues {
        let v = e.variantes.isEmpty ? "" : "  (variantes : \(e.variantes.joined(separator: ", ")))"
        print("  ✓ \(e.terme)\(v)")
    }
    let ecartees = lexique.entrees.filter { entree in
        !retenues.contains { $0.terme == entree.terme }
    }
    if !ecartees.isEmpty {
        print("")
        for e in ecartees { print("  · \(e.terme) — absent du transcript") }
    }

case "word":
    guard args.count == 4 else {
        sortir("Usage : greffier-outil word <compte-rendu.md> <sortie.docx>")
    }
    guard let markdown = try? String(contentsOfFile: args[2], encoding: .utf8) else {
        sortir("Compte rendu illisible : \(args[2])")
    }
    // La charte du dossier de travail, si elle existe ; celle par défaut sinon.
    let racine = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Greffier")
    do {
        let url = try Export.versTraitementDeTexte(
            markdown, vers: URL(fileURLWithPath: args[3]),
            charte: Charte.charger(racine: racine))
        let poids = (try? Data(contentsOf: url).count) ?? 0
        print("Écrit : \(url.path) (\(poids) octets)")
    } catch {
        sortir("Conversion impossible : \(error.localizedDescription)")
    }

case "pdf":
    guard args.count == 4 else { sortir("Usage : greffier-outil pdf <compte-rendu.md> <sortie.pdf>") }
    guard let markdown = try? String(contentsOfFile: args[2], encoding: .utf8) else {
        sortir("Compte rendu illisible : \(args[2])")
    }

    // Les métadonnées du bandeau se lisent dans le compte rendu lui-même :
    // son titre de niveau 1 et sa fiche d'identité de tête.
    func champ(_ nom: String) -> String? {
        for ligne in markdown.components(separatedBy: .newlines) where ligne.hasPrefix("|") {
            let c = ligne.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if c.count >= 2, c[0].replacingOccurrences(of: "**", with: "") == nom { return c[1] }
        }
        return nil
    }
    let titre = markdown.components(separatedBy: .newlines)
        .first { $0.hasPrefix("# ") }
        .map { String($0.dropFirst(2)) } ?? "Compte rendu de réunion"
    let projet = titre.components(separatedBy: "—").last?
        .trimmingCharacters(in: .whitespaces) ?? "—"

    let entete = RenduPDF.Entete(
        titre: titre,
        sousTitre: champ("Objet") ?? "Compte rendu interne.",
        projet: projet,
        date: champ("Date de la réunion") ?? "—")

    do {
        let url = try RenduPDF().ecrire(markdown: markdown, entete: entete,
                                        vers: URL(fileURLWithPath: args[3]))
        let taille = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("PDF écrit : \(url.path) (\(taille) octets)")
        print("Source HTML conservé à côté, pour pouvoir mettre le PDF à jour plus tard.")
    } catch {
        sortir("\(error.localizedDescription)")
    }

case "fusionner":
    // Reconstruit le transcript d'une visioconférence à partir de ses deux
    // pistes, sans passer par l'application. Sert à rattraper un enregistrement
    // dont la transcription a échoué : l'audio, lui, est conservé.
    guard args.count >= 4 else {
        sortir("Usage : greffier-outil fusionner <moi.caf> <les-autres.caf> [sortie.md]")
    }
    let pisteMoi = URL(fileURLWithPath: args[2])
    let pisteAutres = URL(fileURLWithPath: args[3])
    // Le nom vient de l'identité enregistrée par l'application ; à défaut, on
    // ne devine pas.
    let nomMoi = {
        let id = Identite.charger(depuis: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/Greffier/identite.json"))
        return id.nom.isEmpty ? "Moi" : id.nom
    }()
    let moteur = Transcription()

    for (nom, url) in [("micro", pisteMoi), ("les autres", pisteAutres)] {
        let duree = Capture.duree(de: url).map { Capture.lisible($0) } ?? "durée inconnue"
        print("Piste \(nom) : \(duree)")
    }
    print("")

    do {
        let depart = Date()
        print("Transcription de votre piste…")
        let moi = try await moteur.segmenter(pisteMoi) { ou in
            FileHandle.standardError.write(Data(
                "\r  \(ou.pourcentage) %  —  \(ou.mots) mots   ".utf8))
        }
        print("  \(moi.count) mots reconnus en \(Int(Date().timeIntervalSince(depart))) s")

        let depart2 = Date()
        print("Transcription de la piste des autres participants…")
        let autres = try await moteur.segmenter(pisteAutres) { ou in
            FileHandle.standardError.write(Data(
                "\r  \(ou.pourcentage) %  —  \(ou.mots) mots   ".utf8))
        }
        print("  \(autres.count) mots reconnus en \(Int(Date().timeIntervalSince(depart2))) s")

        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM yyyy, HH'h'mm"
        let quand = f.string(from: (try? pisteMoi.resourceValues(forKeys: [.creationDateKey]))?
            .creationDate ?? Date())

        let transcript = FusionPistes.enTete(
            reunion: pisteMoi.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "-moi", with: ""),
            quand: quand.prefix(1).uppercased() + quand.dropFirst(),
            nomMoi: nomMoi)
            + FusionPistes.fusionner(moi: moi, lesAutres: autres, nomMoi: nomMoi)

        if args.count > 4 {
            try transcript.write(to: URL(fileURLWithPath: args[4]),
                                 atomically: true, encoding: .utf8)
            print("")
            print("Transcript écrit : \(args[4])")
            print("\(transcript.split(separator: " ").count) mots.")
        } else {
            print("")
            print(transcript)
        }
    } catch {
        sortir("\n\(error.localizedDescription)")
    }

case "compresser":
    // Éprouve la compression sur un vrai enregistrement, et sert à ranger
    // l'audio d'une réunion déjà transcrite.
    guard args.count >= 3 else {
        sortir("Usage : greffier-outil compresser <fichier.caf> [destination.m4a]")
    }
    do {
        let source = URL(fileURLWithPath: args[2])
        let cible = args.count > 3 ? URL(fileURLWithPath: args[3]) : nil
        print("Compression de \(source.lastPathComponent)…")
        let bilan = try await CompressionAudio.compresser(source, vers: cible)
        print("  \(CompressionAudio.gain(avant: bilan.avant, apres: bilan.apres))")
        print("  → \(bilan.url.path)")
    } catch {
        sortir(error.localizedDescription)
    }

case "unifier":
    // Réunit les deux pistes d'une visio en un seul fichier stéréo :
    // à gauche celui qui tient le micro, à droite les autres.
    guard args.count >= 5 else {
        sortir("Usage : greffier-outil unifier <moi> <les-autres> <sortie.m4a>")
    }
    do {
        let bilan = try FusionAudio.unifier(moi: URL(fileURLWithPath: args[2]),
                                            lesAutres: URL(fileURLWithPath: args[3]),
                                            vers: URL(fileURLWithPath: args[4]))
        print("Fichier unifié : \(bilan.url.lastPathComponent) "
              + "(\(FusionAudio.lisible(bilan.taille)))")
    } catch {
        sortir(error.localizedDescription)
    }

case "ranger":
    // Migration de l'ancien classement — tous les fichiers à plat dans le
    // dossier du client — vers un dossier par réunion. À lancer une fois.
    let racineCR = args.count > 2
        ? URL(fileURLWithPath: args[2])
        : URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/Greffier/comptes-rendus")
    let pourDeVrai = args.contains("--appliquer")
    let fm = FileManager.default

    print(pourDeVrai ? "Rangement en cours." : "Simulation — rien ne sera déplacé.")
    print("Ajoutez --appliquer pour exécuter.")
    print("")

    let projets = ((try? fm.contentsOfDirectory(atPath: racineCR.path)) ?? [])
        .filter { !$0.hasPrefix(".") }
        .sorted()

    for projet in projets {
        let dossierProjet = racineCR.appendingPathComponent(projet)
        var estDossier: ObjCBool = false
        guard fm.fileExists(atPath: dossierProjet.path, isDirectory: &estDossier),
              estDossier.boolValue else { continue }
        let fichiers = ((try? fm.contentsOfDirectory(atPath: dossierProjet.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
        // Une date en fin de nom, « …-2026-08-19.md », identifie la réunion.
        let motif = try! NSRegularExpression(pattern: "(\\d{4})-(\\d{2})-(\\d{2})")

        var parReunion: [String: [String]] = [:]
        for fichier in fichiers {
            let plage = NSRange(fichier.startIndex..., in: fichier)
            guard let trouve = motif.firstMatch(in: fichier, range: plage),
                  let r = Range(trouve.range, in: fichier) else { continue }
            parReunion[String(fichier[r]), default: []].append(fichier)
        }
        guard !parReunion.isEmpty else { continue }

        print("\(projet) — \(parReunion.count) réunion(s)")
        for (dateISO, groupe) in parReunion.sorted(by: { $0.key < $1.key }) {
            let bouts = dateISO.components(separatedBy: "-")
            let nomDossier = "\(bouts[0])-\(bouts[1])-\(bouts[2])"
            let cible = dossierProjet.appendingPathComponent(nomDossier)
            print("  \(nomDossier)/")

            for fichier in groupe.sorted() {
                let source = dossierProjet.appendingPathComponent(fichier)
                let nouveau: String
                switch true {
                case fichier.hasPrefix("CR-interne-") && fichier.hasSuffix(".md"):
                    nouveau = "Compte rendu.md"
                case fichier.hasPrefix("CR-interne-") && fichier.hasSuffix(".pdf"):
                    nouveau = "Compte rendu.pdf"
                case fichier.hasPrefix("CR-interne-") && fichier.hasSuffix(".html"):
                    nouveau = "Fabrication/compte-rendu.html"
                case fichier.hasPrefix("Transcript-"):
                    nouveau = "Transcript.md"
                case fichier.hasPrefix("Mail-client-"):
                    nouveau = "Email client.md"
                default:
                    nouveau = fichier
                }
                print("    \(fichier)  →  \(nouveau)")
                guard pourDeVrai else { continue }
                let destination = cible.appendingPathComponent(nouveau)
                try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                try? fm.moveItem(at: source, to: destination)
            }
        }
        print("")
    }
    if !pourDeVrai { print("Aucun fichier n'a été touché.") }

case "ou-est-claude":
    // À lancer avec « env -i » pour reproduire les conditions du Finder :
    // une application lancée à la souris n'hérite pas du PATH du terminal.
    let voulu = args.count > 2 ? args[2] : "claude"
    print("Cherché sous le nom : \(voulu)")
    print("PATH hérité         : \(ProcessInfo.processInfo.environment["PATH"] ?? "(aucun)")")
    if let trouve = LocalisationClaude.resoudre(voulu) {
        print("Trouvé              : \(trouve)")
    } else {
        print("Introuvable.")
        print("")
        print("Candidats examinés :")
        for chemin in LocalisationClaude.candidats(nom: voulu) { print("  · \(chemin)") }
    }

case "transcription":
    // Vérifie ce que la machine sait faire, sans rien enregistrer.
    let etat = Transcription.etatDuMoteur()
    print("Moteur de reconnaissance vocale — \(etat.langue)")
    print("  disponible          : \(etat.disponible ? "oui" : "non")")
    print("  sur l'appareil      : \(etat.surLAppareil ? "oui" : "non")")
    print("  dictée activée      : \(etat.dictee ? "oui" : "NON")")
    print("  autorisation        : \(etat.autorisation)")
    print("")
    print(etat.pretATranscrire
          ? "Prêt à transcrire."
          : "PAS prêt à transcrire.")
    if !etat.dictee {
        print("")
        print("La dictée est désactivée, et la reconnaissance vocale s'appuie dessus —")
        print("y compris sur l'appareil. Le moteur répond pourtant « disponible » :")
        print("c'est ce qui rend la panne difficile à comprendre.")
        print("À activer dans Réglages Système, Clavier, Dictée, en français.")
    }
    if !etat.surLAppareil {
        print("")
        print("La transcription sur l'appareil est indispensable : rien du son")
        print("d'une réunion client ne doit partir sur un serveur. Le modèle se")
        print("télécharge dans Réglages Système, Clavier, Dictée.")
    }

case "transcrire":
    guard args.count == 3 else { sortir("Usage : greffier-outil transcrire <fichier.caf>") }
    let audio = URL(fileURLWithPath: args[2])
    guard FileManager.default.fileExists(atPath: audio.path) else {
        sortir("Fichier introuvable : \(audio.path)")
    }
    let etat = Transcription.etatDuMoteur()
    guard etat.pretATranscrire else {
        sortir("Pas prêt à transcrire — dictée activée : \(etat.dictee ? "oui" : "non")")
    }
    guard await Transcription.autoriser() else {
        sortir(Transcription.Erreur.autorisationRefusee.errorDescription!)
    }
    if let duree = Capture.duree(de: audio) {
        print("Enregistrement de \(Capture.lisible(duree)). Transcription en cours…")
    }
    do {
        let texte = try await Transcription().transcrire(audio) { ou in
            FileHandle.standardError.write(Data(
                "\r  \(ou.pourcentage) %  —  \(ou.mots) mots reconnus   ".utf8))
        }
        print("")
        print(texte)
    } catch {
        sortir("\n\(error.localizedDescription)")
    }

case "dialogue":
    // Éprouve le pont : deux tours dans une seule conversation, pour vérifier
    // que le contexte est bien conservé d'un temps au suivant.
    let modele = args.count > 2 ? args[2] : "claude-haiku-4-5-20251001"
    let pont = PontClaude(config: ConfigClaude(
        modele: modele,
        promptSysteme: "Tu réponds en français, brièvement, sans formule de politesse."))

    pont.surLimite = { limite in
        var texte = "  ⓘ forfait : \(limite.statut)"
        if let type = limite.type { texte += " (\(type))" }
        if let quand = limite.reinitialisationLe {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            texte += ", réinitialisation à \(f.string(from: quand))"
        }
        print(texte)
    }

    do {
        try pont.demarrer()
        print("Modèle demandé : \(modele)")

        let premier = try await pont.envoyer(
            "Retiens ce mot : « palette ». Réponds seulement : noté.")
        print("Tour 1 → \(premier)")

        let second = try await pont.envoyer(
            "Quel mot t'ai-je demandé de retenir ? Réponds par le seul mot.")
        print("Tour 2 → \(second)")

        print("Session : \(pont.sessionID ?? "inconnue")")
        let conserve = second.localizedCaseInsensitiveContains("palette")
        print(conserve
              ? "✓ Le contexte est conservé d'un tour à l'autre."
              : "✗ Le contexte n'a pas été conservé — le second tour ignore le premier.")
        pont.arreter()
        if !conserve { exit(1) }
    } catch {
        pont.arreter()
        sortir("Échec du dialogue : \(error.localizedDescription)")
    }

default:
    print("""
        greffier-outil — banc d'essai du noyau Greffier

          selection <lexique.json> <transcript.md>   ce qui serait transmis à Claude
          dialogue [modèle]                          deux tours, vérifie la mémoire
          ou-est-claude [nom]                        où le programme Claude Code est trouvé\n          ranger [dossier] [--appliquer]              range l'ancien classement par réunion
          transcription                              ce que la machine sait transcrire
          transcrire <fichier.caf>                   transcrit un enregistrement existant
          fusionner <moi.caf> <autres.caf> [out.md]  reconstruit un transcript de visio
          word <compte-rendu.md> <sortie.docx>       le compte rendu en document Word
          version                                    version CalVer
        """)
}

func poids(_ e: EntreeLexique) -> Int {
    (e.terme.count + e.variantes.reduce(0) { $0 + $1.count } + (e.note?.count ?? 0) + 40)
}
