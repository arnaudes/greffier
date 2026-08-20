import AVFoundation
import SwiftUI
import NoyauCR

struct VueReglages: View {
    @Bindable var reglages: Reglages
    @State private var calendriersDisponibles: [String] = []
    @State private var etatTranscription = Transcription.etatDuMoteur()
    @State private var etatMicro = Capture.etatDuMicro
    @State private var reponseDemande: String?
    @State private var cheminClaudeTrouve: String?
    @State private var promptVisible = false

    var body: some View {
        TabView {
            VueEtat(reglages: reglages)
                .tabItem { Label("État", systemImage: "checkmark.seal") }
            identite.tabItem { Label("Vous", systemImage: "person.crop.circle") }
            calendriers.tabItem { Label("Calendrier", systemImage: "calendar") }
            claude.tabItem { Label("Rédaction", systemImage: "text.bubble") }
            enregistrements.tabItem { Label("Enregistrements", systemImage: "waveform") }
            apparence.tabItem { Label("Apparence", systemImage: "circle.lefthalf.filled") }
            VueCharte(racine: reglages.dossierDeTravail,
                      surTitre: reglages.identite.societe)
                .tabItem { Label("Charte", systemImage: "paintpalette") }
            dossier.tabItem { Label("Dossier", systemImage: "folder") }
        }
        .frame(width: 580, height: 520)
        .task {
            calendriersDisponibles = Calendrier.calendriersDisponibles()
            chercherLeProgramme()
        }
    }

    // MARK: - Calendrier

