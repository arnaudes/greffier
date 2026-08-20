import SwiftUI
import NoyauCR

/// Ce que l'icône de la barre de menus raconte.
///
/// **Pas de notification** (chantier § 3) : l'icône change d'état, on ouvre le
/// menu. Et **pas de pastille rouge** : elle est disproportionnée pour un outil
/// qui vit là toute la journée, et elle attire l'œil des personnes en face quand
/// l'écran est partagé. L'icône se remplit, avec un accent sobre.
///
/// La seule contrainte maintenue : discret ne veut pas dire invisible. Il faut
/// pouvoir dire d'un coup d'œil si ça tourne, sans ouvrir le menu.
enum EtatIcone {
    case repos
    case reunionProche
    case reunionEnCours
    case enregistrement
    case traitement

    var symbole: String {
        switch self {
        case .repos: "text.bubble"
        case .reunionProche: "text.bubble"
        case .reunionEnCours: "text.bubble.fill"
        case .enregistrement: "waveform.circle.fill"
        case .traitement: "ellipsis.circle"
        }
    }

    /// L'accent de couleur reste sobre : il ne sert qu'à distinguer
    /// l'enregistrement d'une réunion simplement en cours.
    var teinte: Color? {
        switch self {
        case .enregistrement: .accentColor
        default: nil
        }
    }
}

@MainActor
@Observable
final class Veilleur {
    var reunion: Calendrier.Reunion?
    var autorisationCalendrier = Calendrier.autorisationAccordee
    private var minuterie: Timer?
    private let reglages: Reglages

    init(reglages: Reglages) { self.reglages = reglages }

    /// Le pré-armement, accepté à la conception : quand la réunion n'a pas
    /// encore commencé, on peut demander à ce que l'enregistrement démarre tout
    /// seul à l'heure dite.
    var armeePour: String?

    func commencerAVeiller() {
        rafraichir()
        // Toutes les trente secondes : assez pour ne pas rater le début d'une
        // réunion, assez peu pour ne rien coûter.
        minuterie = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.rafraichir() }
        }
    }

    /// L'état des quatre conditions nécessaires, rafraîchi avec le reste.
    ///
    /// Vérifié ici plutôt qu'à l'ouverture du menu : la recherche du programme
    /// Claude peut lancer un shell de connexion la première fois, ce qu'on ne
    /// veut pas payer à chaque clic sur l'icône.
    var prerequis = Prerequis(etats: [:])

    func rafraichir() {
        autorisationCalendrier = Calendrier.autorisationAccordee
        prerequis = Prerequis.verifier(
            cheminClaude: reglages.cheminClaude.trimmingCharacters(in: .whitespaces).isEmpty
                ? "claude" : reglages.cheminClaude,
            dossierDeTravail: reglages.dossierDeTravail)
        guard autorisationCalendrier else { reunion = nil; return }
        reunion = reglages.calendrier.reunionAProposer()
    }

    /// La version publiée la plus récente, quand elle est plus récente que la
    /// nôtre et que l'utilisateur veut être prévenu.
    var miseAJour: VerificationVersion.Publication?

    /// Regarde s'il existe une version plus récente. Échoue en silence : une
    /// application qui se plaint de ne pas joindre GitHub est une application
    /// cassée aux yeux de qui l'utilise.
    func chercherUneMiseAJour(force: Bool = false) async {
        guard reglages.previenirDesMisesAJour else { miseAJour = nil; return }
        if !force,
           VerificationVersion.aDejaRegarde(reglages.derniereVerification) { return }

        let publication = try? await VerificationVersion.derniere()
        reglages.derniereVerification = Date()
        guard VerificationVersion.doitPrevenir(
            publication, versionActuelle: versionGreffier,
            prevenir: reglages.previenirDesMisesAJour,
            versionEcartee: reglages.versionEcartee.isEmpty ? nil : reglages.versionEcartee)
        else { miseAJour = nil; return }
        miseAJour = publication
    }

    /// Écarte cette version : elle ne sera plus signalée, la suivante le sera.
    func ecarter(_ publication: VerificationVersion.Publication) {
        reglages.versionEcartee = publication.version
        miseAJour = nil
    }

    func demanderLAutorisation() async {
        _ = await Calendrier.autoriser()
        rafraichir()
    }

    func etat(enregistrement: Bool, traitement: Bool) -> EtatIcone {
        if enregistrement { return .enregistrement }
        if traitement { return .traitement }
        guard let reunion else { return .repos }
        return reunion.enCours ? .reunionEnCours : .reunionProche
    }
}

