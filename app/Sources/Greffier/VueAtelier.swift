import SwiftUI
import NoyauCR

/// L'écran de préparation, direction « l'atelier de nuit ».
///
/// Trois colonnes : les dossiers à gauche, une question à la fois au centre, et
/// à droite ce que l'outil sait déjà du dossier. Ce troisième panneau n'est pas
/// décoratif — il rend visible le mécanisme qui fait la valeur de Greffier et que
/// rien n'affichait jusqu'ici : les comptes rendus antérieurs qui seront relus,
/// et le lexique qui fait décroître le nombre de questions.
struct VueAtelier: View {
    @Bindable var session: Session
    @State private var colle = false
    @State private var details = false

    var body: some View {
        HStack(spacing: 0) {
            ColonneDossiers(session: session).frame(width: 214)
            centre
            FlancDuDossier(session: session).frame(width: 250)
        }
        .background(Teinte.fond)
        .onDrop(of: [.fileURL], isTargeted: nil) { fournisseurs in
            _ = fournisseurs.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let texte = try? String(contentsOf: url, encoding: .utf8)
                else { return }
                Task { @MainActor in
                    session.transcript = texte
                    if session.projet.isEmpty {
                        session.projet = url.deletingLastPathComponent().lastPathComponent
                    }
                    session.rafraichirLeContexte()
                    colle = true
                }
            }
            return true
        }
    }

    private var centre: some View {
        VStack(spacing: 0) {
            HStack {
                reprise
                Spacer()
                Jauge(etape: 1, total: 4, libelle: "La réunion")
            }
            .padding(.horizontal, 26).padding(.top, 16)

            VStack(spacing: 0) {
                Spacer(minLength: 12)
                if session.enregistrementEnCours {
                    // Pendant un enregistrement, l'écran ne parle que de ça.
                    // Auparavant il continuait de demander d'où venait la
                    // réunion, avec les trois cartes de choix : rien ne disait
                    // que le micro tournait ni comment l'arrêter.
                    enregistrementEnCours
                } else {
                    fil
                    question
                    if colle || !session.transcript.isEmpty { saisie } else { propositions }
                }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 34)

            pied
        }
    }

    /// De quoi repartir où l'on en était. Revenir à l'accueil ne détruit
    /// rien — encore faut-il pouvoir retourner à son travail, sans quoi le
    /// compte rendu produit resterait inaccessible jusqu'à la fermeture.
    @ViewBuilder private var reprise: some View {
        if let libelle = session.libelleEtapeInterrompue {
            BoutonDiscret(titre: libelle, icone: "arrow.uturn.right") {
                session.reprendre()
            }
        }
    }

    /// Ce qui est déjà réglé, rappelé sans encombrer — et cliquable : c'est
    /// par ces pastilles qu'on revient sur une décision.
    private var fil: some View {
        HStack(spacing: 7) {
            PastilleFil(texte: session.projet.isEmpty ? "Choisir un dossier" : "Dossier",
                        valeur: session.projet.isEmpty ? nil : session.projet,
                        manquant: session.projet.isEmpty) { details = true }
            PastilleFil(texte: "", valeur: session.quand) { details = true }
            PastilleFil(texte: session.perimetreRestreint
                        ? "Un seul sujet" : "Toute la réunion") { details = true }
            PastilleFil(texte: libelleEntree) { details = true }
        }
        .padding(.bottom, 26)
        .popover(isPresented: $details, arrowEdge: .bottom) {
            VueDetails(session: session, affiche: $details)
        }
    }

    private var libelleEntree: String {
        switch session.entree {
        case .collage: "Transcript collé"
        case .microSeul: "Micro seul"
        case .doublePiste: "Visio, deux pistes"
        case .notes: "Notes à la main"
        }
    }

    /// L'écran d'un enregistrement en cours : le temps écoulé en grand, et une
    /// seule action possible.
    private var enregistrementEnCours: some View {
        VStack(spacing: 22) {
            OndeAnimee()
                .frame(height: 60)

            VStack(spacing: 8) {
                Text("ENREGISTREMENT EN COURS")
                    .font(.system(size: 10.5, weight: .bold)).tracking(1.4)
                    .foregroundStyle(Teinte.bleuClair)
                Text(session.depuisCombienDeTemps)
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Teinte.texte)
                Text(session.entree == .doublePiste
                     ? "Deux pistes séparées : votre micro et le son des autres participants."
                     : "Le micro de cet ordinateur. Le son ne partira nulle part.")
                    .font(.system(size: 13)).foregroundStyle(Teinte.texteDoux)
                    .multilineTextAlignment(.center)
            }

            BoutonPrincipal(titre: "Arrêter et transcrire", icone: "stop.fill") {
                Task { await session.arreterEtTranscrire() }
            }
            .padding(.top, 6)

            Text("La transcription se fera ensuite, sur cet ordinateur — jamais pendant "
                 + "la réunion, pour ménager la batterie.")
                .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
    }

    private var question: some View {
        VStack(spacing: 11) {
            Text("LA MATIÈRE")
                .font(.system(size: 10.5, weight: .bold)).tracking(1.4)
                .foregroundStyle(Teinte.bleuClair)
            Text("D'où vient cette réunion ?")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(Teinte.texte)
            Text(session.transcript.isEmpty
                 ? "Le son ne quittera pas cet ordinateur."
                 : "\(session.motsDuTranscript) mots en place. Relisez, corrigez si besoin, "
                   + "puis analysez.")
                .font(.system(size: 13)).foregroundStyle(Teinte.texteDoux)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 520)
    }

    private var propositions: some View {
        VStack(spacing: 22) {
            OndeDecorative()
                .frame(height: 44)
                .padding(.top, 28)

            // « Coller » et « Déposer » lançaient exactement la même chose :
            // le doublon est remplacé par le choix qui manquait vraiment, entre
            // le micro et la visioconférence. Il fallait auparavant passer par
            // le popover des détails pour le régler.
            HStack(spacing: 11) {
                CarteChoix(icone: "mic", titre: "Enregistrer au micro",
                           detail: "Une réunion dans la pièce.",
                           vedette: true) {
                    session.entree = .microSeul
                    Task { await session.demarrerEnregistrement() }
                }
                CarteChoix(icone: "video", titre: "Enregistrer une visio",
                           detail: "Deux pistes : vous, et les autres.") {
                    session.entree = .doublePiste
                    Task { await session.demarrerEnregistrement() }
                }
                CarteChoix(icone: "text.alignleft", titre: "Coller un transcript",
                           detail: "Ou déposez le fichier sur la fenêtre.") {
                    session.entree = .collage
                    colle = true
                }
                // Toutes les réunions ne s'enregistrent pas : un déjeuner, un
                // entretien, une séance où sortir un micro serait déplacé. Des
                // notes recopiées valent mieux que rien.
                CarteChoix(icone: "pencil.line", titre: "Partir de vos notes",
                           detail: "Prises à la main, même incomplètes.") {
                    session.entree = .notes
                    colle = true
                }
            }
            .frame(maxWidth: 780)
        }
    }

    private var saisie: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $session.transcript)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Teinte.carte,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Teinte.trait))
                .frame(height: 260)
            // Ces deux actions font sortir de l'écran : en texte cliquable,
            // elles se lisaient comme une note de bas de page et ne se
            // remarquaient pas.
            HStack(spacing: 10) {
                Text(session.transcript.isEmpty
                     ? (session.entree == .notes
                        ? "Recopiez vos notes, même abrégées. Rien ne sera comblé : "
                          + "ce qui manque vous sera demandé."
                        : "Collez le verbatim, ou déposez le fichier sur la fenêtre.")
                     : "\(session.motsDuTranscript) mots.")
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                Spacer()
                // Le glisser-déposer ne suffit pas : un fichier rangé dans un
                // dossier fermé ne se glisse pas sans aller le chercher.
                BoutonDiscret(titre: "Ouvrir un fichier…", icone: "folder") {
                    ouvrirUnTranscript()
                }
                BoutonDiscret(titre: session.transcript.isEmpty
                              ? "Revenir aux choix" : "Repartir de zéro",
                              icone: session.transcript.isEmpty
                              ? "arrow.left" : "arrow.counterclockwise") {
                    colle = false
                    session.transcript = ""
                    session.messageCapture = nil
                }
            }
            if let audio = session.dernierEnregistrement {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").font(.system(size: 10))
                        .foregroundStyle(Teinte.texteFaible)
                    Text("Cet enregistrement est conservé : \(audio)")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    BoutonDiscret(titre: "Le montrer", icone: "folder") {
                        session.montrerLEnregistrement()
                    }
                }
            }
        }
        .frame(maxWidth: 640)
        .padding(.top, 24)
    }

    /// Choisir un transcript dans le Finder. Reprend le même comportement que
    /// le dépôt : le dossier du fichier propose le nom du projet.
    private func ouvrirUnTranscript() {
        let panneau = NSOpenPanel()
        panneau.allowsMultipleSelection = false
        panneau.canChooseDirectories = false
        panneau.message = "Choisissez le transcript de la réunion."
        panneau.prompt = "Ouvrir"
        guard panneau.runModal() == .OK, let url = panneau.url,
              let texte = try? String(contentsOf: url, encoding: .utf8) else { return }
        session.transcript = texte
        if session.projet.isEmpty {
            session.projet = url.deletingLastPathComponent().lastPathComponent
        }
        session.rafraichirLeContexte()
        colle = true
    }

    private var pied: some View {
        HStack(spacing: 14) {
            if let message = session.messageCapture {
                VStack(alignment: .trailing, spacing: 6) {
                    // La transcription sait exactement où elle en est : la
                    // place du dernier mot reconnu dans l'enregistrement.
                    if let ou = session.avancement {
                        BarreProgression(fraction: ou, largeur: 240)
                    }
                    Text(message).font(.system(size: 12)).foregroundStyle(Teinte.texteFaible)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    if session.autorisationManquante {
                        HStack(spacing: 12) {
                            BoutonDiscret(titre: "Ouvrir les réglages",
                                          icone: "gearshape") {
                                session.ouvrirLesReglagesSysteme()
                            }
                            BoutonDiscret(titre: "Quitter et rouvrir Greffier",
                                          icone: "arrow.clockwise") {
                                session.relancerLApplication()
                            }
                        }
                    }
                }
                .frame(maxWidth: 470, alignment: .trailing)
            } else if session.enregistrementEnCours {
                Text("Vous pouvez fermer cette fenêtre : l'enregistrement continue, "
                     + "et l'icône de la barre de menus le montre.")
                    .font(.system(size: 12)).foregroundStyle(Teinte.texteFaible)
            } else {
                Text("Aucune réunion en cours dans votre calendrier.")
                    .font(.system(size: 12)).foregroundStyle(Teinte.texteFaible)
            }

            if !session.enregistrementEnCours {
                BoutonPrincipal(titre: "Analyser la réunion", actif: session.pretAAnalyser) {
                    Task { await session.lancerAnalyse() }
                }
            }
        }
        .padding(.horizontal, 34).padding(.vertical, 20)
    }
}

