import SwiftUI
import NoyauCR

/// Régler la forme des documents produits — le PDF comme le document Word.
///
/// Les couleurs vivaient dans un gabarit posé à côté de l'application, que
/// personne d'autre n'avait : sans lui, aucun PDF ne sortait. Elles sont
/// maintenant des valeurs, réglables ici, et elles valent pour les deux
/// documents à la fois — un compte rendu ne doit pas changer d'allure selon
/// qu'on l'imprime ou qu'on l'envoie.
struct VueCharte: View {
    let racine: URL
    /// Ce qui s'affiche au-dessus du titre, pour l'aperçu. Il vient de votre
    /// fiche, jamais du code.
    var surTitre = ""

    @State private var charte = Charte.parDefaut
    @State private var confirmeLeRetour = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("La forme de vos documents")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)
                Text("Ces couleurs habillent le PDF et le document Word. Elles s'écrivent "
                     + "en hexadécimal, à six chiffres et sans dièse — c'est la forme que "
                     + "Word accepte, et le PDF s'en accommode.")
                    .font(.system(size: 12)).foregroundStyle(Teinte.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)

                apercu

                Intertitre(texte: "Ce qui porte l'identité")
                couleur("Accent", "Les filets de section, les numéros et les puces.",
                        valeur: $charte.accent)
                couleur("Bandeau, début", "Le fond du bandeau de tête.",
                        valeur: $charte.bandeauDebut)
                couleur("Bandeau, fin", "Le PDF fond les deux teintes ; Word retient "
                        + "la première, faute de savoir dégrader.",
                        valeur: $charte.bandeauFin)
                couleur("En-tête de tableau", "Le fond de la première ligne d'un tableau.",
                        valeur: $charte.enteteTableau)

                Intertitre(texte: "Le texte")
                couleur("Titres", "Les titres de section et de sous-section.",
                        valeur: $charte.encreForte)
                couleur("Corps", "Le texte courant.", valeur: $charte.encre)
                couleur("Libellés", "La colonne de gauche de la fiche de tête.",
                        valeur: $charte.encreDouce)
                couleur("Pagination", "Le « Page 2 / 7 » au bas des pages.",
                        valeur: $charte.encreFaible)

                Intertitre(texte: "Les fonds et les filets")
                couleur("Filets", "Les traits qui séparent les lignes d'un tableau.",
                        valeur: $charte.filet)
                couleur("Une ligne sur deux", "Le fond alterné des tableaux.",
                        valeur: $charte.fondAlterne)
                couleur("Encadré d'information", "Le liseré d'un encadré ordinaire.",
                        valeur: $charte.information)
                couleur("Encadré d'avertissement", "Celui des encadrés marqués d'un ⚠.",
                        valeur: $charte.avertissement)

                Intertitre(texte: "La typographie")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("Police").font(.system(size: 12.5)).foregroundStyle(Teinte.texte)
                            .frame(width: 150, alignment: .leading)
                        TextField("Celle du système", text: $charte.police).champGreffier()
                    }
                    Text("Laissez vide pour celle du système, qui est le choix sûr : une "
                         + "police absente chez votre destinataire est remplacée sans "
                         + "prévenir, et le document s'abîme à l'ouverture. Le document "
                         + "Word emploie alors Calibri, que Word installe partout.")
                        .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Text("Taille du texte").font(.system(size: 12.5))
                        .foregroundStyle(Teinte.texte)
                        .frame(width: 150, alignment: .leading)
                    Stepper(value: $charte.tailleCorps, in: 8...14, step: 0.5) {
                        Text(String(format: "%.1f points", charte.tailleCorps))
                            .font(.system(size: 12.5)).foregroundStyle(Teinte.texteDoux)
                    }
                }

                HStack(spacing: 10) {
                    BoutonPrincipal(titre: "Enregistrer la charte",
                                    icone: "square.and.arrow.down") {
                        try? charte.enregistrer(racine: racine)
                        confirmeLeRetour = false
                    }
                    BoutonDiscret(titre: confirmeLeRetour
                                  ? "Confirmer le retour aux couleurs d'origine"
                                  : "Revenir aux couleurs d'origine",
                                  icone: "arrow.uturn.backward") {
                        // Un clic distrait effacerait une charte réglée
                        // couleur par couleur : on la redemande une fois.
                        if !confirmeLeRetour { confirmeLeRetour = true; return }
                        charte = .parDefaut
                        try? charte.enregistrer(racine: racine)
                        confirmeLeRetour = false
                    }
                    Spacer()
                }
                .padding(.top, 6)

                Text("La charte est enregistrée dans « charte.json », à la racine de votre "
                     + "dossier de travail. Elle suit vos documents quand vous les "
                     + "sauvegardez, et se corrige aussi à la main.")
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }
        .background(Teinte.fondUni)
        .task { charte = Charte.charger(racine: racine) }
    }

    /// Ce que donneront les documents, en petit. Un code hexadécimal ne dit
    /// rien tant qu'on ne l'a pas vu posé.
    private var apercu: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(surTitre.isEmpty ? "GREFFIER" : "GREFFIER · \(surTitre.uppercased())")
                    .font(.system(size: 8, weight: .bold)).kerning(1.2)
                    .foregroundStyle(.white.opacity(0.75))
                Text("Compte rendu de réunion")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(teinte(charte.bandeauDebut))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("1.").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(teinte(charte.accent))
                    Text("Un titre de section").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(teinte(charte.encreForte))
                }
                Rectangle().fill(teinte(charte.accent)).frame(height: 2)
                Text("Le texte courant, dans la couleur du corps.")
                    .font(.system(size: 10)).foregroundStyle(teinte(charte.encre))
                HStack(spacing: 0) {
                    Text("EN-TÊTE").font(.system(size: 7, weight: .bold)).kerning(0.8)
                        .foregroundStyle(.white)
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(teinte(charte.enteteTableau))
                }
                Text("Une ligne de tableau").font(.system(size: 9))
                    .foregroundStyle(teinte(charte.encre))
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(teinte(charte.fondAlterne))
                HStack(spacing: 0) {
                    Rectangle().fill(teinte(charte.information)).frame(width: 3)
                    Text("Un encadré d'information.").font(.system(size: 9))
                        .foregroundStyle(teinte(RenduWord.assombrir(charte.information)))
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(teinte(RenduWord.eclaircir(charte.information)))
                }
            }
            .padding(12)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Teinte.trait))
    }

    private func couleur(_ titre: String, _ aide: String,
                         valeur: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text(titre).font(.system(size: 12.5)).foregroundStyle(Teinte.texte)
                    .frame(width: 150, alignment: .leading)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(teinte(valeur.wrappedValue))
                    .frame(width: 30, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Teinte.trait))
                TextField("2563EB", text: valeur).champGreffier().frame(width: 100)
                if !Charte.estUneCouleur(valeur.wrappedValue) {
                    Text("Six chiffres de 0 à F.").font(.system(size: 11))
                        .foregroundStyle(Teinte.ambre)
                }
                Spacer()
            }
            Text(aide).font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                .padding(.leading, 160)
        }
    }

    /// Une couleur écrite en hexadécimal, telle qu'elle s'affichera.
    private func teinte(_ hexa: String) -> Color {
        guard Charte.estUneCouleur(hexa), let v = Int(hexa, radix: 16) else { return .gray }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}
