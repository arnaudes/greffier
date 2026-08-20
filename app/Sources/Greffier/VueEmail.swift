import SwiftUI
import NoyauCR

/// Le filtrage, point par point, avant de rédiger l'email client
/// (spécification § 7.3).
///
/// Claude propose ce qui peut sortir ; l'utilisateur ajuste. Rien ne part au client
/// sans être passé par cet écran — et l'outil ne fait que produire le fichier,
/// il n'envoie jamais.
struct VueFiltrage: View {
    @Bindable var session: Session

    private var points: [String] {
        session.questionsFiltrage.flatMap { $0.options ?? [] }
    }

    var body: some View {
        VStack(spacing: 0) {
            EnteteEcran(titre: "Que souhaitez-vous transmettre au client ?",
                        detail: "Les points décochés restent internes. "
                              + "La proposition vient de Claude, c'est vous qui tranchez.",
                        etape: 4, libelleEtape: "L'email client",
                        reglages: session.reglages,
                        accueil: { session.revenirALAccueil() }) {
                Explication(
                    titre: "Pourquoi filtrer ?",
                    texte: "Votre compte rendu est interne : il peut contenir des tarifs "
                         + "journaliers, des estimations de charge, des réserves sur le "
                         + "client, ou une phrase dite « entre nous ».\n\n"
                         + "L'email au client en est dérivé, mais tout n'a pas à en "
                         + "sortir. Claude propose ce qui peut être transmis ; vous "
                         + "décochez le reste.\n\n"
                         + "Ce que vous écartez ici reste dans le compte rendu interne. "
                         + "Rien n'est effacé, rien n'est envoyé : l'email est écrit sur "
                         + "le disque, c'est vous qui l'envoyez.")
                BoutonDiscret(titre: points.count == session.pointsRetenus.count
                                     ? "Tout décocher" : "Tout cocher") {
                    if points.count == session.pointsRetenus.count {
                        session.pointsRetenus = []
                    } else {
                        session.pointsRetenus = Set(points)
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(points, id: \.self) { point in
                        let interne = point.localizedCaseInsensitiveContains("— interne")
                        ChoixLigne(texte: point,
                                   choisi: session.pointsRetenus.contains(point),
                                   multiple: true) {
                            if session.pointsRetenus.contains(point) {
                                session.pointsRetenus.remove(point)
                            } else {
                                session.pointsRetenus.insert(point)
                            }
                        }
                        .opacity(interne ? 0.6 : 1)
                    }
                    if points.isEmpty {
                        Text("Claude n'a rien proposé à transmettre.")
                            .font(.system(size: 12.5)).foregroundStyle(Teinte.texteFaible)
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 26).padding(.vertical, 20)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                BoutonDiscret(titre: "Revenir au compte rendu", icone: "arrow.left") {
                    session.etape = .resultat
                }
                Text("\(session.pointsRetenus.count) point"
                     + "\(session.pointsRetenus.count > 1 ? "s" : "") retenu"
                     + "\(session.pointsRetenus.count > 1 ? "s" : "") sur \(points.count)")
                    .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
                    .monospacedDigit()
                Spacer()
                BoutonPrincipal(titre: "Rédiger l'email", icone: "pencil.line",
                                actif: !session.pointsRetenus.isEmpty) {
                    Task { await session.redigerEmail() }
                }
            }
            .pied()
        }
        .background(Teinte.fond)
    }
}

/// L'email produit. Il est écrit sur disque et jamais envoyé : c'est vous
/// qui l'envoyez — l'application ne fait que le préparer.
struct VueEmail: View {
    @Bindable var session: Session
    @State private var copie = false

    var body: some View {
        VStack(spacing: 0) {
            EnteteEcran(titre: "Email à destination du client",
                        detail: session.destinataire.isEmpty
                            ? nil : "Pour \(session.destinataire)",
                        etape: 4, libelleEtape: "L'email client",
                        reglages: session.reglages,
                        accueil: { session.revenirALAccueil() }) {
                BoutonDiscret(titre: copie ? "Copié" : "Copier",
                              icone: copie ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.emailClient, forType: .string)
                    copie = true
                }
            }

            DocumentLu(texte: session.emailClient)

            HStack(spacing: 12) {
                BoutonDiscret(titre: "Revenir au compte rendu", icone: "arrow.left") {
                    session.etape = .resultat
                }
                HStack(spacing: 5) {
                    Image(systemName: "info.circle").font(.system(size: 10.5))
                    Text(session.cheminEmail.map { "Enregistré sous \($0.lastPathComponent)." }
                         ?? "Greffier n'envoie rien : c'est un brouillon, vous l'enverrez vous-même.")
                }
                .font(.system(size: 11.5)).foregroundStyle(Teinte.texteFaible)
                Spacer()
                BoutonDiscret(titre: "Ouvrir un brouillon", icone: "envelope.open") {
                    session.ouvrirLeBrouillon()
                }
                .help("Prépare le message dans votre logiciel de courrier. "
                      + "Greffier n'envoie jamais : c'est vous qui envoyez.")
                BoutonPrincipal(titre: "Enregistrer", icone: "square.and.arrow.down") {
                    session.enregistrerEmail()
                }
            }
            .pied()
        }
        .background(Teinte.fond)
    }
}

/// Le petit formulaire qui précède le filtrage : à qui l'email s'adresse.
struct VueDestinataire: View {
    @Bindable var session: Session
    @Binding var affiche: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("À qui cet email s'adresse-t-il ?")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Teinte.texte)

            VStack(alignment: .leading, spacing: 4) {
                Text("Destinataire").font(.system(size: 11.5))
                    .foregroundStyle(Teinte.texteDoux)
                TextField("Prénom Nom", text: $session.destinataire).champGreffier()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Entreprise").font(.system(size: 11.5))
                    .foregroundStyle(Teinte.texteDoux)
                TextField("", text: $session.entrepriseClient).champGreffier()
            }

            HStack(spacing: 10) {
                Spacer()
                BoutonDiscret(titre: "Annuler") { affiche = false }
                BoutonPrincipal(titre: "Continuer", actif: session.pretAFiltrer) {
                    affiche = false
                    Task { await session.demanderFiltrage() }
                }
            }
            .padding(.top, 4)
        }
        .padding(22).frame(width: 380)
        .background(Teinte.fondHaut)
    }
}
