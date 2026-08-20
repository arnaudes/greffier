import AppKit
import NoyauCR
import SwiftUI

/// La charte visuelle de l'application — direction « l'atelier de nuit »,
/// retenue le 17/08/2026 sur maquettes.
///
/// La tenue sombre reste celle d'origine : l'application vit à côté d'une
/// visioconférence et d'un transcript, et un fond clair fatigue en fin de
/// journée. Mais une salle de réunion baignée de soleil demande l'inverse —
/// d'où la seconde tenue, claire, et la bascule qui va avec.
///
/// Chaque couleur porte donc ses deux valeurs et se résout toute seule selon
/// l'apparence de la fenêtre. C'est ce qui permet aux écrans écrits avant le
/// mode clair de le recevoir sans une ligne de changement.
enum Teinte {

    /// Une couleur qui connaît ses deux versions.
    static func duo(sombre: Color, clair: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { apparence in
            let estSombre = apparence.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(estSombre ? sombre : clair)
        })
    }

    private static func rvb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    private static func duo(_ sombre: UInt32, _ clair: UInt32) -> Color {
        duo(sombre: rvb(sombre), clair: rvb(clair))
    }

    /// Le fond le plus bas, et la lueur qui le surmonte.
    static let fondUni = duo(0x0B1020, 0xF3F5FB)
    static let fondHaut = duo(0x17223F, 0xFFFFFF)

    static let bleu = duo(0x3168EC, 0x2A5BD7)
    static let bleuClair = duo(0x5B8CFF, 0x3C72F0)
    static let bleuNuit = duo(0x1F3C8E, 0x2A5BD7)
    static let bleuVif = duo(0x4A7BF5, 0x4D82F2)
    // En clair, le vert et l'ambre d'origine s'effacent sur du blanc : ils sont
    // assombris juste assez pour rester lisibles.
    static let vert = duo(0x34D399, 0x0F8F62)
    static let ambre = duo(0xFFC166, 0xA96A00)

    static let texte = duo(0xF4F6FB, 0x0F1729)
    static let texteDoux = duo(0x9AA6C0, 0x475069)
    static let texteFaible = duo(0x66718C, 0x78829B)

    static let trait = duo(sombre: .white.opacity(0.08), clair: .black.opacity(0.10))

    // Les fonds de surface. En sombre ce sont des voiles blancs, en clair des
    // voiles noirs : l'un est l'exact négatif de l'autre.
    /// Le fond d'une carte au repos.
    static let carte = duo(sombre: .white.opacity(0.04), clair: .black.opacity(0.035))
    /// Une carte plus affirmée, ou une pastille.
    static let carteVive = duo(sombre: .white.opacity(0.07), clair: .black.opacity(0.06))
    /// Ce qui est survolé ou sélectionné.
    static let survol = duo(sombre: .white.opacity(0.06), clair: .black.opacity(0.05))
    /// Le creux des panneaux latéraux.
    static let creux = duo(sombre: .black.opacity(0.18), clair: .black.opacity(0.035))
    /// La part de jauge qui reste à parcourir.
    static let jaugeVide = duo(sombre: .white.opacity(0.12), clair: .black.opacity(0.12))

    /// Le fond de l'application : une lueur haute qui s'éteint vers le bas.
    static var fond: some View {
        RadialGradient(colors: [fondHaut, fondUni],
                       center: .init(x: 0.5, y: -0.1),
                       startRadius: 0, endRadius: 900)
            .ignoresSafeArea()
    }

    static var degradeBouton: LinearGradient {
        LinearGradient(colors: [bleu, bleuVif], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var degradeMarque: LinearGradient {
        LinearGradient(colors: [bleuNuit, bleu], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Pièces réutilisées

/// La marque, reprise de l'icône : l'onde qui devient du texte.
struct Marque: View {
    var cote: CGFloat = 23
    var body: some View {
        RoundedRectangle(cornerRadius: cote * 0.3, style: .continuous)
            .fill(Teinte.degradeMarque)
            .frame(width: cote, height: cote)
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: cote * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// Le bouton principal : un seul par écran, celui qui fait avancer.
struct BoutonPrincipal: View {
    let titre: String
    var icone: String?
    var actif = true
    var pleineLargeur = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icone { Image(systemName: icone) }
                Text(titre).fontWeight(.semibold).lineLimit(1)
            }
            .fixedSize(horizontal: !pleineLargeur, vertical: false)
            .frame(maxWidth: pleineLargeur ? .infinity : nil)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.vertical, 10).padding(.horizontal, 24)
            .background(Teinte.degradeBouton, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: Teinte.bleu.opacity(actif ? 0.34 : 0), radius: 12, y: 6)
            .opacity(actif ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!actif)
    }
}

/// Une décision déjà prise, rappelée sans encombrer. Elles se lisent en un
/// coup d'œil et restent cliquables pour revenir dessus.
struct Acquis: View {
    let texte: String
    var valeur: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Teinte.vert)
            Text(texte).foregroundStyle(Teinte.texteDoux)
            if let valeur {
                Text(valeur).foregroundStyle(Teinte.texte).fontWeight(.medium)
            }
        }
        .font(.system(size: 11.5))
        .padding(.vertical, 5).padding(.horizontal, 11)
        .background(Teinte.carte, in: Capsule())
        .overlay(Capsule().strokeBorder(Teinte.trait))
    }
}

