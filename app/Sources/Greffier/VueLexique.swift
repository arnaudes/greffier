import SwiftUI
import NoyauCR

/// Le lexique, consultable et modifiable.
///
/// Il n'était visible que par un compteur, puis seulement supprimable — si bien
/// qu'une entrée fausse ne pouvait qu'être perdue, jamais corrigée. Le
/// « Menuiserie Vidal » y figurait deux fois, sous deux graphies, avec une note juste
/// et utile qu'il aurait fallu détruire pour corriger le nom.
///
/// C'est ici que se répare une erreur validée une fois, avant qu'elle ne
/// contamine tous les comptes rendus suivants.
struct VueLexique: View {
    let racine: URL
    @State private var lexique = Lexique()
    @State private var recherche = ""
    @State private var enCoursDeSuppression: String?
    @State private var enEdition: String?
    @State private var brouillon = Brouillon()
    @Environment(\.dismiss) private var fermer

    private var url: URL { racine.appendingPathComponent("lexique/lexique.json") }

    /// Une entrée en cours de saisie. Les variantes se tapent séparées par des
    /// virgules : c'est ainsi qu'on les lit, et une liste à puces pour trois
    /// mots serait disproportionnée.
    private struct Brouillon {
        var terme = ""
        var variantes = ""
        var categorie: Categorie = .entreprise
        var note = ""
        /// Le terme d'origine, vide pour une création.
        var origine = ""

        init() {}
        init(_ entree: EntreeLexique) {
            terme = entree.terme
            variantes = entree.variantes.joined(separator: ", ")
            categorie = entree.categorie
            note = entree.note ?? ""
            origine = entree.terme
        }

        var entree: EntreeLexique {
            EntreeLexique(
                terme: terme.trimmingCharacters(in: .whitespaces),
                variantes: variantes.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
                categorie: categorie,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private var entrees: [EntreeLexique] {
        let filtre = recherche.trimmingCharacters(in: .whitespaces)
        guard !filtre.isEmpty else { return lexique.entrees }
        let cible = Lexique.normaliser(filtre)
        return lexique.entrees.filter {
            Lexique.normaliser($0.terme).contains(cible)
                || $0.variantes.contains { Lexique.normaliser($0).contains(cible) }
                || Lexique.normaliser($0.note ?? "").contains(cible)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            entete
            barreDeRecherche
            Divider().overlay(Teinte.trait)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ressemblances
                    if enEdition == "" { formulaire }
                    ForEach(entrees, id: \.terme) { entree in
                        if enEdition == entree.terme { formulaire } else { carte(entree) }
                    }
                    if entrees.isEmpty && enEdition == nil {
                        Text(lexique.entrees.isEmpty
                             ? "Le lexique est vide. Il se remplira de vos réponses aux questions."
                             : "Aucun terme ne correspond.")
                            .font(.system(size: 12)).foregroundStyle(Teinte.texteFaible)
                            .padding(.top, 20)
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 600, height: 560)
        .background(Teinte.fondUni)
        .task { recharger() }
    }

    private var entete: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Le lexique").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Teinte.texte)
                Text("\(lexique.entrees.count) termes acquis. Ils ne seront plus redemandés.")
                    .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
            }
            Spacer()
            Explication(
                titre: "À quoi sert le lexique ?",
                texte: "Il retient ce que vous avez corrigé une fois : un nom de client "
                     + "mal transcrit, un sigle, une expression de votre métier.\n\n"
                     + "Deux champs y travaillent différemment. Les VARIANTES sont les "
                     + "fautes déjà rencontrées : elles suppriment l'hésitation dès la "
                     + "deuxième fois. La NOTE ne corrige rien — elle sert à rédiger "
                     + "juste, pas seulement à orthographier juste.\n\n"
                     + "Seules les entrées présentes dans le transcript sont envoyées à "
                     + "Claude : le lexique peut grossir sans alourdir chaque analyse.\n\n"
                     + "C'est lui qui fait décroître le nombre de questions d'un compte "
                     + "rendu à l'autre.")
            BoutonDiscret(titre: "Ajouter", icone: "plus") {
                brouillon = Brouillon()
                enEdition = ""
            }
            BoutonDiscret(titre: "Ouvrir le fichier", icone: "doc.text") {
                NSWorkspace.shared.open(url)
            }
            BoutonPrincipal(titre: "Fermer") { fermer() }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var barreDeRecherche: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundStyle(Teinte.texteFaible)
            TextField("Chercher un terme, une variante, une note", text: $recherche)
                .textFieldStyle(.plain).font(.system(size: 12.5))
                .foregroundStyle(Teinte.texte)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Teinte.carte,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Teinte.trait))
        .padding(.horizontal, 22).padding(.bottom, 12)
    }

