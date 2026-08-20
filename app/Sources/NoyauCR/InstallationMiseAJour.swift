import Foundation

/// Installer une version plus récente sans manipuler un seul fichier.
///
/// L'application se contentait de prévenir : « une version existe, allez la
/// chercher ». Il fallait alors télécharger, décompresser, glisser le bundle
/// par-dessus l'ancien, relancer — quatre gestes, et **rien à la fin ne disait
/// que c'était fait**. C'est précisément le moment où l'on renonce à se mettre
/// à jour, et où une correction reste sur l'étagère.
///
/// Le procédé tient en quatre temps : télécharger d'avance, vérifier, remplacer
/// depuis l'extérieur, relancer.
///
/// **Remplacer depuis l'extérieur** n'est pas un détail : écraser le bundle
/// d'une application en cours d'exécution la fait planter. Un petit script
/// attend donc la fin du processus avant d'agir, et rallume la lumière derrière
/// lui.
public enum InstallationMiseAJour {

    public enum Erreur: Error, LocalizedError {
        case aucunFichierJoint
        case telechargementEchoue(String)
        case archiveIllisible
        case bundleAbsent
        case signatureInvalide
        case installationEchouee(String)

        public var errorDescription: String? {
            switch self {
            case .aucunFichierJoint:
                "Cette version n'a pas d'application prête à installer. "
                    + "Il faut la recompiler soi-même."
            case .telechargementEchoue(let detail):
                "Le téléchargement a échoué. \(detail)"
            case .archiveIllisible:
                "L'archive téléchargée n'a pas pu être ouverte."
            case .bundleAbsent:
                "L'archive ne contient pas d'application Greffier."
            case .signatureInvalide:
                "L'application téléchargée n'est pas correctement signée : "
                    + "elle n'a pas été installée."
            case .installationEchouee(let detail):
                "L'installation a échoué. \(detail)"
            }
        }
    }

