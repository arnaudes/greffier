import SwiftUI
import NoyauCR

/// Le compte rendu produit, et ce qu'on en fait.
struct VueResultat: View {
    @Bindable var session: Session
    @State private var demandeDestinataire = false
    @State private var ajustement = false

    var body: some View {
        VStack(spacing: 0) {
            EnteteEcran(titre: "Compte rendu interne",
                        detail: session.titreReunion.isEmpty
                            ? session.projet : session.titreReunion,
                        etape: 3, libelleEtape: "Le compte rendu",
                        reglages: session.reglages,
                        accueil: { session.revenirALAccueil() }) {
                HStack(spacing: 9) {
                    Explication(
                        titre: "Décision, ou piste évoquée ?",
                        texte: "Le compte rendu range ce qui s'est dit en deux catégories, "
                             + "et c'est la distinction qui coûte le plus cher quand elle "
                             + "est manquée.\n\n"
                             + "Une DÉCISION est actée : « on démarre le 1er septembre ».\n\n"
                             + "Une PISTE a seulement été évoquée : « on pourrait envisager "
                             + "une phase 2, mais rien n'est décidé ».\n\n"
                             + "Six mois plus tard, personne ne se souvient si la phase 2 "
                             + "était engagée ou simplement mentionnée. Greffier ne tranche "
                             + "jamais : dans le doute, il vous pose la question.")
                    if let pdf = session.cheminPDF {
                        BoutonDiscret(titre: "Ouvrir le PDF", icone: "doc.richtext") {
                            NSWorkspace.shared.open(pdf)
                        }
                    }
                    if session.emailClient.isEmpty {
                        BoutonDiscret(titre: "Produire l'email client", icone: "envelope") {
                            demandeDestinataire = true
                        }
                    } else {
                        BoutonDiscret(titre: "Revoir l'email", icone: "envelope") {
                            session.etape = .emailPret
                        }
                    }
                }
                .popover(isPresented: $demandeDestinataire, arrowEdge: .bottom) {
                    VueDestinataire(session: session, affiche: $demandeDestinataire)
                }
            }

            DocumentLu(texte: session.compteRendu)

            HStack(spacing: 12) {
                BoutonDiscret(titre: "Nouveau compte rendu", icone: "plus") {
                    session.recommencer()
                }
                Text(session.cheminPDF == nil
                     ? "Rien n'est encore écrit sur le disque."
                     : "Rangé dans comptes-rendus/\(session.projet).")
                    .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
                Spacer()
                BoutonDiscret(titre: "Ajuster la rédaction", icone: "wand.and.stars") {
                    ajustement = true
                }
                .help("Dire ce qui n'allait pas dans ce compte rendu, pour que les "
                      + "prochains en tiennent compte.")
                BoutonDiscret(titre: "Exporter en Word", icone: "arrow.up.doc") {
                    session.exporterVersTraitementDeTexte()
                }
                .help("Écrit un document Word, à côté du compte rendu, pour "
                      + "l'annoter ou le faire relire. Le PDF reste le document "
                      + "de référence.")
                BoutonPrincipal(titre: "Enregistrer et produire le PDF",
                                icone: "square.and.arrow.down") {
                    session.enregistrer()
                }
            }
            .pied()
        }
        .background(Teinte.fond)
        .sheet(isPresented: $ajustement) {
            VueAjustement(session: session)
        }
    }
}

/// Le corps d'un document produit — compte rendu ou email. Une largeur de
/// lecture, du texte à chasse fixe, et rien autour : c'est le document qu'on
/// vient relire, pas l'application.
struct DocumentLu: View {
    let texte: String

    var body: some View {
        ScrollView {
            Text(texte)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Teinte.texte)
                .textSelection(.enabled)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(Teinte.carte,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Teinte.trait))
                .frame(maxWidth: 840, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 26).padding(.vertical, 20)
        }
    }
}
