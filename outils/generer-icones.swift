import AppKit
import Foundation

// Générateur de propositions d'icône pour Greffier.
//
// La méthode : dessiner en AppKit, rendre une planche à taille réelle sur
// fond clair et sombre, et choisir sur pièces. À l'œil, un
// détail de trois points se discute ; sur planche, il se tranche.
//
//   swiftc -O outils/generer-icones.swift -o /tmp/generer-icones && /tmp/generer-icones <sortie.png>

// MARK: - Charte

let bleuFonce = NSColor(srgbRed: 0x1F/255, green: 0x3C/255, blue: 0x8E/255, alpha: 1)
let bleuMoyen = NSColor(srgbRed: 0x29/255, green: 0x53/255, blue: 0xCE/255, alpha: 1)
let bleuClair = NSColor(srgbRed: 0x31/255, green: 0x68/255, blue: 0xEC/255, alpha: 1)
let ambre = NSColor(srgbRed: 0xFF/255, green: 0xC1/255, blue: 0x66/255, alpha: 1)
let blanc = NSColor.white

/// Le squircle d'Apple n'est pas un rectangle à coins arrondis : son arrondi
/// est une superellipse. Un `roundedRect` se remarque immédiatement à côté des
/// autres icônes du Dock.
func squircle(_ cote: CGFloat) -> NSBezierPath {
    let chemin = NSBezierPath()
    let r = cote / 2, n: CGFloat = 5, pas = 360
    for i in 0...pas {
        let t = CGFloat(i) / CGFloat(pas) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r + r * CGFloat(sign(c)) * pow(abs(c), 2 / n)
        let y = r + r * CGFloat(sign(s)) * pow(abs(s), 2 / n)
        if i == 0 { chemin.move(to: CGPoint(x: x, y: y)) } else { chemin.line(to: CGPoint(x: x, y: y)) }
    }
    chemin.close()
    return chemin
}
func sign(_ v: CGFloat) -> CGFloat { v < 0 ? -1 : 1 }

func fond(_ cote: CGFloat) {
    let degrade = NSGradient(colors: [bleuFonce, bleuMoyen, bleuClair],
                             atLocations: [0, 0.46, 1],
                             colorSpace: .sRGB)!
    squircle(cote).addClip()
    degrade.draw(in: NSRect(x: 0, y: 0, width: cote, height: cote), angle: 315)
}

/// Une ligne de texte stylisée, comme on en dessine dans une icône de document.
func ligne(x: CGFloat, y: CGFloat, largeur: CGFloat, epaisseur: CGFloat,
           couleur: NSColor = blanc, alpha: CGFloat = 1) {
    couleur.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: largeur, height: epaisseur),
                 xRadius: epaisseur / 2, yRadius: epaisseur / 2).fill()
}

/// Bulle de dialogue : un rectangle très arrondi avec sa pointe.
func bulle(_ cadre: NSRect, pointeAGauche: Bool, rayon: CGFloat) -> NSBezierPath {
    let chemin = NSBezierPath(roundedRect: cadre, xRadius: rayon, yRadius: rayon)
    let pointe = NSBezierPath()
    let base = cadre.minY
    let x = pointeAGauche ? cadre.minX + rayon * 1.2 : cadre.maxX - rayon * 1.2
    let sens: CGFloat = pointeAGauche ? 1 : -1
    pointe.move(to: CGPoint(x: x, y: base + 2))
    pointe.line(to: CGPoint(x: x + sens * rayon * 0.9, y: base + 2))
    pointe.line(to: CGPoint(x: x + sens * rayon * 0.1, y: base - rayon * 0.85))
    pointe.close()
    chemin.append(pointe)
    return chemin
}

// MARK: - Les cinq pistes

typealias Piste = (nom: String, sousTitre: String, dessin: (CGFloat) -> Void)