/// Un des choix proposés au centre de l'écran. Le premier est mis en avant :
/// c'est celui qu'on prend neuf fois sur dix.
struct CarteChoix: View {
    let icone: String
    let titre: String
    let detail: String
    var vedette = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(vedette ? AnyShapeStyle(Teinte.degradeBouton)
                                  : AnyShapeStyle(Teinte.carteVive))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: icone)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(vedette ? .white : Teinte.texteDoux)
                    }
                    .padding(.bottom, 7)
                // Deux lignes plutôt qu'une troncature : « Enregistrer a… » ne
                // dit pas ce que fait la carte, et la fenêtre est parfois plus
                // étroite que la mise en page ne le suppose.
                Text(titre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Teinte.texte)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(vedette ? Teinte.bleu.opacity(0.14) : Teinte.carte,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(vedette ? Teinte.bleu.opacity(0.55) : Teinte.trait))
            .shadow(color: Teinte.bleu.opacity(vedette ? 0.2 : 0), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }
}

/// L'avancement, en quatre traits plutôt qu'en pourcentage : on veut savoir
/// où l'on en est, pas combien il reste exactement.
struct Jauge: View {
    let etape: Int
    let total: Int
    var libelle: String?

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i < etape ? Teinte.bleu : Teinte.jaugeVide)
                        .frame(width: 22, height: 4)
                }
            }
            Text(libelle ?? "\(etape) sur \(total)")
                .font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
        }
    }
}

/// Un intertitre de colonne.
struct Intertitre: View {
    let texte: String
    var body: some View {
        Text(texte.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Teinte.texteFaible)
    }
}

/// L'en-tête commun à tous les écrans pleine page.
///
/// L'atelier a sa colonne de gauche pour se repérer ; les écrans suivants n'en
/// ont pas. Sans cet en-tête, on passait d'une interface tenue à des fenêtres
/// grises sans identité, et l'on ne savait plus où l'on en était dans la
/// chaîne. Il porte donc la marque, l'étape, et la bascule de tenue.
struct EnteteEcran<Accessoires: View>: View {
    let titre: String
    var detail: String?
    var etape: Int
    var libelleEtape: String
    var reglages: Reglages
    /// Le retour à l'accueil. Absent des écrans d'où l'on ne doit pas partir.
    var accueil: (() -> Void)?
    @ViewBuilder var accessoires: () -> Accessoires

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                // Sans ce bouton, la seule sortie de l'écran final était
                // « Nouveau compte rendu », qui efface tout : on ne pouvait pas
                // aller voir un dossier sans perdre son travail.
                if let accueil {
                    BoutonDiscret(titre: "Accueil", icone: "house") { accueil() }
                }
                Marque(cote: 21)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titre).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Teinte.texte)
                    if let detail {
                        Text(detail).font(.system(size: 11.5))
                            .foregroundStyle(Teinte.texteFaible)
                    }
                }
                Spacer(minLength: 16)
                accessoires()
                BasculeApparence(reglages: reglages)
            }
            HStack {
                Jauge(etape: etape, total: 4, libelle: libelleEtape)
                Spacer()
            }
        }
        .padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 14)
        .background(alignment: .bottom) {
            Rectangle().fill(Teinte.trait).frame(height: 1)
        }
    }
}

extension EnteteEcran where Accessoires == EmptyView {
    init(titre: String, detail: String? = nil, etape: Int,
         libelleEtape: String, reglages: Reglages, accueil: (() -> Void)? = nil) {
        self.init(titre: titre, detail: detail, etape: etape,
                  libelleEtape: libelleEtape, reglages: reglages,
                  accueil: accueil) { EmptyView() }
    }
}

