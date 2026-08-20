import AVFoundation
import SwiftUI
import NoyauCR

/// Mode diagnostic : `Greffier --diagnostic-micro` demande l'accès au micro et
/// écrit ce qu'il obtient, sans ouvrir d'interface. Sert à éprouver la chaîne
/// d'autorisation depuis l'application elle-même, et non depuis un programme
/// de test qui n'aurait pas ses caractéristiques.
func diagnosticMicroSiDemande() {
    guard CommandLine.arguments.contains("--diagnostic-micro") else { return }
    let journal = URL(fileURLWithPath: "/tmp/greffier-diagnostic-micro.log")
    // `@Sendable` : cette fonction est appelée depuis le rappel d'autorisation,
    // qui arrive sur une file quelconque.
    @Sendable func note(_ texte: String) {
        let ligne = texte + "\n"
        if let h = try? FileHandle(forWritingTo: journal) {
            h.seekToEndOfFile(); h.write(Data(ligne.utf8)); try? h.close()
        } else { try? ligne.write(to: journal, atomically: true, encoding: .utf8) }
    }
    note("statut avant : \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
    AVCaptureDevice.requestAccess(for: .audio) { accorde in
        note("accordé      : \(accorde)")
        note("statut après : \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        exit(0)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(20))
    note("délai écoulé sans réponse")
    exit(1)
}

/// Ce qui doit arriver avant que l'application ne disparaisse.
///
/// **Quitter pendant un enregistrement laissait le fichier audio non clos** :
/// il est écrit au fil de l'eau, mais son en-tête n'est complété qu'à la
/// fermeture. Une réunion d'une heure pouvait ainsi devenir illisible — et le
/// menu de la barre propose « Quitter » juste à côté du chronomètre.
@MainActor
final class Sortie: NSObject, NSApplicationDelegate {
    var session: Session?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }

        // Un compte rendu produit mais pas encore enregistré n'existe que dans
        // la mémoire de l'application : le laisser partir en silence, c'est
        // perdre la réunion et toutes les réponses données.
        if session.travailNonEnregistre {
            let alerte = NSAlert()
            alerte.messageText = "Le compte rendu n'est pas enregistré."
            alerte.informativeText = "Il disparaîtra si vous quittez maintenant, "
                + "avec les réponses que vous avez données."
            alerte.alertStyle = .warning
            alerte.addButton(withTitle: "Enregistrer et quitter")
            alerte.addButton(withTitle: "Annuler")
            alerte.addButton(withTitle: "Quitter sans enregistrer")
            switch alerte.runModal() {
            case .alertFirstButtonReturn:
                session.enregistrer()
            case .alertSecondButtonReturn:
                return .terminateCancel
            default:
                break
            }
        }

        guard session.enregistrementEnCours else { return .terminateNow }
        // On ne discute pas : on ferme proprement l'enregistrement, puis on
        // laisse partir. Demander confirmation ferait perdre du temps au pire
        // moment.
        Task { @MainActor in
            await session.cloreAvantDeQuitter()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct AppGreffier: App {
    @State private var reglages: Reglages
    @State private var session: Session
    @State private var veilleur: Veilleur
    @NSApplicationDelegateAdaptor(Sortie.self) private var sortie
    @State private var raccourci = RaccourciGlobal()

    init() {
        diagnosticMicroSiDemande()
        let reglages = Reglages()
        _reglages = State(initialValue: reglages)
        _session = State(initialValue: Session(reglages: reglages))
        _veilleur = State(initialValue: Veilleur(reglages: reglages))
    }

    var body: some Scene {
        WindowGroup(id: "principale") {
            VuePrincipale(session: session, veilleur: veilleur)
                .frame(minWidth: 1040, minHeight: 680)
                .preferredColorScheme(reglages.apparence.schema)
                .task {
                    sortie.session = session
                    // Une réunion commence quand quelqu'un dit « on y va » : il
                    // faut pouvoir lancer l'enregistrement sans viser une icône.
                    raccourci.installer {
                        let enVisio = veilleur.reunion?.mode == .visio
                        Task { await session.basculerLEnregistrement(reunionEnVisio: enVisio) }
                    }
                    veilleur.commencerAVeiller()
                    session.rafraichirLeContexte()
                    // En arrière-plan, sans rien demander : la compression ne
                    // détruit rien, elle allège seulement ce qui traîne.
                    session.compresserLesVieuxOrphelins()
                    // Une fois par jour au plus, et en silence si le réseau
                    // manque : cette vérification est un confort, pas une étape.
                    await veilleur.chercherUneMiseAJour()
                }
        }
        .windowResizability(.contentSize)

        // L'icône vit dans la barre de menus toute la journée. Elle ne notifie
        // rien : elle change d'état, et c'est en l'ouvrant qu'on agit.
        MenuBarExtra {
            MenuGreffier(session: session, veilleur: veilleur)
                .preferredColorScheme(reglages.apparence.schema)
        } label: {
            let etat = veilleur.etat(enregistrement: session.enregistrementEnCours,
                                     traitement: session.etape.estUnTraitement)
            Image(systemName: etat.symbole)
                .foregroundStyle(etat.teinte ?? .primary)
        }
        .menuBarExtraStyle(.window)

        Settings {
            VueReglages(reglages: reglages)
                .preferredColorScheme(reglages.apparence.schema)
        }
    }
}

struct VuePrincipale: View {
    @Bindable var session: Session
    @Bindable var veilleur: Veilleur
    @State private var accueilEcarte = false

    var body: some View {
        VStack(spacing: 0) {
            if let alerte = session.alerteForfait {
                BandeauAlerte(texte: alerte)
            }
            // Ce qui manque, dit dans la fenêtre où l'on travaille — et non
            // dans un onglet de réglages qu'on n'ouvre jamais.
            if !accueilEcarte, !aRegler.isEmpty {
                BandeauAccueil(manques: aRegler, bloquant: !veilleur.prerequis.peutEnregistrer,
                               ecarter: veilleur.prerequis.peutEnregistrer
                                   ? { accueilEcarte = true } : nil)
            }
            contenu
        }
        .background(Teinte.fond)
        .overlay(alignment: .top) {
            if let annonce = session.annonceLexique {
                AnnonceLexiqueVue(annonce: annonce) { session.annonceLexique = nil }
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8),
                   value: session.annonceLexique)
    }

    /// Ce qu'il faut régler avant que Greffier ne donne son plein résultat.
    ///
    /// L'identité d'abord : c'est elle qui décide de la justesse des comptes
    /// rendus, et son absence ne se voit nulle part ailleurs. Les autorisations
    /// ensuite, seulement quand elles empêchent de capter une réunion — pour
    /// les autres, le menu de la barre suffit.
    private var aRegler: [String] {
        var manques: [String] = []
        let identite = session.reglages.identite
        if !identite.incomplet.isEmpty {
            manques.append("Il manque " + identite.incomplet.joined(separator: ", ")
                           + " pour que vos comptes rendus soient au niveau.")
        }
        if !veilleur.prerequis.peutEnregistrer {
            manques.append(veilleur.prerequis.resume)
        }
        return manques
    }

    @ViewBuilder private var contenu: some View {
        switch session.etape {
        case .preparation:
            VueAtelier(session: session)
        case .analyse(let ou):
            VueTravailEnCours(titre: "Analyse en cours", detail: ou,
                              etape: 2, libelleEtape: "Les questions",
                              apercu: session.apercuEnCours)
        case .interrogation:
            VueInterrogation(session: session)
        case .redaction:
            VueTravailEnCours(titre: "Rédaction du compte rendu",
                              detail: "Claude écrit à partir du transcript et de vos réponses.",
                              etape: 3, libelleEtape: "Le compte rendu",
                              apercu: session.apercuEnCours)
        case .resultat:
            VueResultat(session: session)
        case .filtrage:
            VueFiltrage(session: session)
        case .redactionEmail:
            VueTravailEnCours(titre: "Rédaction de l'email",
                              detail: "Claude dérive l'email du compte rendu, "
                                    + "en ne gardant que ce que vous avez retenu.",
                              etape: 4, libelleEtape: "L'email client",
                              apercu: session.apercuEnCours)
        case .emailPret:
            VueEmail(session: session)
        case .echec(let message):
            VueEchec(message: message, session: session)
        }
    }
}

/// Ce que le lexique vient d'apprendre.
///
/// C'est le moment où l'outil tient sa promesse — ces termes ne seront plus
/// jamais redemandés, et le prochain compte rendu du dossier coûtera moins que
/// celui-ci. Il méritait mieux qu'une ligne de texte dans un écran qu'on vient
/// de quitter.
struct AnnonceLexiqueVue: View {
    let annonce: Session.AnnonceLexique
    let fermer: () -> Void
    @State private var apparu = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Teinte.vert.opacity(0.18)).frame(width: 32, height: 32)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 14)).foregroundStyle(Teinte.vert)
                    .scaleEffect(apparu ? 1 : 0.4)
                    .opacity(apparu ? 1 : 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                if !annonce.termes.isEmpty {
                    Text(annonce.termes.count == 1
                         ? "Un terme est entré dans le lexique"
                         : "\(annonce.termes.count) termes sont entrés dans le lexique")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Teinte.texte)
                    // Les termes eux-mêmes, en pastilles : on veut voir CE qui
                    // a été appris, pas seulement qu'il s'est passé quelque chose.
                    HStack(spacing: 6) {
                        ForEach(Array(annonce.termes.prefix(4)), id: \.self) { terme in
                            Text(terme)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Teinte.vert)
                                .padding(.vertical, 3).padding(.horizontal, 9)
                                .background(Teinte.vert.opacity(0.14), in: Capsule())
                        }
                        if annonce.termes.count > 4 {
                            Text("+\(annonce.termes.count - 4)")
                                .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                        }
                    }
                    Text("Ils ne seront plus jamais redemandés.")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteDoux)
                }
                ForEach(annonce.arbitrages, id: \.self) { arbitrage in
                    Label(arbitrage + " — à trancher dans le lexique.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Teinte.ambre)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            Button { fermer() } label: {
                Image(systemName: "xmark").font(.system(size: 10))
                    .foregroundStyle(Teinte.texteFaible).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(Teinte.fondHaut,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(Teinte.vert.opacity(0.35)))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.12)) {
                apparu = true
            }
        }
    }
}