/// 1. La question — le principe fondateur : demander avant d'écrire.
func pisteLaQuestion(_ c: CGFloat) {
    fond(c)
    let u = c / 100
    let cadre = NSRect(x: 18*u, y: 26*u, width: 64*u, height: 52*u)
    blanc.setFill()
    bulle(cadre, pointeAGauche: true, rayon: 14*u).fill()

    // Deux lignes de texte, puis un point d'interrogation qui prend la place
    // de la troisième : le document s'arrête pour poser sa question.
    ligne(x: 29*u, y: 62*u, largeur: 42*u, epaisseur: 5*u, couleur: bleuMoyen, alpha: 0.30)
    ligne(x: 29*u, y: 52*u, largeur: 34*u, epaisseur: 5*u, couleur: bleuMoyen, alpha: 0.30)

    let police = NSFont.systemFont(ofSize: 30*u, weight: .heavy)
    let texte = NSAttributedString(string: "?", attributes: [
        .font: police, .foregroundColor: bleuClair])
    texte.draw(at: CGPoint(x: 43*u, y: 29*u))
}

/// 2. L'onde qui devient texte — la transformation, cœur du produit.
func pisteLOnde(_ c: CGFloat) {
    fond(c)
    let u = c / 100
    // À gauche, l'onde. Les hauteurs décroissent puis se rangent : le son
    // s'ordonne à mesure qu'on va vers la droite.
    let hauteurs: [CGFloat] = [22, 38, 28, 46, 30, 18]
    for (i, h) in hauteurs.enumerated() {
        let x = 20*u + CGFloat(i) * 7*u
        ligne(x: x, y: (100 - h) / 2 * u, largeur: 4*u, epaisseur: h*u, alpha: 0.95)
    }
    // À droite, les lignes de texte qui en sortent.
    for (i, largeur) in [(0, 26), (1, 26), (2, 18)].map({ ($0.0, CGFloat($0.1)) }) {
        ligne(x: 66*u, y: (56 - CGFloat(i) * 11)*u, largeur: largeur*u, epaisseur: 5*u,
              alpha: 0.95)
    }
}

/// 3. Les guillemets — la citation, le compte rendu, la langue française.
func pisteLesGuillemets(_ c: CGFloat) {
    fond(c)
    let u = c / 100
    let police = NSFont.systemFont(ofSize: 44*u, weight: .bold)
    let attributs: [NSAttributedString.Key: Any] = [.font: police, .foregroundColor: blanc]
    NSAttributedString(string: "\u{AB}", attributes: attributs).draw(at: CGPoint(x: 12*u, y: 33*u))
    NSAttributedString(string: "\u{BB}", attributes: attributs).draw(at: CGPoint(x: 60*u, y: 33*u))
    // Entre les guillemets, trois lignes : ce qui a été dit devient un texte.
    // Elles s'estompent vers le bas — le propos se range en document.
    ligne(x: 38*u, y: 61*u, largeur: 24*u, epaisseur: 4.5*u, alpha: 0.95)
    ligne(x: 38*u, y: 52*u, largeur: 24*u, epaisseur: 4.5*u, alpha: 0.7)
    ligne(x: 38*u, y: 43*u, largeur: 15*u, epaisseur: 4.5*u, alpha: 0.45)
}

/// 4. Deux voix, un document — la double piste, l'attribution exacte.
func pisteDeuxVoix(_ c: CGFloat) {
    fond(c)
    let u = c / 100
    // Deux bulles décalées, l'une pleine, l'autre en retrait : « moi » et
    // « les autres », que la double piste sépare par construction.
    blanc.withAlphaComponent(0.45).setFill()
    bulle(NSRect(x: 14*u, y: 46*u, width: 46*u, height: 34*u),
          pointeAGauche: true, rayon: 11*u).fill()
    blanc.setFill()
    bulle(NSRect(x: 42*u, y: 20*u, width: 46*u, height: 34*u),
          pointeAGauche: false, rayon: 11*u).fill()
    ligne(x: 52*u, y: 38*u, largeur: 26*u, epaisseur: 4.5*u, couleur: bleuMoyen, alpha: 0.35)
    ligne(x: 52*u, y: 29*u, largeur: 18*u, epaisseur: 4.5*u, couleur: bleuMoyen, alpha: 0.35)
}