    /// Les doublons probables, signalés tant qu'ils ne sont pas tranchés.
    ///
    /// Deux entrées très proches ne sont jamais réunies d'office : « Menuiseries Vidal »
    /// et « Menuiserie Vidal » peuvent désigner la même entreprise ou deux clients
    /// différents, et l'outil n'a aucun moyen de le savoir.
    @ViewBuilder private var ressemblances: some View {
        let paires = lexique.ressemblances()
        if !paires.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Ces termes se ressemblent : sont-ils la même chose ?",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Teinte.ambre)
                ForEach(paires.indices, id: \.self) { i in
                    let (a, b) = paires[i]
                    HStack(spacing: 9) {
                        Text("« \(a.terme) » et « \(b.terme) »")
                            .font(.system(size: 12)).foregroundStyle(Teinte.texte)
                        Spacer()
                        BoutonDiscret(titre: "Garder « \(a.terme) »") { fusionner(b.terme, dans: a.terme) }
                        BoutonDiscret(titre: "Garder « \(b.terme) »") { fusionner(a.terme, dans: b.terme) }
                    }
                }
                Text("Le terme abandonné devient une variante de l'autre : c'est une faute "
                     + "déjà rencontrée, et la garder évite qu'elle repose la question.")
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Teinte.ambre.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Teinte.ambre.opacity(0.35)))
            .padding(.bottom, 6)
        }
    }

    private func carte(_ entree: EntreeLexique) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(entree.terme).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Teinte.texte)
                Etiquette(texte: entree.categorie.rawValue)
                Spacer()
                BoutonDiscret(titre: "Modifier", icone: "pencil") {
                    brouillon = Brouillon(entree)
                    enEdition = entree.terme
                    enCoursDeSuppression = nil
                }
                Button {
                    supprimer(entree)
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                        .foregroundStyle(enCoursDeSuppression == entree.terme
                                         ? .red : Teinte.texteFaible)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help(enCoursDeSuppression == entree.terme
                      ? "Cliquez à nouveau pour retirer définitivement ce terme."
                      : "Retirer ce terme du lexique. Il sera redemandé au prochain "
                        + "compte rendu.")
            }
            if !entree.variantes.isEmpty {
                Text("déjà transcrit à tort : " + entree.variantes.joined(separator: ", "))
                    .font(.system(size: 11)).foregroundStyle(Teinte.ambre)
            }
            if let note = entree.note {
                Text(note).font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Teinte.carte, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(Teinte.trait))
    }

    private var formulaire: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(brouillon.origine.isEmpty ? "Nouveau terme" : "Modifier « \(brouillon.origine) »")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Teinte.texte)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Terme, tel qu'il doit s'écrire")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteDoux)
                    TextField("Menuiseries Vidal", text: $brouillon.terme).champGreffier()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nature").font(.system(size: 11)).foregroundStyle(Teinte.texteDoux)
                    Picker("", selection: $brouillon.categorie) {
                        ForEach(Categorie.allCases, id: \.self) { categorie in
                            Text(categorie.rawValue).tag(categorie)
                        }
                    }
                    .labelsHidden().frame(width: 130)
                }
            }

            if let proche = proximite {
                Label("Ressemble à « \(proche) », déjà dans le lexique. Si c'est la même "
                      + "chose, modifiez plutôt cette entrée-là.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(Teinte.ambre)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Fautes de transcription déjà rencontrées, séparées par des virgules")
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteDoux)
                TextField("Menuiserie Vidal, MENUISERIES VIDAL", text: $brouillon.variantes).champGreffier()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Ce qu'il faut en savoir pour rédiger juste — laissez vide si vous "
                     + "n'êtes pas sûr")
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteDoux)
                TextField("", text: $brouillon.note, axis: .vertical)
                    .lineLimit(2...5).champGreffier()
            }

            HStack(spacing: 10) {
                Spacer()
                BoutonDiscret(titre: "Annuler") { enEdition = nil }
                BoutonPrincipal(titre: "Enregistrer",
                                actif: !brouillon.terme.trimmingCharacters(in: .whitespaces)
                                    .isEmpty) {
                    valider()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Teinte.bleu.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(Teinte.bleu.opacity(0.4)))
    }

    /// Un terme déjà connu qui ressemble à celui qu'on est en train de saisir.
    private var proximite: String? {
        let terme = brouillon.terme.trimmingCharacters(in: .whitespaces)
        guard terme.count >= 3, Lexique.normaliser(terme) != Lexique.normaliser(brouillon.origine)
        else { return nil }
        var sansCelleCi = lexique
        sansCelleCi.entrees.removeAll { $0.terme == brouillon.origine }
        return sansCelleCi.entreeProche(de: terme)?.terme
    }

    // MARK: - Écritures

    private func recharger() {
        lexique = (try? Lexique.charger(depuis: url)) ?? Lexique()
    }

    private func enregistrer() {
        try? lexique.enregistrer(vers: url)
        recharger()
    }

    /// Relit le fichier avant d'y écrire, et repart de ce qu'il contient.
    ///
    /// L'enrichissement automatique écrit dans le même fichier : cette fenêtre
    /// pouvait être ouverte au moment où un compte rendu apprenait un terme, et
    /// sa prochaine écriture l'aurait effacé sans un mot.
    private func avecLeFichierAJour(_ modifier: (inout Lexique) -> Void) {
        var frais = (try? Lexique.charger(depuis: url)) ?? lexique
        modifier(&frais)
        lexique = frais
        enregistrer()
    }

    private func valider() {
        let entree = brouillon.entree
        guard !entree.terme.isEmpty else { return }
        // Une modification remplace en place plutôt que d'ajouter à côté :
        // renommer « Menuiserie Vidal » en « Menuiseries Vidal » ne doit pas laisser les deux.
        avecLeFichierAJour { lexique in
            if !brouillon.origine.isEmpty,
               let i = lexique.entrees.firstIndex(where: { $0.terme == brouillon.origine }) {
                lexique.entrees[i] = entree
            } else {
                lexique.integrer(entree)
            }
        }
        enEdition = nil
    }

    private func fusionner(_ abandonne: String, dans retenu: String) {
        avecLeFichierAJour { $0.fusionner(abandonne, dans: retenu) }
    }

    /// Une suppression demande deux clics : une entrée retirée par mégarde ne
    /// se remarque qu'au compte rendu suivant, quand la question revient.
    private func supprimer(_ entree: EntreeLexique) {
        guard enCoursDeSuppression == entree.terme else {
            enCoursDeSuppression = entree.terme
            return
        }
        avecLeFichierAJour { lexique in
            lexique.entrees.removeAll { $0.terme == entree.terme }
        }
        enCoursDeSuppression = nil
    }
}
