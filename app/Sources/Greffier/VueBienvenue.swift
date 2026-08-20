import AppKit
import SwiftUI
import NoyauCR

/// Le premier lancement, pris par la main du début à la fin.
///
/// Les pièces existaient toutes — les huit conditions vérifiées, l'écran
/// d'identité, les demandes d'autorisation — mais **personne ne les mettait
/// bout à bout**. L'arrivant découvrait qu'il fallait Claude Code au moment où
/// la rédaction échouait, la dictée au moment où la transcription rendait une
/// page blanche, et l'importance de son identité jamais.
///
/// L'ordre n'est pas décoratif : d'abord ce qui décide de la qualité du compte
/// rendu, puis ce qui ferait perdre une réunion, puis ce dont on peut se
/// passer. Chaque étape dit ce qu'on perd sans elle, et porte le bouton qui la
/// règle — on ne renvoie jamais l'utilisateur chercher ailleurs sans lui ouvrir
/// la porte.
struct VueBienvenue: View {
    @Bindable var reglages: Reglages
    /// Ce qu'on fait quand le parcours est terminé, ou qu'on le laisse de côté.
    var terminer: () -> Void

    @State private var prerequis: Prerequis?
    @State private var verdictClaude: EpreuveClaude.Verdict?
    @State private var epreuveEnCours = false
    @State private var enCours: Prerequis.Condition?
    @State private var identiteOuverte = false
    @Environment(\.openSettings) private var ouvrirLesReglages

    /// Les conditions présentées, dans l'ordre où on les règle.
    ///
    /// Le calendrier et Chrome viennent en dernier : on peut travailler des
    /// mois sans eux, et les présenter tôt donnerait à croire qu'ils comptent
    /// autant que le micro.
    private let etapes: [Prerequis.Condition] = [
        .dictee, .micro, .reconnaissance, .dossier, .ecran, .calendrier, .chrome,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                entete
                bloc(numero: 1, titre: "Présentez-vous",
                     satisfait: reglages.identite.incomplet.isEmpty) { identite }
                bloc(numero: 2, titre: "Claude Code",
                     satisfait: verdictClaude?.satisfait ?? false) { claude }
                bloc(numero: 3, titre: "Ce que Greffier doit pouvoir faire",
                     satisfait: prerequis?.peutEnregistrer ?? false) { conditions }
                bloc(numero: 4, titre: "Un premier essai", satisfait: false) { essai }
                pied
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
        .background(Teinte.fond)
        .task { verifier() }
    }

