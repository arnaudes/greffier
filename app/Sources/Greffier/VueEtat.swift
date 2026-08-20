import SwiftUI
import NoyauCR

/// Ce que Greffier voit de cet ordinateur, rassemblé en un endroit.
///
/// Les vérifications existaient, mais éparpillées : le micro dans un onglet, la
/// dictée dans un autre, Claude dans un troisième, et **la reconnaissance
/// vocale nulle part**. Le 20/08/2026, elle n'avait jamais été demandée sur la
/// machine d'usage courant, et rien ne le signalait — la première réunion
/// enregistrée aurait échoué à la transcription.
///
/// Chaque ligne dit trois choses : où en est la condition, à quoi elle sert, et
/// ce qu'on perd sans elle. Rien n'est demandé tant qu'on ne clique pas :
/// présenter huit demandes d'autorisation à l'ouverture d'un écran serait le
/// meilleur moyen de les voir toutes refusées.
struct VueEtat: View {
    @Bindable var reglages: Reglages
    @State private var prerequis: Prerequis?
    @State private var enCours: Prerequis.Condition?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                entete
                if let prerequis {
                    ForEach(Prerequis.Condition.allCases) { condition in
                        ligne(condition, etat: prerequis.etat(condition))
                    }
                }
                Text("Aucune autorisation n'est demandée tant que vous ne cliquez pas.")
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    .padding(.top, 2)
            }
            .padding(20)
        }
        .task { verifier() }
    }

    @ViewBuilder private var entete: some View {
        if let prerequis {
            HStack(alignment: .top, spacing: 10) {
                PastilleEtat(gravite: prerequis.gravite,
                             texte: prerequis.toutVaBien
                                ? "Tout est en place."
                                : "\(prerequis.manques.count) point"
                                  + (prerequis.manques.count > 1 ? "s" : "")
                                  + " à régler",
                             detail: prerequis.toutVaBien
                                ? "Greffier peut enregistrer, transcrire et rédiger."
                                : (prerequis.peutEnregistrer
                                   ? "Vous pouvez enregistrer sans risque : rien de ce qui "
                                     + "manque ne ferait perdre une réunion."
                                   : "⚠️ Une réunion enregistrée maintenant serait perdue."))
                Spacer()
                BoutonDiscret(titre: "Revérifier", icone: "arrow.clockwise") { verifier() }
            }
            Divider().overlay(Teinte.trait)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func ligne(_ condition: Prerequis.Condition,
                       etat: Prerequis.Etat) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: etat.satisfait ? "checkmark.circle.fill" : symbole(etat))
                .font(.system(size: 14))
                .foregroundStyle(couleur(condition, etat))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(condition.titre).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Teinte.texte)
                    Text(etat.libelle).font(.system(size: 11))
                        .foregroundStyle(couleur(condition, etat))
                }
                Text(etat.satisfait ? condition.role : condition.consequence)
                    .font(.system(size: 11))
                    .foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !etat.satisfait { actions(condition) }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private func actions(_ condition: Prerequis.Condition) -> some View {
        HStack(spacing: 7) {
            if enCours == condition {
                ProgressView().controlSize(.small)
            } else if peutSeDemander(condition) {
                BoutonDiscret(titre: "Autoriser") {
                    Task {
                        enCours = condition
                        _ = await Prerequis.demander(condition)
                        enCours = nil
                        verifier()
                    }
                }
            }
            if let reglages = Prerequis.reglagesSysteme(condition) {
                BoutonDiscret(titre: "Réglages") { NSWorkspace.shared.open(reglages) }
            }
            if condition == .dossier {
                BoutonDiscret(titre: "Choisir") { choisirLeDossier() }
            }
        }
    }

    /// L'autorisation se demande-t-elle depuis l'application ? La dictée, un
    /// programme absent ou un dossier introuvable se règlent ailleurs.
    private func peutSeDemander(_ condition: Prerequis.Condition) -> Bool {
        switch condition {
        case .micro, .reconnaissance, .calendrier, .ecran: true
        case .dictee, .claude, .chrome, .dossier: false
        }
    }

    private func symbole(_ etat: Prerequis.Etat) -> String {
        switch etat {
        case .bon: "checkmark.circle.fill"
        case .aDemander: "questionmark.circle"
        case .refuse: "xmark.circle.fill"
        case .absent: "exclamationmark.circle"
        }
    }

    private func couleur(_ condition: Prerequis.Condition,
                         _ etat: Prerequis.Etat) -> Color {
        if etat.satisfait { return Teinte.vert }
        return condition.faitPerdreLaReunion ? .red : Teinte.ambre
    }

    private func verifier() {
        prerequis = Prerequis.verifier(
            cheminClaude: reglages.cheminClaude.trimmingCharacters(in: .whitespaces).isEmpty
                ? "claude" : reglages.cheminClaude,
            dossierDeTravail: reglages.dossierDeTravail)
    }

    private func choisirLeDossier() {
        let panneau = NSOpenPanel()
        panneau.canChooseDirectories = true
        panneau.canChooseFiles = false
        panneau.canCreateDirectories = true
        panneau.directoryURL = reglages.dossierDeTravail
        panneau.message = "Choisissez le dossier où ranger vos comptes rendus."
        panneau.prompt = "Utiliser ce dossier"
        guard panneau.runModal() == .OK, let url = panneau.url else { return }
        reglages.dossierDeTravail = url
        verifier()
    }
}
