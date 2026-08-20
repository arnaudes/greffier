import SwiftUI
import NoyauCR

/// La phase d'interrogation, cœur de l'outil.
///
/// Les questions arrivent par vagues, les plus rapides d'abord (spécification
/// § 3.4) : une série de réponses à un clic s'enchaîne sans rupture de rythme,
/// alors qu'un arbitrage placé en troisième position arrête tout.
///
/// C'est l'écran où l'on passe le plus de temps, et celui qui décide si l'outil
/// est utilisé ou abandonné : il porte la même tenue que l'atelier.
struct VueInterrogation: View {
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 0) {
            EnteteEcran(titre: session.libelleVague,
                        detail: session.tourDInterrogation > 1
                            ? "Tour \(session.tourDInterrogation) — vos réponses en ont ouvert d'autres."
                            : "Répondez à ce que vous savez ; laissez le reste de côté.",
                        etape: 2, libelleEtape: "Les questions",
                        reglages: session.reglages,
                        accueil: { session.revenirALAccueil() }) {
                Explication(
                    titre: "Pourquoi ces questions ?",
                    texte: "Un moteur de transcription se trompe avec aplomb : il écrit "
                         + "des mots plausibles à la place des noms propres et du "
                         + "vocabulaire métier, sans jamais signaler qu'il hésite.\n\n"
                         + "Plutôt que de lisser, Greffier demande. Une question de trop "
                         + "coûte deux secondes ; une invention coûte la crédibilité d'un "
                         + "document envoyé à un client.\n\n"
                         + "Vos réponses entrent dans le lexique : les mêmes termes ne "
                         + "seront plus jamais redemandés, et le prochain compte rendu de "
                         + "ce dossier posera moins de questions.\n\n"
                         + "Ce que vous laissez sans réponse n'est jamais tranché à votre "
                         + "place : le point ressort en « à confirmer » dans le compte "
                         + "rendu.")
                avancement
            }

            vagues

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(session.questionsDeLaVague) { question in
                        CarteQuestion(question: question, session: session)
                    }
                    if session.questionsDeLaVague.isEmpty {
                        Text("Aucune question dans cette vague.")
                            .font(.system(size: 12.5)).foregroundStyle(Teinte.texteFaible)
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 26).padding(.vertical, 20)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            barreDuBas
        }
        .background(Teinte.fond)
    }

    /// Le compte des réponses, en clair. C'est lui qui dit s'il reste beaucoup
    /// à faire — un pourcentage ne l'aurait pas dit aussi bien.
    private var avancement: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10)).foregroundStyle(Teinte.vert)
            Text("\(session.nombreRepondu) sur \(session.questions.count)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Teinte.texteDoux)
                .monospacedDigit()
        }
        .padding(.vertical, 5).padding(.horizontal, 11)
        .background(Teinte.carte, in: Capsule())
        .overlay(Capsule().strokeBorder(Teinte.trait))
        .help("Les questions sans réponse ne sont jamais tranchées à votre place : "
              + "elles ressortent en points à confirmer dans le compte rendu.")
    }

    /// Les vagues, cliquables : on peut revenir sur la précédente sans perdre
    /// ce qui a déjà été répondu.
    private var vagues: some View {
        HStack(spacing: 7) {
            ForEach(session.vagues, id: \.self) { vague in
                PastilleVague(numero: vague,
                              active: vague == session.vagueAffichee,
                              complete: session.vagueEstComplete(vague)) {
                    session.vagueAffichee = vague
                }
            }
            Spacer()
        }
        .padding(.horizontal, 26).padding(.top, 14)
    }

    private var barreDuBas: some View {
        HStack(spacing: 12) {
            BoutonDiscret(titre: "Rédiger sans répondre au reste") {
                Task { await session.redigerSansAttendre() }
            }
            .help("Les points laissés sans réponse seront signalés dans le compte rendu, "
                  + "jamais tranchés à votre place.")

            Spacer()

            if let suivante = session.vagues.first(where: { $0 > session.vagueAffichee }) {
                BoutonPrincipal(titre: "Vague suivante", icone: "arrow.right") {
                    session.vagueAffichee = suivante
                }
            } else {
                BoutonPrincipal(titre: "Transmettre mes réponses", icone: "paperplane.fill") {
                    Task { await session.transmettreReponses() }
                }
            }
        }
        .pied()
    }
}

/// Une vague dans le fil : son numéro, et le fait qu'elle soit finie ou non.
struct PastilleVague: View {
    let numero: Int
    let active: Bool
    let complete: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if complete && !active {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Teinte.vert)
                }
                Text("Vague \(numero)")
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? .white : Teinte.texteDoux)
            .padding(.vertical, 5).padding(.horizontal, 11)
            .background(active ? AnyShapeStyle(Teinte.degradeBouton)
                               : AnyShapeStyle(Teinte.carte), in: Capsule())
            .overlay(Capsule().strokeBorder(active ? .clear : Teinte.trait))
        }
        .buttonStyle(.plain)
    }
}

/// Une question, avec l'extrait qui la motive — le seul moyen de répondre sans
/// réécouter la réunion.
struct CarteQuestion: View {
    let question: Question
    @Bindable var session: Session
    @State private var texteLibre = ""

    private var reponse: String { session.reponses[question.id] ?? "" }
    private var repondu: Bool { !reponse.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Etiquette(texte: question.famille.libelle, couleur: Teinte.bleuClair)
                if let h = question.horodatage {
                    Text(h).font(.system(size: 10.5).monospaced())
                        .foregroundStyle(Teinte.texteFaible)
                }
                if let n = question.occurrences, n > 1 {
                    Text("\(n) occurrences").font(.system(size: 10.5))
                        .foregroundStyle(Teinte.texteFaible)
                }
                Spacer()
                if repondu {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13)).foregroundStyle(Teinte.vert)
                }
            }

            Text(question.question)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Teinte.texte)
                .fixedSize(horizontal: false, vertical: true)

            if question.extrait != "—" && !question.extrait.isEmpty {
                Citation(texte: question.extrait)
            }

            controles

            if question.saisieLibre {
                TextField("…ou répondez librement", text: $texteLibre, axis: .vertical)
                    .lineLimit(1...4)
                    .champGreffier()
                    .onChange(of: texteLibre) { _, neuf in
                        if !neuf.isEmpty { session.reponses[question.id] = neuf }
                    }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Teinte.carte,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(repondu ? Teinte.vert.opacity(0.3) : Teinte.trait))
    }

    @ViewBuilder private var controles: some View {
        switch question.type {
        case .ouiNon:
            HStack(spacing: 9) {
                choix("Oui"); choix("Non")
            }
        case .choixUnique, .date:
            VStack(alignment: .leading, spacing: 7) {
                ForEach(question.options ?? [], id: \.self) { choix($0) }
            }
        case .choixMultiple:
            VStack(alignment: .leading, spacing: 7) {
                ForEach(question.options ?? [], id: \.self) { option in
                    ChoixLigne(texte: option,
                               choisi: reponse.contains(option),
                               multiple: true) {
                        var retenus = reponse.isEmpty
                            ? [] : reponse.components(separatedBy: " · ")
                        if retenus.contains(option) { retenus.removeAll { $0 == option } }
                        else { retenus.append(option) }
                        session.reponses[question.id] = retenus.joined(separator: " · ")
                    }
                }
            }
        case .texte:
            EmptyView()  // le champ libre plus bas suffit
        }
    }

    private func choix(_ option: String) -> some View {
        ChoixLigne(texte: option, choisi: reponse == option) {
            session.reponses[question.id] = reponse == option ? "" : option
            texteLibre = ""
        }
    }
}