    // MARK: - L'en-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Marque(cote: 30)
                Text("Bienvenue dans Greffier")
                    .font(.system(size: 21, weight: .semibold)).foregroundStyle(Teinte.texte)
                Spacer()
                BasculeApparence(reglages: reglages)
            }
            Text("Greffier transforme une réunion en compte rendu. Quatre choses à "
                 + "régler une fois pour toutes, et vous n'y reviendrez plus.")
                .font(.system(size: 13)).foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 26)
    }

    /// Un bloc d'étape : son numéro, son titre, et son contenu.
    private func bloc<Contenu: View>(numero: Int, titre: String, satisfait: Bool,
                                     @ViewBuilder contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(satisfait ? Teinte.vert.opacity(0.18) : Teinte.carteVive)
                        .frame(width: 24, height: 24)
                    if satisfait {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Teinte.vert)
                    } else {
                        Text("\(numero)").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Teinte.texteDoux)
                    }
                }
                Text(titre).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Teinte.texte)
            }
            contenu().padding(.leading, 34)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 30)
    }

    // MARK: - 1. L'identité

    private var identite: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("C'est ce qui décide de la justesse de vos comptes rendus, et son "
                 + "absence ne se voit nulle part ailleurs : sans savoir ce que fait "
                 + "votre société, Greffier ignore ce qu'est un livrable, un jalon ou "
                 + "une réserve dans votre métier — et le compte rendu devient plat "
                 + "sans qu'on comprenne pourquoi.")
                .font(.system(size: 12.5)).foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)

            if reglages.identite.incomplet.isEmpty {
                mention(vert: true,
                        "Vous êtes \(reglages.identite.signature).")
            } else {
                mention(vert: false,
                        "Il manque " + reglages.identite.incomplet.joined(separator: ", ") + ".")
            }
            BoutonPrincipal(titre: reglages.identite.incomplet.isEmpty
                            ? "Revoir ma fiche" : "Me présenter",
                            icone: "person.crop.circle") {
                identiteOuverte = true
            }
        }
        .sheet(isPresented: $identiteOuverte) {
            VueIdentiteRapide(reglages: reglages, fermer: { identiteOuverte = false })
        }
    }

    // MARK: - 2. Claude Code

    private var claude: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("La rédaction passe par votre abonnement Claude Code : il n'y a pas "
                 + "de facturation séparée. Sans lui, Greffier enregistre et "
                 + "transcrit, mais ne rédige pas.")
                .font(.system(size: 12.5)).foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)

            if epreuveEnCours {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Greffier lui pose une question et attend la réponse…")
                        .font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)
                }
            } else if let verdictClaude {
                mention(vert: verdictClaude.satisfait, verdictClaude.libelle)
                if !verdictClaude.remede.isEmpty {
                    Text(verdictClaude.remede)
                        .font(.system(size: 12)).foregroundStyle(Teinte.texteFaible)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Vérifier prend quelques secondes : c'est le seul moyen de "
                     + "distinguer « installé » d'« utilisable ». Un programme "
                     + "présent mais non connecté échouerait en pleine rédaction, "
                     + "après la réunion.")
                    .font(.system(size: 12)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 9) {
                BoutonPrincipal(titre: verdictClaude == nil ? "Vérifier" : "Vérifier à nouveau",
                                icone: "checkmark.seal", actif: !epreuveEnCours) {
                    eprouverClaude()
                }
                if verdictClaude?.satisfait == false {
                    BoutonDiscret(titre: "Ouvrir le Terminal", icone: "terminal") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                    }
                }
            }
        }
    }

    // MARK: - 3. Les conditions de la machine

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chacune se demande à la première utilisation. Les régler "
                 + "maintenant évite de les découvrir pendant une réunion.")
                .font(.system(size: 12.5)).foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)

            if let prerequis {
                ForEach(etapes, id: \.self) { condition in
                    ligne(condition, etat: prerequis.etat(condition))
                }
            }
            BoutonDiscret(titre: "Revérifier", icone: "arrow.clockwise") { verifier() }
        }
    }

    private func ligne(_ condition: Prerequis.Condition,
                       etat: Prerequis.Etat) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: etat.satisfait ? "checkmark.circle.fill"
                  : (condition.faitPerdreLaReunion ? "exclamationmark.circle" : "circle"))
                .font(.system(size: 13))
                .foregroundStyle(etat.satisfait ? Teinte.vert
                                 : (condition.faitPerdreLaReunion ? Teinte.ambre
                                    : Teinte.texteFaible))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(condition.titre).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Teinte.texte)
                    if !condition.faitPerdreLaReunion && !etat.satisfait {
                        Etiquette(texte: "facultatif", couleur: Teinte.texteFaible)
                    }
                }
                Text(etat.satisfait ? condition.role : condition.consequence)
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            if !etat.satisfait {
                HStack(spacing: 7) {
                    if enCours == condition {
                        ProgressView().controlSize(.small)
                    } else if condition.peutSeDemander {
                        BoutonDiscret(titre: "Autoriser") { demander(condition) }
                    }
                    if let ou = Prerequis.reglagesSysteme(condition) {
                        BoutonDiscret(titre: "Réglages") { NSWorkspace.shared.open(ou) }
                    }
                    if condition == .dossier {
                        BoutonDiscret(titre: "Choisir") { choisirLeDossier() }
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - 4. Le premier essai

    private var essai: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enregistrez deux minutes au micro plutôt qu'une vraie réunion : "
                 + "vous verrez les questions arriver, et le lexique se remplir de "
                 + "vos réponses. C'est ce mécanisme qui fait que le dixième compte "
                 + "rendu d'un client demande moins d'efforts que le premier.")
                .font(.system(size: 12.5)).foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
            Text("Rien n'est envoyé nulle part pendant l'enregistrement : le son est "
                 + "transcrit sur cet ordinateur. Seul le texte part à Claude, pour "
                 + "la rédaction.")
                .font(.system(size: 12)).foregroundStyle(Teinte.texteFaible)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Le pied

    private var pied: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Teinte.trait).frame(height: 1)
            HStack(spacing: 12) {
                BoutonPrincipal(titre: "Commencer", icone: "arrow.right") {
                    reglages.accueilFait = true
                    terminer()
                }
                BoutonDiscret(titre: "Régler plus tard") {
                    reglages.accueilFait = true
                    terminer()
                }
                Spacer()
                BoutonDiscret(titre: "Tous les réglages", icone: "gearshape") {
                    ouvrirLesReglages()
                }
            }
            Text("Cet écran ne reviendra plus. Tout ce qu'il contient se retrouve "
                 + "dans les réglages, onglets « Vous » et « État ».")
                .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
        }
    }

    // MARK: - Pièces communes

    private func mention(vert: Bool, _ texte: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: vert ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(vert ? Teinte.vert : Teinte.ambre)
            Text(texte).font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func verifier() {
        prerequis = Prerequis.verifier(
            cheminClaude: reglages.cheminClaude.isEmpty ? "claude" : reglages.cheminClaude,
            dossierDeTravail: reglages.dossierDeTravail)
    }

    private func demander(_ condition: Prerequis.Condition) {
        Task {
            enCours = condition
            _ = await Prerequis.demander(condition)
            enCours = nil
            verifier()
        }
    }

    private func eprouverClaude() {
        Task {
            epreuveEnCours = true
            verdictClaude = await EpreuveClaude.eprouver(config: reglages.configClaude)
            epreuveEnCours = false
            verifier()
        }
    }

    /// Le sélecteur du système : désigner le dossier vaut aussi autorisation
    /// d'y écrire.
    private func choisirLeDossier() {
        let panneau = NSOpenPanel()
        panneau.canChooseDirectories = true
        panneau.canChooseFiles = false
        panneau.message = "Choisissez le dossier où ranger vos comptes rendus."
        panneau.prompt = "Utiliser ce dossier"
        panneau.directoryURL = reglages.dossierDeTravail
        if panneau.runModal() == .OK, let choisi = panneau.url {
            reglages.dossierDeTravail = choisi
            verifier()
        }
    }
}