/// 5. Le compte rendu — la page relue et validée, sobre et institutionnelle.
func pisteLaPage(_ c: CGFloat) {
    fond(c)
    let u = c / 100
    // La page, avec un coin corné.
    let page = NSBezierPath()
    let g: CGFloat = 24, d: CGFloat = 76, b: CGFloat = 16, h: CGFloat = 84, corne: CGFloat = 16
    page.move(to: CGPoint(x: g*u, y: b*u))
    page.line(to: CGPoint(x: g*u, y: h*u))
    page.line(to: CGPoint(x: (d - corne)*u, y: h*u))
    page.line(to: CGPoint(x: d*u, y: (h - corne)*u))
    page.line(to: CGPoint(x: d*u, y: b*u))
    page.close()
    blanc.setFill()
    page.fill()

    for (i, largeur) in [30, 30, 22].enumerated() {
        ligne(x: 32*u, y: (66 - CGFloat(i) * 11)*u, largeur: CGFloat(largeur)*u,
              epaisseur: 4.5*u, couleur: bleuMoyen, alpha: 0.28)
    }
    // La coche ambre : le document est relu et validé, pas seulement produit.
    let coche = NSBezierPath()
    coche.move(to: CGPoint(x: 33*u, y: 27*u))
    coche.line(to: CGPoint(x: 40*u, y: 21*u))
    coche.line(to: CGPoint(x: 55*u, y: 36*u))
    coche.lineWidth = 6*u
    coche.lineCapStyle = .round
    coche.lineJoinStyle = .round
    ambre.setStroke()
    coche.stroke()
}

let pistes: [Piste] = [
    ("1 · La question", "le principe fondateur : demander avant d'écrire", pisteLaQuestion),
    ("2 · L'onde et le texte", "la transformation du son en document", pisteLOnde),
    ("3 · Les guillemets", "la citation, le compte rendu, le français", pisteLesGuillemets),
    ("4 · Deux voix", "la double piste et l'attribution exacte", pisteDeuxVoix),
    ("5 · Le compte rendu", "la page relue et validée", pisteLaPage),
]

// MARK: - Planche

func rendre(_ dessin: (CGFloat) -> Void, cote: CGFloat, echelle: CGFloat = 2) -> NSImage {
    let image = NSImage(size: NSSize(width: cote, height: cote))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    dessin(cote)
    image.unlockFocus()
    return image
}

let sortie = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/greffier-icones.png"

let grand: CGFloat = 170
let tailles: [CGFloat] = [64, 32, 16]  // ce que le Finder et le Dock montrent vraiment
let margeH: CGFloat = 30
let colonne: CGFloat = 300
let largeur = margeH * 2 + colonne * CGFloat(pistes.count)
let demi: CGFloat = 350
let hauteur = demi * 2

let planche = NSImage(size: NSSize(width: largeur, height: hauteur))
planche.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

NSColor(white: 0.96, alpha: 1).setFill()
NSRect(x: 0, y: demi, width: largeur, height: demi).fill()
NSColor(white: 0.11, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: largeur, height: demi).fill()

for (index, piste) in pistes.enumerated() {
    let x = margeH + CGFloat(index) * colonne

    for (fondClair, base) in [(true, demi), (false, CGFloat(0))] {
        let encre = fondClair ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.94, alpha: 1)
        let doux = fondClair ? NSColor(white: 0.42, alpha: 1) : NSColor(white: 0.62, alpha: 1)

        // Titre et sous-titre, en haut du bloc.
        NSAttributedString(string: piste.nom, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: encre,
        ]).draw(at: CGPoint(x: x, y: base + demi - 32))

        NSAttributedString(string: piste.sousTitre, attributes: [
            .font: NSFont.systemFont(ofSize: 10.5),
            .foregroundColor: doux,
        ]).draw(in: NSRect(x: x, y: base + demi - 64, width: colonne - 30, height: 28))

        // L'icône en grand.
        rendre(piste.dessin, cote: grand)
            .draw(in: NSRect(x: x, y: base + 108, width: grand, height: grand))

        // Puis les tailles réelles, côte à côte : c'est là que les icônes se
        // cassent, et c'est ce qu'on voit vraiment dans le Dock et le Finder.
        var xp = x
        for taille in tailles {
            rendre(piste.dessin, cote: taille)
                .draw(in: NSRect(x: xp, y: 42, width: taille, height: taille).offsetBy(dx: 0, dy: base))
            NSAttributedString(string: "\(Int(taille))", attributes: [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: doux,
            ]).draw(at: CGPoint(x: xp, y: base + 26))
            xp += taille + 22
        }
    }
}

planche.unlockFocus()

let rep = NSBitmapImageRep(data: planche.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: sortie))
print("Planche écrite : \(sortie)")