    private var calendriers: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            Text("De quels calendriers Greffier doit-il tenir compte ?").font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)
            Text("Ne cochez que vos calendriers professionnels. Sans ce tri, l'outil "
                 + "vous proposerait d'enregistrer les jours fériés et les anniversaires.")
                .font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)

            if calendriersDisponibles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Greffier ne voit pas encore vos calendriers.").font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)
                    BoutonDiscret(titre: "Autoriser l'accès au calendrier", icone: "calendar") {
                        Task {
                            _ = await Calendrier.autoriser()
                            calendriersDisponibles = Calendrier.calendriersDisponibles()
                        }
                    }
                }
                .padding(.top, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calendriersDisponibles, id: \.self) { nom in
                            Toggle(nom, isOn: Binding(
                                get: { reglages.calendriersRetenus.contains(nom) },
                                set: { garde in
                                    if garde { reglages.calendriersRetenus.insert(nom) }
                                    else { reglages.calendriersRetenus.remove(nom) }
                                }))
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        }
    }

    // MARK: - Rédaction

    private var claude: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            Text("Quel modèle rédige vos comptes rendus ?").font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)
            Text("Laissez vide pour employer celui de votre session Claude Code. "
                 + "Les deux étapes qui passent par Claude — repérer les ambiguïtés du "
                 + "verbatim, puis rédiger — sont les plus exigeantes de la chaîne.")
                .font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)

            VStack(alignment: .leading, spacing: 3) {
                Text("Modèle").font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)
                TextField("celui de la session", text: $reglages.modele)
                    .champGreffier()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Modèle de repli").font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)
                TextField("aucun", text: $reglages.modeleRepli)
                    .champGreffier()
                Text("Employé quand la limite du forfait est atteinte. Sans lui, la "
                     + "rédaction s'interrompt en cours de route.")
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text("Le programme Claude Code").font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)
                TextField("détecté automatiquement", text: $reglages.cheminClaude)
                    .champGreffier()
                    .onSubmit { chercherLeProgramme() }
                if let trouve = cheminClaudeTrouve {
                    Label("Trouvé ici : \(trouve)", systemImage: "checkmark.circle")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                        .textSelection(.enabled)
                } else {
                    Label {
                        Text("Introuvable. Tapez « which claude » dans un terminal et "
                             + "recopiez ici le chemin obtenu.").font(.system(size: 11))
                            .foregroundStyle(Teinte.texteDoux)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().overlay(Teinte.trait)

            Toggle("Me prévenir quand une version plus récente est publiée",
                   isOn: $reglages.previenirDesMisesAJour)
                .toggleStyle(.switch).tint(Teinte.bleu)
            Text("Greffier interroge alors son dépôt public une fois par jour, sans rien "
                 + "envoyer. Il ne se met jamais à jour tout seul : il prévient, vous "
                 + "installez.")
                .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                .fixedSize(horizontal: false, vertical: true)


            Label("La rédaction passe par votre abonnement Claude Code, jamais par une "
                  + "facturation séparée.", systemImage: "checkmark.seal")
                .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
            Spacer()
        }
        .padding(20)
        }
    }

    /// Où le programme a été trouvé — ou rien du tout. Une application lancée
    /// depuis le Finder ne voit pas les mêmes dossiers qu'un terminal : le dire
    /// ici évite d'avoir à le découvrir en pleine rédaction.
    ///
    /// La recherche n'est relancée qu'à l'ouverture et quand le champ est
    /// validé : la reprendre à chaque frappe interrogerait le système pour des
    /// chemins à moitié tapés.
    private func chercherLeProgramme() {
        let voulu = reglages.cheminClaude.trimmingCharacters(in: .whitespaces)
        cheminClaudeTrouve = LocalisationClaude.resoudre(voulu.isEmpty ? "claude" : voulu)
    }

    // MARK: - Apparence

    private var dossier: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            Text("Où sont rangés vos comptes rendus ?")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)
            Text("Ce dossier contient les comptes rendus, le lexique et les "
                 + "enregistrements en attente. Il vit hors du code de l'application : "
                 + "vos documents ne dépendent donc pas de l'endroit où celle-ci est "
                 + "installée.")
                .font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Text(reglages.dossierDeTravail.path)
                    .font(.system(size: 11.5).monospaced())
                    .foregroundStyle(Teinte.texte)
                    .textSelection(.enabled)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                BoutonDiscret(titre: "Choisir…", icone: "folder") { choisirLeDossier() }
                BoutonDiscret(titre: "Ouvrir", icone: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(reglages.dossierDeTravail)
                }
            }

            Label("Changer de dossier ne déplace rien : les documents déjà produits "
                  + "restent où ils sont. Quittez et rouvrez Greffier pour que le nouveau "
                  + "dossier soit pris en compte.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(Teinte.ambre)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(20)
        }
    }

    /// Le sélecteur de dossier du système : l'utilisateur désigne lui-même
    /// l'endroit, ce qui vaut aussi autorisation d'y écrire.
    private func choisirLeDossier() {
        let panneau = NSOpenPanel()
        panneau.canChooseDirectories = true
        panneau.canChooseFiles = false
        panneau.canCreateDirectories = true
        panneau.allowsMultipleSelection = false
        panneau.directoryURL = reglages.dossierDeTravail
        panneau.message = "Choisissez le dossier où ranger vos comptes rendus."
        panneau.prompt = "Utiliser ce dossier"
        guard panneau.runModal() == .OK, let url = panneau.url else { return }
        reglages.dossierDeTravail = url
    }

    /// Qui vous êtes — le réglage qui décide de la justesse des comptes rendus.
    ///
    /// Ces informations étaient dans le code : l'application était écrite pour
    /// une personne et une société. Le champ « ce que fait votre société » est
    /// celui qui compte le plus : sans lui, Claude ignore ce qu'est un
    /// livrable, un jalon ou une réserve dans votre métier, et le compte rendu
    /// devient plat sans qu'on sache pourquoi.
    private var identite: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Qui rédige ces comptes rendus ?")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)

                if !reglages.identite.incomplet.isEmpty {
                    Label("Il manque " + reglages.identite.incomplet.joined(separator: ", ")
                          + ". Les comptes rendus s'en ressentiront.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Teinte.ambre)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    champIdentite("Votre nom", $reglages.identite.nom,
                                  aide: "Sert aussi à vous reconnaître en visioconférence.")
                    champIdentite("Votre fonction", $reglages.identite.fonction)
                }
                champIdentite("Votre société", $reglages.identite.societe)

                zoneIdentite("Ce que fait votre société",
                             $reglages.identite.activite,
                             exemple: "Nous fabriquons des menuiseries sur mesure : "
                                    + "nous concevons, nous posons, et nous assurons "
                                    + "le service après-vente.",
                             aide: "En une ou deux phrases. C'est ce qui permet à Claude de "
                                 + "distinguer un livrable d'une intention, et une réserve "
                                 + "d'un simple commentaire.")

                zoneIdentite("Ce qui ne sort jamais au client",
                             $reglages.identite.jamaisAuClient,
                             exemple: "Tarifs journaliers, estimations de charge, réserves "
                                    + "sur le client, organisation interne.",
                             aide: "Ces points resteront dans le compte rendu interne et "
                                 + "seront écartés de l'email client.")

                Divider().overlay(Teinte.trait)

                Text("Votre façon de rédiger")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)
                zoneIdentite("Ce qu'il faut savoir de votre métier",
                             $reglages.identite.consignesMetier,
                             exemple: "Nos réunions comportent toujours un point sécurité. "
                                    + "Distingue les jalons contractuels des jalons "
                                    + "indicatifs.",
                             aide: "Porte sur le fond, là où la charte porte sur la forme. "
                                 + "C'est ce qui manque le plus souvent, et qu'aucune "
                                 + "description d'activité ne capture.")

                zoneIdentite("Charte rédactionnelle", $reglages.identite.charte,
                             exemple: "Vouvoiement. Des paragraphes courts. Un tableau pour "
                                    + "les actions, jamais ailleurs.",
                             aide: "Ces préférences portent sur la forme. Elles ne peuvent "
                                 + "jamais conduire à inventer, à trancher à votre place ou "
                                 + "à taire un désaccord : ces règles-là ne se règlent pas.")

                Divider().overlay(Teinte.trait)
                BoutonDiscret(titre: "Voir ce que Claude reçoit", icone: "eye") {
                    promptVisible = true
                }
                Text("L'effet de ces champs est invisible tant qu'un compte rendu n'a pas "
                     + "été produit. Ce bouton montre les consignes exactes qui seront "
                     + "envoyées.")
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(20)
        }
        .sheet(isPresented: $promptVisible) {
            VuePrompt(identite: reglages.identite) { promptVisible = false }
        }
    }

    private func champIdentite(_ titre: String, _ valeur: Binding<String>,
                               aide: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
            TextField("", text: valeur).champGreffier()
            if let aide {
                Text(aide).font(.system(size: 10.5)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func zoneIdentite(_ titre: String, _ valeur: Binding<String>,
                              exemple: String, aide: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
            TextField(exemple, text: valeur, axis: .vertical)
                .lineLimit(2...5).champGreffier()
            Text(aide).font(.system(size: 10.5)).foregroundStyle(Teinte.texteFaible)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var apparence: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            Text("Quelle tenue pour Greffier ?").font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)
            Text("La tenue sombre est celle d'origine : l'application vit à côté d'une "
                 + "visioconférence, et un fond clair fatigue en fin de journée. La tenue "
                 + "claire rend la main quand la pièce est en plein soleil.")
                .font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $reglages.apparence) {
                ForEach(Reglages.Apparence.allCases) { tenue in
                    Label(tenue.libelle, systemImage: tenue.symbole).tag(tenue)
                }
            }
            .pickerStyle(.inline).labelsHidden()

            Text("La bascule se trouve aussi en haut de la colonne des dossiers, à côté "
                 + "du nom de l'application : elle passe du sombre au clair sans ouvrir "
                 + "cette fenêtre.")
                .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(20)
        }
    }

    // MARK: - Enregistrements

    /// Ce qu'on fait des enregistrements une fois le compte rendu produit.
    ///
    /// L'état du micro et de la transcription figurait ici, **figé à
    /// l'ouverture de la fenêtre** : accorder une autorisation puis revenir
    /// laissait un état faux à l'écran. L'onglet « État » dit la même chose et
    /// se rafraîchit — deux endroits qui se contredisent valent moins qu'un
    /// seul qui a raison.
    private var enregistrements: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Que deviennent vos enregistrements ?")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)

                Toggle("Conserver les enregistrements après la transcription",
                       isOn: $reglages.conserverLesEnregistrements)
                    .toggleStyle(.switch).tint(Teinte.bleu)
                Text("Conservés, ils sont rangés avec le compte rendu et compressés : "
                     + "une réunion de trente minutes occupe une trentaine de mégaoctets "
                     + "au lieu de neuf cents. Le transcript corrigé suffit le plus "
                     + "souvent — mais un enregistrement effacé ne se retrouve jamais.")
                    .font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Teinte.trait)

                Text("La transcription se fait sur cet ordinateur : le son d'une réunion "
                     + "ne part jamais sur un serveur. Le transcript, lui, est envoyé à "
                     + "Claude pour la rédaction.")
                    .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)

                Text("L'état du micro, de la dictée et de la reconnaissance vocale se "
                     + "consulte dans l'onglet « État ».")
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                Spacer()
            }
            .padding(20)
        }
    }

    private func ligne(_ intitule: String, _ valeur: String) -> some View {
        GridRow {
            Text(intitule).font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)
            Text(valeur).font(.callout.weight(.medium))
        }
    }
}