/// Se présenter sans quitter le parcours.
///
/// Les mêmes champs que l'onglet « Vous », mais posés à l'endroit où la
/// question se pose — un renvoi vers un onglet de réglages, au premier
/// lancement, est un renvoi que personne ne suit.
struct VueIdentiteRapide: View {
    @Bindable var reglages: Reglages
    var fermer: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Qui rédige ces comptes rendus ?")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Teinte.texte)

                champ("Votre nom", $reglages.identite.nom,
                      aide: "Sert aussi à vous reconnaître en visioconférence.")
                champ("Votre fonction", $reglages.identite.fonction, aide: "")
                champ("Votre société", $reglages.identite.societe, aide: "")

                zone("Ce que fait votre société", $reglages.identite.activite,
                     aide: "En une ou deux phrases. C'est ce qui permet de distinguer "
                         + "un livrable d'une intention, et une réserve d'un simple "
                         + "commentaire.")
                zone("Ce qui ne sort jamais au client", $reglages.identite.jamaisAuClient,
                     aide: "Ces points restent dans le compte rendu interne et sont "
                         + "écartés de l'email client.")

                HStack(spacing: 10) {
                    Spacer()
                    BoutonPrincipal(titre: "Enregistrer", icone: "checkmark") { fermer() }
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 540)
        .background(Teinte.fondUni)
    }

    private func champ(_ titre: String, _ valeur: Binding<String>,
                       aide: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
            TextField("", text: valeur).champGreffier()
            if !aide.isEmpty {
                Text(aide).font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func zone(_ titre: String, _ valeur: Binding<String>,
                      aide: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
            TextEditor(text: valeur)
                .font(.system(size: 12.5)).scrollContentBackground(.hidden)
                .frame(height: 62).padding(6)
                .background(Teinte.carte,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Teinte.trait))
            Text(aide).font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