/// Le menu de la barre — l'endroit où l'on agit sans ouvrir la fenêtre.
///
/// Refait le 19/08/2026. L'icône connaissait cinq états, le menu n'en couvrait
/// que deux : pendant un traitement, il proposait d'enregistrer une réunion
/// alors que Claude était en train de rédiger. Les prérequis manquants ne se
/// découvraient qu'à la fin, après avoir enregistré, et le dernier compte rendu
/// n'était atteignable qu'en ouvrant l'application.
///
/// La structure — des modules empilés, séparés par un trait fin, chacun avec
/// son intertitre — est empruntée aux menus de MacPaw. Leur palette, non : elle
/// habille une densité d'information que ce menu n'a pas.
struct MenuGreffier: View {
    @Bindable var session: Session
    @Bindable var veilleur: Veilleur
    @Environment(\.openWindow) private var ouvrirFenetre

    /// La grille : une marge, une gouttière, et des boutons qui se partagent la
    /// largeur à égalité. Sans elle, chaque bouton prenait la largeur de son
    /// texte et la colonne partait de travers.
    private let marge: CGFloat = 15
    private let gouttiere: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            entete
            if session.enregistrementEnCours {
                moduleEnregistrement
            } else if session.etape.estUnTraitement || session.avancement != nil {
                moduleTraitement
            } else {
                moduleMiseAJour
                moduleEtat
                moduleReunion
                moduleEnregistrerMaintenant
                moduleDernierCompteRendu
            }
            modulePied
        }
        .padding(marge)
        .frame(width: 300)
        .background(Teinte.fondHaut)
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 8) {
            Marque(cote: 19)
            Text("Greffier").font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Teinte.texte)
            Spacer()
            if let armee = veilleur.armeePour, !session.enregistrementEnCours {
                Button {
                    veilleur.armeePour = nil
                    session.desarmer()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.xmark").font(.system(size: 10))
                        Text("Armé").font(.system(size: 10.5))
                    }
                    .foregroundStyle(Teinte.bleuClair)
                }
                .buttonStyle(.plain)
                .help("Armé pour « \(armee) ». Cliquez pour annuler.")
            }
        }
    }

    // MARK: - Pendant un enregistrement

    private var moduleEnregistrement: some View {
        ModuleMenu(premier: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Circle().fill(Color.red).frame(width: 9, height: 9)
                    Text(session.depuisCombienDeTemps)
                        .font(.system(size: 26, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Teinte.texte)
                }
                Text(session.entree == .doublePiste
                     ? "Visioconférence, deux pistes séparées."
                     : "Micro de cet ordinateur.")
                    .font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
                BoutonPrincipal(titre: "Arrêter et transcrire", icone: "stop.fill",
                                pleineLargeur: true) {
                    Task { await session.arreterEtTranscrire(); ouvrirFenetre(id: "principale") }
                }
                Text("Ou \(RaccourciGlobal.libelle), sans ouvrir ce menu.")
                    .font(.system(size: 10.5)).foregroundStyle(Teinte.texteFaible)
            }
        }
    }

    // MARK: - Pendant un traitement

    private var moduleTraitement: some View {
        ModuleMenu(titre: "En cours", premier: true) {
            VStack(alignment: .leading, spacing: 9) {
                if let ou = session.avancement {
                    HStack {
                        Text(libelleTraitement).font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Teinte.texte)
                        Spacer()
                        Text("\(Int((ou * 100).rounded())) %")
                            .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Teinte.bleuClair)
                    }
                    BarreProgression(fraction: ou, largeur: 270 - 0)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(libelleTraitement).font(.system(size: 12.5))
                            .foregroundStyle(Teinte.texte)
                    }
                }
                if let message = session.messageCapture {
                    Text(message).font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var libelleTraitement: String {
        switch session.etape {
        case .analyse: "Claude lit la réunion"
        case .redaction: "Claude rédige le compte rendu"
        case .redactionEmail: "Claude rédige l'email"
        default: "Transcription"
        }
    }

    // MARK: - Une version plus récente

    @ViewBuilder private var moduleMiseAJour: some View {
        if let maj = veilleur.miseAJour {
            ModuleMenu(premier: true) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13)).foregroundStyle(Teinte.bleuClair)
                        Text("Version \(maj.version) disponible")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Teinte.texte)
                    }
                    if let notes = maj.notes {
                        Text(notes).font(.system(size: 11))
                            .foregroundStyle(Teinte.texteDoux)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: gouttiere) {
                        BoutonDiscret(titre: maj.telechargement == nil ? "Voir" : "Télécharger",
                                      icone: "arrow.down", pleineLargeur: true) {
                            NSWorkspace.shared.open(maj.telechargement ?? maj.page)
                        }
                        BoutonDiscret(titre: "Plus tard", pleineLargeur: true) {
                            veilleur.miseAJour = nil
                        }
                        BoutonDiscret(titre: "Ignorer", pleineLargeur: true) {
                            veilleur.ecarter(maj)
                        }
                        .help("Cette version ne sera plus signalée. La suivante le sera.")
                    }
                }
            }
        }
    }

    // MARK: - L'état, en un coup d'œil

    private var moduleEtat: some View {
        ModuleMenu(premier: true) {
            VStack(alignment: .leading, spacing: 9) {
                PastilleEtat(gravite: veilleur.prerequis.gravite,
                             texte: veilleur.prerequis.resume,
                             detail: veilleur.prerequis.manques.first?.consequence)
                if !veilleur.prerequis.toutVaBien {
                    HStack(spacing: gouttiere) {
                        if let aRegler = veilleur.prerequis.manques.first {
                            BoutonDiscret(titre: "Autoriser", icone: "checkmark.shield",
                                          pleineLargeur: true) {
                                Task {
                                    _ = await Prerequis.demander(aRegler)
                                    veilleur.rafraichir()
                                }
                            }
                        }
                        BoutonReglages(titre: "Réglages", pleineLargeur: true) {
                            ouvrirFenetre(id: "principale")
                        }
                    }
                }
            }
        }
    }

    // MARK: - La réunion du moment

    @ViewBuilder private var moduleReunion: some View {
        if let reunion = veilleur.reunion {
            ModuleMenu(titre: reunion.enCours ? "En ce moment" : "À venir") {
                VStack(alignment: .leading, spacing: 9) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reunion.titre).font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Teinte.texte).lineLimit(2)
                        Text(sousTitre(reunion)).font(.system(size: 11))
                            .foregroundStyle(Teinte.texteFaible)
                    }
                    HStack(spacing: gouttiere) {
                        BoutonPrincipal(titre: "Enregistrer", icone: "record.circle",
                                        actif: veilleur.prerequis.peutEnregistrer,
                                        pleineLargeur: true) {
                            session.preparerDepuis(reunion)
                            Task { await session.demarrerEnregistrement() }
                        }
                        if !reunion.enCours {
                            BoutonDiscret(titre: "Programmer", icone: "clock",
                                          pleineLargeur: true) {
                                veilleur.armeePour = reunion.titre
                                session.preparerDepuis(reunion)
                                session.armer(pour: reunion.debut)
                            }
                        }
                    }
                }
            }
        } else if veilleur.prerequis.etat(.calendrier).satisfait {
            ModuleMenu(titre: "Votre calendrier") {
                Text("Aucune réunion en cours ni à venir dans l'heure.")
                    .font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Enregistrer sans réunion

    private var moduleEnregistrerMaintenant: some View {
        ModuleMenu(titre: "Enregistrer maintenant") {
            VStack(alignment: .leading, spacing: 7) {
                Text("Raccourci : \(RaccourciGlobal.libelle), de n'importe où.")
                    .font(.system(size: 10.5)).foregroundStyle(Teinte.texteFaible)
                HStack(spacing: gouttiere) {
                    BoutonDiscret(titre: "Au micro", icone: "mic",
                                  actif: veilleur.prerequis.peutEnregistrer,
                                  pleineLargeur: true) {
                        Task { await session.enregistrerSansReunion(.microSeul) }
                    }
                    .help("Une réunion dans la pièce, captée par le micro de cet ordinateur.")
                    BoutonDiscret(titre: "En visio", icone: "video",
                                  actif: veilleur.prerequis.peutEnregistrer,
                                  pleineLargeur: true) {
                        Task { await session.enregistrerSansReunion(.doublePiste) }
                    }
                    .help("Deux pistes séparées : votre micro d'un côté, le son des autres "
                          + "participants de l'autre. L'attribution des propos est alors exacte.")
                }
                if let message = session.messageCapture, !veilleur.prerequis.peutEnregistrer {
                    Text(message).font(.system(size: 11)).foregroundStyle(Teinte.ambre)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Le dernier compte rendu

    @ViewBuilder private var moduleDernierCompteRendu: some View {
        if let dernier = session.dernierCompteRendu {
            ModuleMenu(titre: "Dernier compte rendu") {
                VStack(alignment: .leading, spacing: 9) {
                    Text("\(dernier.projet) · \(dernier.reunion.titre)")
                        .font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
                        .lineLimit(1)
                    HStack(spacing: gouttiere) {
                        if let pdf = dernier.reunion.pdf {
                            BoutonDiscret(titre: "Le PDF", icone: "doc.richtext",
                                          pleineLargeur: true) {
                                NSWorkspace.shared.open(pdf)
                            }
                        }
                        BoutonDiscret(titre: "Le dossier", icone: "folder",
                                      pleineLargeur: true) {
                            NSWorkspace.shared.open(dernier.reunion.dossier)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pied

    private var modulePied: some View {
        ModuleMenu {
            HStack(spacing: gouttiere) {
                BoutonDiscret(titre: "Ouvrir Greffier", icone: "macwindow",
                              pleineLargeur: true) {
                    ouvrirFenetre(id: "principale")
                }
                BoutonDiscret(titre: "Quitter", pleineLargeur: true) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func sousTitre(_ reunion: Calendrier.Reunion) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH'h'mm"
        let heure = f.string(from: reunion.debut)
        let mode = reunion.mode == .visio ? "visioconférence" : "en présentiel"
        return reunion.enCours
            ? "En cours depuis \(heure) · \(mode)"
            : "À \(heure) · \(mode)"
    }
}
