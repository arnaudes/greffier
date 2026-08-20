import SwiftUI
import NoyauCR

/// Relire un compte rendu produit, et retrouver celui qu'on cherche.
///
/// Les comptes rendus n'étaient atteignables que par le Finder : le panneau de
/// droite en listait trois et les ouvrait ailleurs. Or ce sont des documents
/// qu'on relit des mois plus tard, souvent sans se souvenir du client — mais en
/// se souvenant d'un montant, d'un nom, d'une phrase dite en séance.
struct VueArchives: View {
    let racine: URL
    /// La forme des documents exportés d'ici.
    var charte: Charte = .parDefaut
    /// Ce qui s'affiche au-dessus du titre : la société de l'utilisateur.
    var surTitre = ""
    /// Vrai quand un compte rendu produit n'est pas encore enregistré : en
    /// rouvrir un autre le ferait disparaître.
    var avertirDeLaPerte = false
    /// Reprendre un compte rendu dans la chaîne, pour le corriger et refaire
    /// son PDF.
    var reprendre: (Rangement.Reunion, String) -> Void

    @State private var demande = ""
    @State private var resultats: [Recherche.Resultat] = []
    @State private var choisie: Recherche.Resultat?
    @State private var contenu = ""
    @State private var cherche = false
    @State private var confirmeReprise = false
    /// Ce qu'il y a à dire quand un export vient d'avoir lieu — ou d'échouer.
    @State private var messageExport: String?
    @Environment(\.dismiss) private var fermer

    var body: some View {
        VStack(spacing: 0) {
            entete
            Divider().overlay(Teinte.trait)
            HStack(spacing: 0) {
                liste.frame(width: 300)
                Divider().overlay(Teinte.trait)
                document
            }
        }
        .frame(width: 980, height: 620)
        .background(Teinte.fondUni)
        .task { rechercher() }
    }