    /// Où la version téléchargée attend son heure.
    ///
    /// Dans les caches : si le système fait le ménage, on retéléchargera, ce
    /// qui est sans conséquence — alors qu'encombrer les Documents de
    /// l'utilisateur avec des archives serait impardonnable.
    public static var dossierDAttente: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Greffier/mises-a-jour")
    }

    // MARK: - Télécharger d'avance

    /// Récupère l'application de cette version et la prépare, sans rien
    /// installer. Rendue prête, elle s'installera d'un seul clic.
    ///
    /// - Returns: le bundle décompressé, prêt à prendre la place de l'autre.
    public static func preparer(_ publication: VerificationVersion.Publication,
                                progression: (@Sendable (Double) -> Void)? = nil)
        async throws -> URL {
        guard let source = publication.telechargement else { throw Erreur.aucunFichierJoint }

        let dossier = dossierDAttente.appendingPathComponent(publication.version)
        let bundle = dossier.appendingPathComponent("Greffier.app")
        // Déjà prête d'une tentative précédente : inutile de recommencer.
        if FileManager.default.fileExists(atPath: bundle.path) { return bundle }

        try? FileManager.default.removeItem(at: dossier)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)

        let archive = dossier.appendingPathComponent("Greffier.zip")
        try await telecharger(source, vers: archive, progression: progression)

        // La quarantaine posée sur tout fichier venu du réseau ferait afficher
        // « développeur non identifié » à chaque lancement. L'utilisateur a
        // demandé cette mise à jour : elle n'a pas à se présenter comme
        // suspecte.
        _ = lancer("/usr/bin/xattr", ["-dr", "com.apple.quarantine", archive.path])

        guard lancer("/usr/bin/ditto", ["-x", "-k", archive.path, dossier.path]) == 0 else {
            throw Erreur.archiveIllisible
        }
        try? FileManager.default.removeItem(at: archive)

        guard FileManager.default.fileExists(atPath: bundle.path) else {
            throw Erreur.bundleAbsent
        }
        // Une archive tronquée ou altérée en chemin donnerait une application
        // qui plante au lancement, après avoir remplacé celle qui marchait.
        guard lancer("/usr/bin/codesign", ["--verify", "--deep", bundle.path]) == 0 else {
            throw Erreur.signatureInvalide
        }
        return bundle
    }

    /// La version qui attend déjà, s'il y en a une.
    public static func dejaPrete(pour version: String) -> URL? {
        let bundle = dossierDAttente.appendingPathComponent(version)
            .appendingPathComponent("Greffier.app")
        return FileManager.default.fileExists(atPath: bundle.path) ? bundle : nil
    }

    /// Fait le ménage des versions préparées qui ne servent plus.
    public static func oublierLesAutres(sauf version: String) {
        let contenu = (try? FileManager.default.contentsOfDirectory(
            atPath: dossierDAttente.path)) ?? []
        for nom in contenu where nom != version {
            try? FileManager.default.removeItem(
                at: dossierDAttente.appendingPathComponent(nom))
        }
    }

    // MARK: - Installer

    /// Remplace l'application et la relance.
    ///
    /// L'appelant doit quitter juste après : le script attend la fin de ce
    /// processus avant de toucher au bundle.
    ///
    /// - Parameter installee: le bundle à remplacer — celui qui tourne.
    public static func installerPuisRelancer(_ prete: URL, remplace installee: URL) throws {
        let script = dossierDAttente.appendingPathComponent("installer.sh")
        let texte = """
            #!/bin/bash
            # Écrit par Greffier pour se remplacer lui-même. Une application ne
            # peut pas écraser son propre bundle pendant qu'elle tourne : ce
            # script attend qu'elle ait fini, échange les deux, et la rallume.
            set -u
            for _ in $(seq 1 100); do
                pgrep -f "\(installee.path)/Contents/MacOS/" >/dev/null || break
                sleep 0.2
            done
            ANCIENNE="\(installee.path).ancienne"
            rm -rf "$ANCIENNE"
            # L'ancienne version est mise de côté, pas détruite : si l'échange
            # tourne mal, il reste quelque chose à remettre en place.
            mv "\(installee.path)" "$ANCIENNE" 2>/dev/null
            if ! ditto "\(prete.path)" "\(installee.path)"; then
                mv "$ANCIENNE" "\(installee.path)" 2>/dev/null
                open "\(installee.path)"
                exit 1
            fi
            rm -rf "$ANCIENNE"
            open "\(installee.path)"
            """
        try FileManager.default.createDirectory(at: dossierDAttente,
                                                withIntermediateDirectories: true)
        try texte.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)

        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: "/bin/bash")
        processus.arguments = [script.path]
        // Détaché : il doit survivre à l'application qui le lance.
        do { try processus.run() } catch {
            throw Erreur.installationEchouee(error.localizedDescription)
        }
    }

    // MARK: - Les briques

    private static func telecharger(_ source: URL, vers cible: URL,
                                    progression: (@Sendable (Double) -> Void)?)
        async throws -> Void {
        do {
            let (temporaire, reponse) = try await URLSession.shared.download(from: source)
            if let http = reponse as? HTTPURLResponse, http.statusCode != 200 {
                throw Erreur.telechargementEchoue("Le serveur a répondu \(http.statusCode).")
            }
            try? FileManager.default.removeItem(at: cible)
            try FileManager.default.moveItem(at: temporaire, to: cible)
            progression?(1)
        } catch let erreur as Erreur {
            throw erreur
        } catch {
            throw Erreur.telechargementEchoue(error.localizedDescription)
        }
    }

    @discardableResult
    private static func lancer(_ outil: String, _ arguments: [String]) -> Int32 {
        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: outil)
        processus.arguments = arguments
        processus.standardOutput = Pipe()
        processus.standardError = Pipe()
        do { try processus.run() } catch { return -1 }
        processus.waitUntilExit()
        return processus.terminationStatus
    }
}