/// L'action secondaire : présente, mais qui ne dispute pas la vedette au
/// bouton principal.
struct BoutonDiscret: View {
    let titre: String
    var icone: String?
    var actif = true
    /// Prend toute la largeur qu'on lui laisse. Deux boutons côte à côte se
    /// partagent alors la ligne à égalité — sans quoi chacun prend la largeur
    /// de son texte et la colonne part de travers.
    var pleineLargeur = false
    let action: () -> Void
    @State private var survole = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icone { Image(systemName: icone).font(.system(size: 11)) }
                // Sans cela, un libellé coupe au milieu d'un mot dès que la
                // colonne se resserre — « Consulte / r » dans le panneau de
                // droite, qui ne fait que 214 points utiles.
                Text(titre).font(.system(size: 12.5)).lineLimit(1)
            }
            .fixedSize(horizontal: !pleineLargeur, vertical: false)
            .frame(maxWidth: pleineLargeur ? .infinity : nil)
            .foregroundStyle(Teinte.texteDoux)
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(survole ? Teinte.survol : Teinte.carte,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Teinte.trait))
            .opacity(actif ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .onHover { survole = $0 }
    }
}

/// Une étiquette de catégorie — la famille d'une question, l'état d'un point.
struct Etiquette: View {
    let texte: String
    var couleur: Color = Teinte.texteDoux

    var body: some View {
        Text(texte)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(couleur)
            .padding(.vertical, 2.5).padding(.horizontal, 8)
            .background(couleur.opacity(0.13), in: Capsule())
    }
}

/// Un extrait du transcript, cité tel qu'il a été dit. La barre bleue le
/// distingue nettement de la question : l'un vient de la réunion, l'autre de
/// Claude, et les confondre ferait répondre à côté.
struct Citation: View {
    let texte: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule().fill(Teinte.bleu.opacity(0.55)).frame(width: 2.5)
            Text("« \(texte) »")
                .font(.system(size: 12.5)).italic()
                .foregroundStyle(Teinte.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9).padding(.horizontal, 11)
        .background(Teinte.carte, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Un choix parmi d'autres — d'un clic, et assez large pour qu'on ne vise pas.
/// Les questions rapides arrivent en premier (spécification § 3.4) : leur
/// enchaînement doit rester une suite de clics, pas une série de visées.
struct ChoixLigne: View {
    let texte: String
    let choisi: Bool
    var multiple = false
    let action: () -> Void
    @State private var survole = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbole)
                    .font(.system(size: 13))
                    .foregroundStyle(choisi ? Teinte.bleuClair : Teinte.texteFaible)
                Text(texte)
                    .font(.system(size: 12.5))
                    .foregroundStyle(choisi ? Teinte.texte : Teinte.texteDoux)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fond, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(choisi ? Teinte.bleu.opacity(0.5) : Teinte.trait))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survole = $0 }
    }

    private var symbole: String {
        if multiple { return choisi ? "checkmark.square.fill" : "square" }
        return choisi ? "largecircle.fill.circle" : "circle"
    }

    private var fond: Color {
        if choisi { return Teinte.bleu.opacity(0.14) }
        return survole ? Teinte.survol : Teinte.carte
    }
}

extension View {
    /// Un champ de saisie à la tenue de l'atelier : les champs du système
    /// tranchaient sur le reste, en clair comme en sombre.
    func champGreffier() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(Teinte.texte)
            .padding(.vertical, 8).padding(.horizontal, 11)
            .background(Teinte.carte,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Teinte.trait))
    }

    /// Le pied de page d'un écran : la barre où vit l'action principale.
    func pied() -> some View {
        padding(.horizontal, 26).padding(.vertical, 14)
            .background(alignment: .top) {
                Rectangle().fill(Teinte.trait).frame(height: 1)
            }
    }
}

/// Une barre de progression, quand le pourcentage est réel.
///
/// Elle n'apparaît que là où l'avancement est mesuré — la transcription connaît
/// la place du dernier mot reconnu dans l'enregistrement, la fusion audio le
/// nombre de tranches écrites. Là où Claude travaille, aucun pourcentage n'a de
/// sens : une barre qui avancerait au hasard vaudrait moins que pas de barre.
struct BarreProgression: View {
    let fraction: Double
    var largeur: CGFloat = 320

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .leading) {
                Capsule().fill(Teinte.jaugeVide).frame(height: 6)
                Capsule().fill(Teinte.degradeBouton)
                    .frame(width: max(6, largeur * min(1, max(0, fraction))), height: 6)
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
            .frame(width: largeur)
            Text("\(Int((fraction * 100).rounded())) %")
                .font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(Teinte.texteDoux)
        }
    }
}

