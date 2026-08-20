import SwiftUI
import NoyauCR

/// Ce que Claude reçoit, morceau par morceau, avec l'origine de chacun.
///
/// L'écran affichait un bloc de texte uniforme : on voyait tout sans savoir ce
/// qu'on pouvait changer ni où. Montrer la provenance vaut mieux que de tout
/// rendre éditable — d'autant que ce prompt porte aussi les schémas dont dépend
/// le décodage des réponses, et qu'une retouche malheureuse arrêterait
/// l'application sans qu'on fasse le lien.
struct VuePrompt: View {
    let identite: Identite
    var consignesDossier: String = ""
    var nomDuDossier: String?
    let fermer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ce que Claude reçoit").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Teinte.texte)
                    Text("Les consignes marquées d'un crayon viennent de vous. "
                         + "Les autres sont ce que Greffier garantit.")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                }
                Spacer()
                BoutonPrincipal(titre: "Fermer") { fermer() }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider().overlay(Teinte.trait)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Prompts.blocs(identite: identite,
                                          consignesDossier: consignesDossier)) { bloc in
                        carte(bloc)
                    }
                    Text("Les schémas de réponse attendus par l'application sont envoyés "
                         + "en plus de ces consignes. Ils ne sont pas modifiables : les "
                         + "changer empêcherait Greffier de comprendre ce que Claude "
                         + "répond.")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(18)
            }
        }
        .frame(width: 660, height: 580)
        .background(Teinte.fondUni)
    }

    private func carte(_ bloc: Prompts.Bloc) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: bloc.origine.modifiable ? "pencil" : "lock.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(bloc.origine.modifiable ? Teinte.bleuClair : Teinte.vert)
                Text(etiquette(bloc.origine))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(bloc.origine.modifiable ? Teinte.bleuClair : Teinte.vert)
                Spacer()
                if let titre = bloc.titre {
                    Text(titre).font(.system(size: 9.5, weight: .bold)).tracking(0.8)
                        .foregroundStyle(Teinte.texteFaible)
                }
            }
            Text(bloc.texte)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Teinte.texteDoux)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(bloc.origine.modifiable ? Teinte.bleu.opacity(0.07) : Teinte.carte,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(bloc.origine.modifiable
                          ? Teinte.bleu.opacity(0.3) : Teinte.trait))
    }

    /// L'origine, dite avec le nom du dossier quand c'est de lui qu'il s'agit.
    private func etiquette(_ origine: Prompts.Origine) -> String {
        guard origine == .dossier, let nom = nomDuDossier else { return origine.libelle }
        return "Consignes de « \(nom) »"
    }
}
