import SwiftUI
import NoyauCR

/// Les détails de la réunion, ouverts depuis les pastilles du fil.
///
/// Ils ne sont pas sur l'écran principal parce qu'ils se remplissent seuls dans
/// le cas courant — la réunion vient du calendrier. Ne les afficher qu'à la
/// demande évite de présenter un formulaire pour quelque chose qui, la plupart
/// du temps, n'a pas à être saisi.
struct VueDetails: View {
    @Bindable var session: Session
    @Binding var affiche: Bool
    @State private var nouveauDossier = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("La réunion").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Teinte.texte)

            choixDuDossier

            champ("Intitulé de la réunion", $session.titreReunion)
            quandLaReunionAEuLieu
            champ("Participants", $session.participants, aide: "Séparés par une virgule.")
            if session.entree != .doublePiste { champ("Lieu", $session.lieu) }

            Divider().overlay(Teinte.trait)

            Text("Comment on capte").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Teinte.texte)
            VStack(alignment: .leading, spacing: 6) {
                option("Transcript collé", .collage)
                option("Micro seul, en présentiel", .microSeul)
                option("Visioconférence en deux pistes", .doublePiste)
                option("Notes prises à la main", .notes)
            }
            Text(session.entree == .doublePiste
                 ? "L'attribution des propos est connue : aucune question là-dessus."
                 : "Sans attribution des locuteurs, Claude devra demander qui a dit quoi.")
                .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Teinte.trait)

            Toggle(isOn: $session.perimetreRestreint) {
                Text("Ne retenir qu'un sujet de la réunion")
                    .font(.system(size: 12.5)).foregroundStyle(Teinte.texte)
            }
            .toggleStyle(.switch).tint(Teinte.bleu)
            if session.perimetreRestreint {
                TextField("par exemple : uniquement la partie sur le devis",
                          text: $session.sujet, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
                Text("Le compte rendu mentionnera son périmètre en encadré.")
                    .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
            }

            HStack {
                Spacer()
                BoutonPrincipal(titre: "Terminé") {
                    session.rafraichirLeContexte()
                    affiche = false
                }
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 380)
        .background(Teinte.fondHaut)
    }

    /// Le dossier où le compte rendu sera rangé.
    ///
    /// C'était un champ libre doublé de quatre pastilles : d'où « Menuiserie Vidal »,
    /// « menuiseries vidal » et « MENUISERIES VIDAL » pour un même client. Les dossiers
    /// existants se choisissent maintenant dans une liste, et il faut demander
    /// explicitement à en créer un — la saisie libre reste possible, elle n'est
    /// simplement plus le chemin par défaut.
    private var choixDuDossier: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Projet ou client").font(.system(size: 11.5))
                .foregroundStyle(Teinte.texteDoux)

            if nouveauDossier || session.dossiers.isEmpty {
                TextField("Nom du client ou du projet", text: $session.projet)
                    .champGreffier()
                if !session.dossiers.isEmpty {
                    BoutonDiscret(titre: "Choisir un dossier existant", icone: "list.bullet") {
                        nouveauDossier = false
                    }
                }
                if let proche = dossierProche {
                    Label("Un dossier « \(proche) » existe déjà. Est-ce le même ?",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Teinte.ambre)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { session.projet },
                        set: { session.choisirDossier($0) })) {
                        if session.projet.isEmpty {
                            Text("Choisissez un dossier").tag("")
                        }
                        ForEach(session.dossiers, id: \.nom) { dossier in
                            Text("\(dossier.nom)  (\(dossier.nombre))").tag(dossier.nom)
                        }
                    }
                    .labelsHidden()
                    BoutonDiscret(titre: "Nouveau", icone: "plus") {
                        session.projet = ""
                        nouveauDossier = true
                    }
                }
            }

            Text("C'est lui qui décide où le compte rendu sera rangé.")
                .font(.system(size: 10.5)).foregroundStyle(Teinte.texteFaible)
        }
    }

    /// Un dossier existant qui ressemble à celui qu'on est en train de nommer.
    private var dossierProche: String? {
        let saisi = session.projet.trimmingCharacters(in: .whitespaces)
        guard saisi.count >= 3 else { return nil }
        let cible = Lexique.compacterPublic(saisi)
        return session.dossiers.map(\.nom).first { nom in
            let candidat = Lexique.compacterPublic(nom)
            return candidat != cible && Lexique.similaritePublique(cible, candidat) >= 0.82
        }
    }

    /// La date au calendrier et l'heure à l'horloge, plutôt qu'en toutes
    /// lettres : c'est le seul champ de cet écran dont la valeur pouvait être
    /// fausse sans que rien ne s'en aperçoive.
    private var quandLaReunionAEuLieu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Date et heure").font(.system(size: 11.5))
                .foregroundStyle(Teinte.texteDoux)
            DatePicker("", selection: $session.quandDate,
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.field)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "fr_FR"))
            Text(session.quand)
                .font(.system(size: 10.5)).foregroundStyle(Teinte.texteFaible)
        }
    }

    private func champ(_ titre: String, _ valeur: Binding<String>, aide: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
            TextField("", text: valeur).textFieldStyle(.roundedBorder)
            if let aide {
                Text(aide).font(.system(size: 10.5)).foregroundStyle(Teinte.texteFaible)
            }
        }
    }

    private func option(_ titre: String, _ valeur: TypeEntree) -> some View {
        Button {
            session.entree = valeur
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .strokeBorder(session.entree == valeur ? Teinte.bleu : Teinte.texteFaible,
                                  lineWidth: 1.5)
                    .background(Circle().fill(session.entree == valeur ? Teinte.bleu : .clear)
                        .padding(3.5))
                    .frame(width: 14, height: 14)
                Text(titre).font(.system(size: 12.5))
                    .foregroundStyle(session.entree == valeur ? Teinte.texte : Teinte.texteDoux)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Une pastille du fil, cliquable : c'est par elle qu'on revient sur une
/// décision déjà prise.
struct PastilleFil: View {
    let texte: String
    var valeur: String?
    var manquant = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: manquant ? "plus.circle" : "checkmark")
                    .font(.system(size: manquant ? 10 : 9, weight: .bold))
                    .foregroundStyle(manquant ? Teinte.texteFaible : Teinte.vert)
                // Une pastille tient sur une ligne : un nom de dossier un peu
                // long l'étirait sur trois, et le fil de la réunion perdait sa
                // forme de fil.
                if !texte.isEmpty {
                    Text(texte).foregroundStyle(Teinte.texteDoux).lineLimit(1)
                }
                if let valeur {
                    Text(valeur).foregroundStyle(Teinte.texte).fontWeight(.medium)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .font(.system(size: 11.5))
            .padding(.vertical, 5).padding(.horizontal, 11)
            .background(Teinte.carte, in: Capsule())
            .overlay(Capsule().strokeBorder(
                manquant ? Teinte.bleu.opacity(0.4) : Teinte.trait))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