/// L'onde qui bat pendant l'enregistrement. Elle ne s'anime **que** là : sur un
/// outil qu'on garde ouvert toute la journée, une animation permanente
/// fatiguerait — et l'animation devient alors un signal, pas une décoration.
struct OndeAnimee: View {
    @State private var phase = false
    private let hauteurs: [CGFloat] = [18, 38, 26, 52, 30, 44, 22, 34, 16]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(hauteurs.enumerated()), id: \.offset) { i, h in
                Capsule()
                    .fill(Teinte.bleuClair)
                    .frame(width: 5, height: phase ? h : h * 0.45)
                    .animation(.easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.07), value: phase)
            }
        }
        .onAppear { phase = true }
    }
}

/// L'onde de la marque, immobile, pour les écrans au repos.
struct OndeDecorative: View {
    var hauteurs: [CGFloat] = [16, 30, 22, 42, 26, 36, 18, 28, 14]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(hauteurs.enumerated()), id: \.offset) { _, h in
                Capsule().fill(Teinte.bleuClair).frame(width: 4, height: h)
            }
        }
    }
}

// MARK: - Colonne des dossiers

struct ColonneDossiers: View {
    @Bindable var session: Session
    @State private var details = false
    @State private var confirmeRecommencer = false
    @State private var archivesOuvertes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Marque()
                Text("Greffier").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Teinte.texte)
                Spacer()
                BasculeApparence(reglages: session.reglages)
            }
            .padding(.horizontal, 14).padding(.top, 42).padding(.bottom, 16)

            Button {
                // Un compte rendu produit mais pas encore enregistré n'existe
                // qu'en mémoire : l'effacer d'un clic imposerait de tout
                // recommencer, questions comprises.
                if session.travailNonEnregistre && !confirmeRecommencer {
                    confirmeRecommencer = true
                    return
                }
                confirmeRecommencer = false
                session.recommencer()
                details = true
            } label: {
                Text(confirmeRecommencer
                     ? "Effacer le compte rendu en cours ?"
                     : "＋  Nouveau compte rendu")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Teinte.degradeBouton,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: Teinte.bleu.opacity(0.3), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .popover(isPresented: $details, arrowEdge: .trailing) {
                VueDetails(session: session, affiche: $details)
            }

            BoutonDiscret(titre: "Mes comptes rendus", icone: "magnifyingglass",
                          pleineLargeur: true) {
                archivesOuvertes = true
            }
            .padding(.horizontal, 14).padding(.top, 12)
            .sheet(isPresented: $archivesOuvertes) {
                VueArchives(racine: session.racineDuProjet,
                            charte: session.charte,
                            surTitre: session.reglages.identite.societe,
                            avertirDeLaPerte: session.travailNonEnregistre) {
                    reunion, contenu in
                    session.rouvrir(reunion, projet: projetDe(reunion), contenu: contenu)
                }
            }

            Intertitre(texte: "Dossiers").padding(.horizontal, 14).padding(.top, 22).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(session.dossiers, id: \.nom) { dossier in
                        LigneDossier(nom: dossier.nom, nombre: dossier.nombre,
                                     actif: dossier.nom == session.projet) {
                            session.choisirDossier(dossier.nom)
                        }
                    }
                    if session.dossiers.isEmpty {
                        Text("Aucun dossier pour l'instant. Le premier compte rendu en créera un.")
                            .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                            .padding(.horizontal, 14)
                    }
                }
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panneau()
    }
}