/// Le temps passé sur un traitement, en clair.
///
/// Quand aucun pourcentage n'est possible, savoir qu'il s'est écoulé quarante
/// secondes suffit à distinguer « ça travaille » de « c'est bloqué ».
struct TempsEcoule: View {
    let depuis: Date
    @State private var maintenant = Date()

    private let battement = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(lisible)
            .font(.system(size: 11.5)).monospacedDigit()
            .foregroundStyle(Teinte.texteFaible)
            .onReceive(battement) { maintenant = $0 }
    }

    private var lisible: String {
        let s = Int(maintenant.timeIntervalSince(depuis))
        if s < 60 { return "\(s) s" }
        return "\(s / 60) min \(String(format: "%02d", s % 60)) s"
    }
}

/// Une pastille d'état : une couleur, un mot, et rien de plus.
///
/// Reprise du langage des menus de MacPaw, où l'on sait en une demi-seconde si
/// l'outil peut travailler. C'est le seul emprunt qui vaille ici : leurs
/// dégradés et leurs jauges circulaires habillent une densité d'information que
/// ce menu n'a pas.
struct PastilleEtat: View {
    let gravite: Prerequis.Gravite
    let texte: String
    var detail: String?

    private var couleur: Color {
        switch gravite {
        case .bien: Teinte.vert
        case .attention: Teinte.ambre
        case .bloquant: .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(couleur).frame(width: 8, height: 8).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(texte).font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Teinte.texte)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Teinte.texteFaible)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Un module du menu : un intertitre discret, puis du contenu.
///
/// La structure vient de MacPaw — des modules empilés séparés par un trait fin,
/// plutôt qu'une liste de lignes. Elle donne au menu sa lisibilité sans rien
/// emprunter à leur palette.
struct ModuleMenu<Contenu: View>: View {
    var titre: String?
    var premier = false
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !premier {
                Rectangle().fill(Teinte.trait).frame(height: 1).padding(.vertical, 3)
            }
            if let titre {
                Text(titre.uppercased())
                    .font(.system(size: 9.5, weight: .bold)).tracking(1.1)
                    .foregroundStyle(Teinte.texteFaible)
            }
            contenu()
        }
    }
}

/// Ouvrir la fenêtre des réglages, depuis n'importe où.
///
/// Elle s'ouvrait par `NSApp.sendAction(Selector(("showSettingsWindow:")))` :
/// un sélecteur privé, deviné, envoyé à personne en particulier — il remonte
/// la chaîne des répondeurs depuis la fenêtre active. **Le bouton du bandeau
/// d'accueil ne faisait donc rien**, puisqu'on clique justement là quand
/// aucune fenêtre n'est au premier plan. Apple a par ailleurs renommé ce
/// sélecteur entre deux versions de macOS, sans qu'aucun avertissement ne le
/// signale : un appel qui échoue en silence.
///
/// `openSettings` fait la même chose, mais c'est l'interface officielle : elle
/// ouvre la scène `Settings` déclarée par l'application, sans rien deviner.
struct BoutonReglages: View {
    var titre = "Ouvrir les réglages"
    var icone = "gearshape"
    var pleineLargeur = false
    /// Ce qu'il faut faire avant — ramener la fenêtre principale, depuis le
    /// menu de la barre.
    var avant: (() -> Void)?
    @Environment(\.openSettings) private var ouvrirLesReglages

    var body: some View {
        BoutonDiscret(titre: titre, icone: icone, pleineLargeur: pleineLargeur) {
            avant?()
            ouvrirLesReglages()
        }
    }
}

/// Une explication qui ne s'impose pas : un point d'interrogation qu'on ouvre.
///
/// Deux notions décident de la valeur d'un compte rendu — la différence entre
/// une décision et une piste, et le filtrage de ce qui part au client — et
/// **elles n'étaient nommées nulle part à l'écran**. Le 19/08/2026, celui qui a
/// commandé l'application ne les a pas reconnues quand on l'a interrogé
/// dessus : trois personnes qui la découvrent ne les reconnaîtront pas
/// davantage.
///
/// Un chapitre d'aide vieillirait mal. Une explication posée à l'endroit exact
/// où la question se pose, non.
struct Explication: View {
    let titre: String
    let texte: String
    @State private var ouverte = false