struct BandeauAlerte: View {
    let texte: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(Teinte.ambre)
            Text(texte).font(.system(size: 12)).foregroundStyle(Teinte.texte)
            Spacer()
        }
        .padding(.horizontal, 26).padding(.vertical, 10)
        .background(Teinte.ambre.opacity(0.14))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Teinte.ambre.opacity(0.3)).frame(height: 1)
        }
    }
}

/// L'attente. Elle dure — Claude lit quarante-cinq minutes de verbatim — et un
/// écran vide donnerait à croire que rien ne se passe : l'onde reprend celle de
/// l'enregistrement, et le détail dit à quoi on en est.
struct VueTravailEnCours: View {
    let titre: String
    let detail: String
    var etape = 2
    var libelleEtape = "Les questions"
    /// Ce que Claude a déjà écrit. Montré au fil de l'eau : il ne dit jamais où
    /// il en est, mais on peut voir le document se construire — et commencer à
    /// le lire avant la fin.
    var apercu = ""
    @State private var debut = Date()

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 14)
            OndeAnimee().frame(height: 40).frame(maxWidth: 260)
            VStack(spacing: 8) {
                Text(titre).font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Teinte.texte)
                Text(detail).font(.system(size: 13)).foregroundStyle(Teinte.texteDoux)
                    .multilineTextAlignment(.center).frame(maxWidth: 480)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TempsEcoule(depuis: debut)
            Jauge(etape: etape, total: 4, libelle: libelleEtape)

            if !apercu.isEmpty {
                ScrollViewReader { fil in
                    ScrollView {
                        Text(apercu)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Teinte.texteDoux)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .id("bas")
                    }
                    .frame(maxWidth: 720, maxHeight: 260)
                    .background(Teinte.carte,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Teinte.trait))
                    .onChange(of: apercu) { _, _ in
                        // Suivre le texte qui s'écrit, sans avoir à faire
                        // défiler soi-même.
                        withAnimation { fil.scrollTo("bas", anchor: .bottom) }
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 14)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Teinte.fond)
    }
}

struct VueEchec: View {
    let message: String
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34)).foregroundStyle(Teinte.ambre)
            VStack(spacing: 9) {
                Text("Le compte rendu n'a pas pu être produit")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(Teinte.texte)
                Text(message).font(.system(size: 13)).foregroundStyle(Teinte.texteDoux)
                    .multilineTextAlignment(.center).frame(maxWidth: 560)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Text("Rien n'est perdu : le transcript et vos réponses sont conservés.")
                .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
            HStack(spacing: 12) {
                BoutonDiscret(titre: "Revenir au transcript", icone: "arrow.left") {
                    session.etape = .preparation
                }
                // L'échec le plus courant est une limite de forfait ou un
                // réseau qui tombe : la matière est intacte, seul le dialogue
                // s'est interrompu. Refaire tout serait absurde.
                if session.etapeEchouee != nil {
                    BoutonPrincipal(titre: "Réessayer", icone: "arrow.clockwise") {
                        Task { await session.reessayer() }
                    }
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Teinte.fond)
    }
}