extension ColonneDossiers {
    /// Le nom du client se lit dans le chemin : le dossier de la réunion vit
    /// dans celui du projet.
    func projetDe(_ reunion: Rangement.Reunion) -> String {
        reunion.dossier.deletingLastPathComponent().lastPathComponent
    }
}

struct LigneDossier: View {
    let nom: String
    let nombre: Int
    let actif: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle().fill(Teinte.bleuClair.opacity(actif ? 0.9 : 0.5))
                    .frame(width: 6, height: 6)
                Text(nom).font(.system(size: 12.5, weight: actif ? .semibold : .regular))
                    .foregroundStyle(actif ? Teinte.texte : Teinte.texteDoux)
                Spacer()
                Text("\(nombre)").font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(actif ? Teinte.survol : .clear)
            .overlay(alignment: .leading) {
                if actif { Rectangle().fill(Teinte.bleu).frame(width: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flanc du dossier

/// Ce que l'outil sait déjà. C'est ici que le mécanisme se montre : sans ce
/// panneau, on ne voit jamais pourquoi le dixième compte rendu d'un dossier
/// demande moins d'efforts que le premier.
struct FlancDuDossier: View {
    @Bindable var session: Session
    @State private var lexiqueOuvert = false
    @State private var enregistrementsOuverts = false
    @State private var consignesOuvertes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Intertitre(texte: "Ce dossier")
                    Spacer()
                    if !session.projet.isEmpty {
                        BoutonDiscret(titre: "Ouvrir", icone: "folder") {
                            session.montrerLeDossier()
                        }
                    }
                }
                .padding(.bottom, 14)

                if session.comptesRendusAnterieurs.isEmpty {
                    Text(session.projet.isEmpty
                         ? "Choisissez un dossier à gauche, ou nommez-en un nouveau."
                         : "Premier compte rendu de ce dossier.")
                        .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(session.comptesRendusAnterieurs, id: \.titre) { cr in
                        // La carte entière était cliquable, sans que rien ne le
                        // dise : ce qu'on peut faire d'un compte rendu doit
                        // s'annoncer en boutons, ici comme ailleurs.
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cr.titre).font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Teinte.texte)
                                .multilineTextAlignment(.leading)
                            Text(cr.apercu).font(.system(size: 11))
                                .foregroundStyle(Teinte.texteFaible).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 7) {
                                BoutonDiscret(titre: cr.pdf != nil ? "PDF" : "Ouvrir",
                                              icone: "doc.richtext") {
                                    session.ouvrir(cr)
                                }
                                BoutonDiscret(titre: "Word", icone: "arrow.up.doc") {
                                    session.exporterEnWord(cr)
                                }
                                .help("Écrit un document Word de ce compte rendu, "
                                      + "dans son dossier.")
                                Spacer(minLength: 0)
                            }
                            .padding(.top, 7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Teinte.carte,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Teinte.trait))
                        .padding(.bottom, 9)
                    }
                    Text("Ils seront relus pour la continuité, et pour repérer une contradiction.")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Rectangle().fill(Teinte.trait).frame(height: 1).padding(.vertical, 20)

