import SwiftUI
import NoyauCR

/// Ce qu'on demande à Claude en plus, pour ce dossier seulement.
///
/// Un client n'attend pas ce qu'attend l'autre : l'un veut des comptes rendus
/// serrés, l'autre suit un dossier de subvention où chaque jalon doit être
/// qualifié. Une charte unique pour tous obligerait à écrire des consignes si
/// générales qu'elles ne serviraient plus.
struct VueConsignes: View {
    let projet: String
    let identite: Identite
    @State var texte: String
    let enregistrer: (String) -> Void

    @State private var promptVisible = false
    @Environment(\.dismiss) private var fermer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Consignes pour « \(projet) »")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)
                    Text("Ajoutées à votre charte, pour ce dossier seulement.")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                }
                Spacer()
            }

            TextEditor(text: $texte)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Teinte.carte,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Teinte.trait))
                .frame(height: 190)

            Text("Une consigne par ligne. Par exemple : « Cite systématiquement le numéro "
                 + "de lot pour ce client » ou « Ne mentionne jamais les autres dossiers "
                 + "en cours ».")
                .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                .fixedSize(horizontal: false, vertical: true)

            Text("Elles portent sur la forme et le contexte. Elles ne peuvent jamais "
                 + "conduire Greffier à inventer ni à trancher à votre place.")
                .font(.system(size: 11)).foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                BoutonDiscret(titre: "Voir ce que Claude reçoit", icone: "eye") {
                    promptVisible = true
                }
                Spacer()
                BoutonDiscret(titre: "Annuler") { fermer() }
                BoutonPrincipal(titre: "Enregistrer") {
                    enregistrer(texte)
                    fermer()
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Teinte.fondHaut)
        .sheet(isPresented: $promptVisible) {
            VuePrompt(identite: identite, consignesDossier: texte,
                      nomDuDossier: projet) { promptVisible = false }
        }
    }
}

/// Dire ce qui n'allait pas, pour que Greffier le retienne.
///
/// Personne ne sait décrire sa façon d'écrire à froid — mais tout le monde sait
/// dire ce qui cloche dans un document qu'il vient de lire. C'est le procédé du
/// lexique appliqué au style : on ne configure pas, on corrige, et l'outil
/// retient.
///
/// **À la demande, jamais après chaque compte rendu** : une application qui
/// réclame un avis à chaque fois finit par n'en recevoir aucun.
struct VueAjustement: View {
    @Bindable var session: Session
    @State private var reproche = ""
    @Environment(\.dismiss) private var fermer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Qu'est-ce qui n'allait pas ?")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)
                Text("Dites-le comme vous le diriez à quelqu'un. Greffier en tirera une "
                     + "consigne pour les prochaines fois.")
                    .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("Par exemple : tu as rangé la phase 2 en décision alors que rien "
                      + "n'était acté.", text: $reproche, axis: .vertical)
                .lineLimit(3...6).champGreffier()

            if let proposee = session.consigneProposee {
                VStack(alignment: .leading, spacing: 9) {
                    Text("La consigne que Greffier propose de retenir :")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    Text(proposee)
                        .font(.system(size: 12.5)).foregroundStyle(Teinte.texte)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Teinte.vert.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Teinte.vert.opacity(0.35)))
                    HStack(spacing: 9) {
                        BoutonDiscret(titre: "Pour « \(session.projet) »",
                                      icone: "folder", pleineLargeur: true) {
                            session.retenir(proposee, portee: .ceDossier)
                            fermer()
                        }
                        BoutonPrincipal(titre: "Pour tous mes comptes rendus",
                                        icone: "checkmark", pleineLargeur: true) {
                            session.retenir(proposee, portee: .tousLesDossiers)
                            fermer()
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer()
                BoutonDiscret(titre: session.consigneProposee == nil ? "Annuler" : "Ne rien retenir") {
                    session.consigneProposee = nil
                    fermer()
                }
                if session.consigneProposee == nil {
                    if session.deductionEnCours {
                        ProgressView().controlSize(.small)
                    } else {
                        BoutonPrincipal(titre: "Proposer une consigne", icone: "wand.and.stars",
                                        actif: !reproche.trimmingCharacters(in: .whitespaces)
                                            .isEmpty) {
                            Task { await session.deduireUneConsigne(reproche) }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Teinte.fondHaut)
    }
}