    private var entete: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vos comptes rendus").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Teinte.texte)
                Text(resume).font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11))
                    .foregroundStyle(Teinte.texteFaible)
                TextField("Un client, un mot dit en réunion, un montant…", text: $demande)
                    .textFieldStyle(.plain).font(.system(size: 12.5))
                    .foregroundStyle(Teinte.texte)
                    .frame(width: 260)
                    .onSubmit { rechercher() }
                    .onChange(of: demande) { _, _ in rechercher() }
                if !demande.isEmpty {
                    Button { demande = ""; rechercher() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                            .foregroundStyle(Teinte.texteFaible)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Teinte.carte,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Teinte.trait))
            BoutonPrincipal(titre: "Fermer") { fermer() }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var resume: String {
        if cherche { return "Recherche en cours…" }
        if demande.isEmpty {
            return resultats.isEmpty
                ? "Aucun compte rendu pour l'instant."
                : "\(resultats.count) réunion\(resultats.count > 1 ? "s" : "")."
        }
        return resultats.isEmpty
            ? "Rien ne correspond à « \(demande) »."
            : "\(resultats.count) réunion\(resultats.count > 1 ? "s" : "") trouvée"
              + "\(resultats.count > 1 ? "s" : "")."
    }

    // MARK: - La liste

    private var liste: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(resultats) { resultat in
                    carte(resultat)
                }
                if resultats.isEmpty && !cherche {
                    Text(demande.isEmpty
                         ? "Vos comptes rendus apparaîtront ici au fur et à mesure."
                         : "Essayez un autre mot : la recherche porte sur le nom du "
                           + "client, l'objet de la réunion et le corps du compte rendu.")
                        .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)
                }
            }
            .padding(14)
        }
    }

    private func carte(_ resultat: Recherche.Resultat) -> some View {
        let active = choisie?.id == resultat.id
        return Button {
            choisir(resultat)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(resultat.projet).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Teinte.bleuClair).lineLimit(1)
                    Spacer()
                    if let date = resultat.reunion.date {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10)).foregroundStyle(Teinte.texteFaible)
                    }
                }
                Text(resultat.reunion.titre)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Teinte.texte)
                    .multilineTextAlignment(.leading).lineLimit(2)
                if let extrait = resultat.extrait {
                    Text(extrait).font(.system(size: 10.5).italic())
                        .foregroundStyle(Teinte.texteDoux)
                        .multilineTextAlignment(.leading).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(active ? Teinte.bleu.opacity(0.14) : Teinte.carte,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(active ? Teinte.bleu.opacity(0.5) : Teinte.trait))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Le document

    @ViewBuilder private var document: some View {
        if let choisie {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(choisie.reunion.titre)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Teinte.texte).lineLimit(1)
                        Text(choisie.projet).font(.system(size: 11))
                            .foregroundStyle(Teinte.texteFaible)
                    }
                    Spacer()
                    if let pdf = choisie.reunion.pdf {
                        BoutonDiscret(titre: "PDF", icone: "doc.richtext") {
                            NSWorkspace.shared.open(pdf)
                        }
                    }
                    // L'export Word n'existait que sur l'écran du compte rendu
                    // qui vient d'être produit. Or on a besoin d'un document à
                    // envoyer bien plus tard, quand l'application a été relancée
                    // et que cet écran n'existe plus.
                    BoutonDiscret(titre: "Word", icone: "arrow.up.doc") {
                        exporter(choisie)
                    }
                    .help("Écrit un document Word de ce compte rendu, dans son "
                          + "dossier, pour l'annoter ou l'envoyer.")
                    BoutonDiscret(titre: "Dossier", icone: "folder") {
                        NSWorkspace.shared.open(choisie.reunion.dossier)
                    }
                    // Reprendre plutôt que recommencer : le compte rendu revient
                    // dans la chaîne, on le corrige, on refait le PDF.
                    BoutonDiscret(titre: confirmeReprise ? "Confirmer" : "Reprendre",
                                  icone: "square.and.pencil") {
                        // Le compte rendu en cours n'est pas enregistré : en
                        // rouvrir un autre le ferait disparaître, avec les
                        // réponses données.
                        if avertirDeLaPerte && !confirmeReprise {
                            confirmeReprise = true
                            return
                        }
                        reprendre(choisie.reunion, contenu)
                        fermer()
                    }
                    .help(avertirDeLaPerte
                          ? "Votre compte rendu en cours n'est pas enregistré : "
                            + "il sera perdu."
                          : "Ramène ce compte rendu dans l'application pour le corriger "
                            + "et refaire son PDF.")
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                if let messageExport {
                    Text(messageExport)
                        .font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.bottom, 10)
                }
                Divider().overlay(Teinte.trait)
                ScrollView {
                    Text(contenu)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Teinte.texte)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text").font(.system(size: 26))
                    .foregroundStyle(Teinte.texteFaible)
                Text("Choisissez une réunion pour la relire.")
                    .font(.system(size: 12.5)).foregroundStyle(Teinte.texteFaible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func rechercher() {
        let demandeCourante = demande
        cherche = true
        Task.detached(priority: .userInitiated) {
            let trouves = demandeCourante.trimmingCharacters(in: .whitespaces).count >= 2
                ? Recherche.chercher(demandeCourante, racine: racine)
                : Recherche.toutes(racine: racine)
            await MainActor.run {
                // La demande a pu changer pendant la recherche : ne pas
                // afficher le résultat d'une frappe déjà dépassée.
                guard demandeCourante == demande else { return }
                resultats = trouves
                cherche = false
                if choisie == nil { choisir(trouves.first) }
            }
        }
    }

    /// Écrit le compte rendu affiché en document Word, dans son dossier.
    private func exporter(_ resultat: Recherche.Resultat) {
        guard !contenu.isEmpty else {
            messageExport = "Ce compte rendu est vide : il n'y a rien à exporter."
            return
        }
        let nom = Rangement.nomDeFichier(projet: resultat.projet,
                                         objet: resultat.reunion.titre,
                                         date: resultat.reunion.date ?? Date())
        let url = resultat.reunion.dossier
            .appendingPathComponent("\(nom).\(Export.extensionTraitementDeTexte)")
        do {
            let entete = RenduWord.Entete(
                titre: "Compte rendu de réunion — \(resultat.projet)",
                sousTitre: resultat.reunion.titre, projet: resultat.projet,
                date: resultat.reunion.date?
                    .formatted(date: .long, time: .omitted) ?? "")
            try Export.versTraitementDeTexte(contenu, vers: url, charte: charte,
                                             surTitre: surTitre, enteteWord: entete)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            messageExport = "Le document Word « \(url.lastPathComponent) » est prêt : "
                + "le Finder vient de s'ouvrir dessus."
        } catch {
            messageExport = "Le document Word n'a pas pu être écrit. "
                + "\(error.localizedDescription)"
        }
    }

    private func choisir(_ resultat: Recherche.Resultat?) {
        choisie = resultat
        messageExport = nil
        guard let url = resultat?.reunion.compteRendu else { contenu = ""; return }
        contenu = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