                HStack {
                    Intertitre(texte: "Consignes")
                    Spacer()
                    BoutonDiscret(titre: "Régler", icone: "slider.horizontal.3") {
                        consignesOuvertes = true
                    }
                    .help("Ce que Greffier doit savoir pour ce dossier en particulier.")
                }
                .padding(.bottom, 8)
                Text(session.consignesDuDossier.estVide
                     ? "Aucune consigne propre à ce dossier."
                     : session.consignesDuDossier.texte)
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(Teinte.trait).frame(height: 1).padding(.vertical, 20)

                HStack {
                    Intertitre(texte: "Les enregistrements")
                    Spacer()
                    BoutonDiscret(titre: "Voir", icone: "waveform") {
                        enregistrementsOuverts = true
                    }
                    .help("Les enregistrements sans compte rendu, et l'audio conservé.")
                }
                .padding(.bottom, 12)

                Rectangle().fill(Teinte.trait).frame(height: 1).padding(.vertical, 20)

                HStack {
                    Intertitre(texte: "Le lexique")
                    Spacer()
                    // « Consulter » ne tenait pas à côté de l'intitulé dans une
                    // colonne de 214 points utiles.
                    BoutonDiscret(titre: "Voir", icone: "book") {
                        lexiqueOuvert = true
                    }
                    .help("Consulter le lexique : les termes retenus de vos réponses.")
                }
                .padding(.bottom, 12)
                ligne("Termes acquis", "\(session.lexiqueTotal)")
                ligne("Retenus pour ce transcript", "\(session.lexiqueRetenu)")
                Text(session.apercuLexique)
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18).padding(.top, 42).padding(.bottom, 22)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panneau(bordureGauche: true)
        .sheet(isPresented: $lexiqueOuvert) {
            VueLexique(racine: session.racineDuProjet)
        }
        .sheet(isPresented: $consignesOuvertes) {
            VueConsignes(projet: session.projet,
                         identite: session.reglages.identite,
                         texte: session.consignesDuDossier.texte) { texte in
                let consignes = ConsignesDossier(texte: texte)
                try? consignes.enregistrer(racine: session.racineDuProjet,
                                           projet: session.projet)
                session.consignesDuDossier = consignes
            }
        }
        .sheet(isPresented: $enregistrementsOuverts) {
            VueEnregistrements(racine: session.racineDuProjet) { url in
                Task { await session.transcrireUnOrphelin(url) }
            }
        }
    }

    private func ligne(_ intitule: String, _ valeur: String) -> some View {
        HStack {
            Text(intitule).foregroundStyle(Teinte.texteDoux)
            Spacer()
            Text(valeur).foregroundStyle(Teinte.texte).fontWeight(.medium)
        }
        .font(.system(size: 12))
        .padding(.vertical, 5)
    }
}