    var body: some View {
        Button { ouverte.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11.5))
                .foregroundStyle(ouverte ? Teinte.bleuClair : Teinte.texteFaible)
        }
        .buttonStyle(.plain)
        .help(titre)
        .popover(isPresented: $ouverte, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(titre).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Teinte.texte)
                Text(texte).font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 320)
            .background(Teinte.fondHaut)
        }
    }
}

/// « Greffier a été mis à jour. » — dit une fois, puis jamais plus.
///
/// On installait, l'application redémarrait, et **rien ne disait si c'était
/// passé**. On rouvrait le menu pour vérifier, sans en être sûr, et l'on
/// finissait par ne plus se mettre à jour du tout. Une mise à jour qu'on ne
/// voit pas aboutir est une mise à jour qu'on cesse de faire.
struct BandeauMiseAJourFaite: View {
    let version: String
    var notes: String?
    let fermer: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15)).foregroundStyle(Teinte.vert)
            VStack(alignment: .leading, spacing: 3) {
                Text("Greffier a été mis à jour en \(version).")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Teinte.texte)
                if let notes, !notes.isEmpty {
                    Text(notes).font(.system(size: 11.5))
                        .foregroundStyle(Teinte.texteDoux)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            BoutonDiscret(titre: "Ce qui change", icone: "arrow.up.forward") {
                NSWorkspace.shared.open(URL(string:
                    "https://github.com/\(VerificationVersion.depotParDefaut)/releases")!)
            }
            Button(action: fermer) {
                Image(systemName: "xmark").font(.system(size: 10))
                    .foregroundStyle(Teinte.texteFaible)
            }
            .buttonStyle(.plain)
            .help("Fermer. Ce bandeau ne reviendra pas.")
        }
        .padding(.horizontal, 22).padding(.vertical, 13)
        .background(Teinte.vert.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Teinte.trait).frame(height: 1)
        }
    }
}

/// Ce qui manque pour que Greffier travaille bien, dit là où on le verra.
///
/// **Rien ne l'annonçait.** L'avertissement sur l'identité incomplète vivait
/// dans un onglet des réglages qu'un nouvel utilisateur n'a aucune raison
/// d'ouvrir, et l'état des autorisations dans le menu de la barre. Quelqu'un
/// qui découvre l'application enregistrerait sa première réunion, obtiendrait
/// un compte rendu impersonnel et plat, et ne saurait jamais pourquoi.
///
/// C'est le moment où l'on abandonne un outil : au premier essai, quand le
/// résultat déçoit sans qu'on comprenne ce qui a manqué.
struct BandeauAccueil: View {
    let manques: [String]
    let bloquant: Bool
    var ecarter: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: bloquant ? "exclamationmark.triangle.fill" : "hand.wave")
                .font(.system(size: 14))
                .foregroundStyle(bloquant ? Teinte.ambre : Teinte.bleuClair)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(bloquant
                     ? "Greffier n'est pas prêt à travailler"
                     : "Présentez-vous à Greffier")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Teinte.texte)
                Text(manques.joined(separator: " · "))
                    .font(.system(size: 11.5)).foregroundStyle(Teinte.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            BoutonReglages()
            if let ecarter {
                Button { ecarter() } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                        .foregroundStyle(Teinte.texteFaible).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Ne plus afficher. Tout reste consultable dans les réglages.")
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 11)
        .background((bloquant ? Teinte.ambre : Teinte.bleu).opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill((bloquant ? Teinte.ambre : Teinte.bleu).opacity(0.3))
                .frame(height: 1)
        }
    }
}

/// La bascule entre la tenue sombre et la tenue claire, posée dans l'en-tête :
/// on change de lumière quand la pièce change, pas en ouvrant les réglages.
struct BasculeApparence: View {
    @Bindable var reglages: Reglages
    @State private var survole = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                reglages.apparence = reglages.apparence.suivante
            }
        } label: {
            Image(systemName: reglages.apparence.symbole)
                .font(.system(size: 11.5))
                .foregroundStyle(Teinte.texteDoux)
                .frame(width: 24, height: 24)
                .background(survole ? Teinte.survol : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { survole = $0 }
        .help(reglages.apparence == .clair
              ? "Passer en tenue sombre"
              : "Passer en tenue claire")
    }
}

extension View {
    /// Le cartouche des panneaux latéraux : un fond légèrement creusé.
    func panneau(bordureGauche: Bool = false) -> some View {
        background(Teinte.creux)
            .overlay(alignment: bordureGauche ? .leading : .trailing) {
                Rectangle().fill(Teinte.trait).frame(width: 1)
            }
    }
}
