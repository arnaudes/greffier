import AVFoundation
import SwiftUI
import NoyauCR

/// Les enregistrements : ce qui n'a rien produit, et ce qui accompagne un
/// compte rendu.
///
/// Cette fenêtre manquait entièrement : l'audio vivait hors de vue, et rien
/// dans l'application ne disait qu'un enregistrement traînait ni ce qu'il
/// pesait. La suppression n'est pourtant pas la seule action utile — un
/// orphelin peut être une réunion oubliée. Le 19/08/2026, une visioconférence
/// de trente minutes a été récupérée depuis son audio conservé ; une fenêtre
/// qui n'aurait proposé que d'effacer l'aurait détruite.
struct VueEnregistrements: View {
    let racine: URL
    var transcrire: (URL) -> Void

    @State private var orphelins: [Enregistrements.Orphelin] = []
    @State private var ranges: [Enregistrements.AudioRange] = []
    @State private var enCoursDeSuppression: String?
    @State private var lecteur: AVAudioPlayer?
    @State private var enLecture: String?
    @Environment(\.dismiss) private var fermer

    var body: some View {
        VStack(spacing: 0) {
            entete
            Divider().overlay(Teinte.trait)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sectionOrphelins
                    sectionRanges
                }
                .padding(22)
            }
        }
        .frame(width: 640, height: 580)
        .background(Teinte.fondUni)
        .task { recharger() }
        .onDisappear { lecteur?.stop() }
    }

    private var entete: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Les enregistrements").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Teinte.texte)
                Text(resume).font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
            }
            Spacer()
            BoutonDiscret(titre: "Ouvrir le dossier", icone: "folder") {
                NSWorkspace.shared.open(racine.appendingPathComponent("enregistrements"))
            }
            BoutonPrincipal(titre: "Fermer") { fermer() }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var resume: String {
        let total = orphelins.reduce(0) { $0 + $1.taille } + ranges.reduce(0) { $0 + $1.taille }
        guard total > 0 else { return "Aucun fichier audio sur cet ordinateur." }
        return "\(Enregistrements.lisible(total)) d'audio en tout."
    }

    // MARK: - Ce qui n'a rien produit

    @ViewBuilder private var sectionOrphelins: some View {
        VStack(alignment: .leading, spacing: 10) {
            Intertitre(texte: "Sans compte rendu")
            if orphelins.isEmpty {
                Text("Rien en attente : tous vos enregistrements ont donné un compte rendu.")
                    .font(.system(size: 12)).foregroundStyle(Teinte.texteFaible)
            } else {
                Text("Ces enregistrements n'ont produit aucun compte rendu. "
                     + "Un enregistrement court est sans doute un essai ; un enregistrement "
                     + "long est une réunion qu'il reste à traiter.")
                    .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(orphelins) { orphelin in carteOrphelin(orphelin) }
            }
        }
    }

    private func carteOrphelin(_ o: Enregistrements.Orphelin) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(Enregistrements.dureeLisible(o.duree))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Teinte.texte)
                Etiquette(texte: Enregistrements.lisible(o.taille))
                if o.estUnEssai {
                    Etiquette(texte: "probablement un essai", couleur: Teinte.ambre)
                }
                Spacer()
                Text(o.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
            }
            Text(o.url.lastPathComponent)
                .font(.system(size: 11).monospaced()).foregroundStyle(Teinte.texteFaible)
            Text(o.conseil).font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                BoutonDiscret(titre: enLecture == o.id ? "Arrêter" : "Écouter",
                              icone: enLecture == o.id ? "stop.fill" : "play.fill") {
                    ecouter(o)
                }
                if !o.estUnEssai {
                    BoutonDiscret(titre: "Transcrire", icone: "text.alignleft") {
                        lecteur?.stop(); enLecture = nil
                        transcrire(o.url)
                        fermer()
                    }
                }
                Spacer()
                Button {
                    supprimer(o)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash").font(.system(size: 11))
                        Text(enCoursDeSuppression == o.id ? "Confirmer" : "Supprimer")
                            .font(.system(size: 12.5))
                    }
                    .foregroundStyle(enCoursDeSuppression == o.id ? .red : Teinte.texteDoux)
                    .padding(.vertical, 8).padding(.horizontal, 14)
                    .background(Teinte.carte,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(enCoursDeSuppression == o.id
                                      ? Color.red.opacity(0.5) : Teinte.trait))
                }
                .buttonStyle(.plain)
                .help("Un enregistrement effacé ne se retrouve jamais.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Teinte.carte, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(o.estUnEssai ? Teinte.ambre.opacity(0.3) : Teinte.trait))
    }

    // MARK: - Ce qui accompagne un compte rendu

    @ViewBuilder private var sectionRanges: some View {
        let perimes = ranges.filter { $0.perime() }
        let poidsPerime = perimes.reduce(0) { $0 + $1.taille }
        let poidsTotal = ranges.reduce(0) { $0 + $1.taille }

        VStack(alignment: .leading, spacing: 10) {
            Intertitre(texte: "Rangés avec un compte rendu")
            if ranges.isEmpty {
                Text("Aucun enregistrement conservé avec vos comptes rendus.")
                    .font(.system(size: 12)).foregroundStyle(Teinte.texteFaible)
            } else {
                Text("\(Enregistrements.lisible(poidsTotal)) au total."
                     + (perimes.isEmpty
                        ? " Aucun n'a plus d'un an."
                        : " Dont \(Enregistrements.lisible(poidsPerime)) pour des réunions "
                          + "traitées il y a plus d'un an."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(poidsTotal > Enregistrements.volumeQuiInterpelle
                                     ? Teinte.ambre : Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)

                if !perimes.isEmpty {
                    Text("Supprimer un de ces fichiers ne touche ni au compte rendu, ni au "
                         + "transcript, ni au PDF — mais une nouvelle transcription ne sera "
                         + "plus possible.")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(ranges) { audio in carteRange(audio, perime: audio.perime()) }
            }
        }
    }

    private func carteRange(_ a: Enregistrements.AudioRange, perime: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(a.projet) — \(a.reunion)")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Teinte.texte)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(Enregistrements.lisible(a.taille))
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    if perime {
                        Etiquette(texte: "plus d'un an", couleur: Teinte.ambre)
                    }
                }
            }
            Spacer()
            BoutonDiscret(titre: "Montrer", icone: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([a.url])
            }
            Button {
                supprimerRange(a)
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
                    .foregroundStyle(enCoursDeSuppression == a.id ? .red : Teinte.texteFaible)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help(enCoursDeSuppression == a.id
                  ? "Cliquez à nouveau pour effacer définitivement cet enregistrement."
                  : "Effacer l'audio. Le compte rendu et le transcript restent.")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Teinte.carte, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(perime ? Teinte.ambre.opacity(0.3) : Teinte.trait))
    }

    // MARK: - Actions

    private func recharger() {
        orphelins = Enregistrements.orphelins(racine: racine)
        ranges = Enregistrements.rangés(racine: racine)
        enCoursDeSuppression = nil
    }

    /// Écouter avant de trancher : une durée ne dit pas si l'enregistrement
    /// porte une vraie réunion ou le bruit d'un bureau.
    private func ecouter(_ o: Enregistrements.Orphelin) {
        if enLecture == o.id { lecteur?.stop(); enLecture = nil; return }
        lecteur?.stop()
        lecteur = try? AVAudioPlayer(contentsOf: o.url)
        lecteur?.play()
        enLecture = lecteur == nil ? nil : o.id
    }

    /// Deux clics, comme partout ailleurs : un enregistrement effacé ne se
    /// retrouve jamais, et celui-ci peut porter une réunion entière.
    private func supprimer(_ o: Enregistrements.Orphelin) {
        guard enCoursDeSuppression == o.id else { enCoursDeSuppression = o.id; return }
        if enLecture == o.id { lecteur?.stop(); enLecture = nil }
        try? FileManager.default.removeItem(at: o.url)
        recharger()
    }

    private func supprimerRange(_ a: Enregistrements.AudioRange) {
        guard enCoursDeSuppression == a.id else { enCoursDeSuppression = a.id; return }
        try? FileManager.default.removeItem(at: a.url)
        recharger()
    }
}
