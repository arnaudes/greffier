import AppKit
import Foundation

// Fabrique l'icône de Greffier : « l'onde et le texte », piste retenue
// le 17/08/2026. Le son entre à gauche, le document sort à droite.
//
//   swiftc -O outils/generer-icone.swift -o /tmp/generer-icone
//   /tmp/generer-icone ressources/Greffier.icns [planche.png]
//
// **Chaque taille est dessinée pour elle-même, jamais réduite depuis 1024.**
// Et sous 40 px le dessin est simplifié : à cette échelle, six barres d'onde et
// trois lignes de texte se referment en une trame grise illisible. C'est
// exactement ce que la planche de propositions avait montré.

let bleuFonce = NSColor(srgbRed: 0x1F/255, green: 0x3C/255, blue: 0x8E/255, alpha: 1)
let bleuMoyen = NSColor(srgbRed: 0x29/255, green: 0x53/255, blue: 0xCE/255, alpha: 1)
let bleuClair = NSColor(srgbRed: 0x31/255, green: 0x68/255, blue: 0xEC/255, alpha: 1)
let blanc = NSColor.white

func sign(_ v: CGFloat) -> CGFloat { v < 0 ? -1 : 1 }

/// Superellipse d'exposant 5 : l'arrondi d'Apple. Un `roundedRect` se remarque
/// aussitôt dans le Dock, son arrondi étant un simple arc de cercle.
func squircle(_ cote: CGFloat) -> NSBezierPath {
    let chemin = NSBezierPath()
    let r = cote / 2, n: CGFloat = 5, pas = 720
    for i in 0...pas {
        let t = CGFloat(i) / CGFloat(pas) * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = CGPoint(x: r + r * sign(c) * pow(abs(c), 2/n),
                            y: r + r * sign(s) * pow(abs(s), 2/n))
        if i == 0 { chemin.move(to: point) } else { chemin.line(to: point) }
    }
    chemin.close()
    return chemin
}

func fond(_ cote: CGFloat) {
    NSGradient(colors: [bleuFonce, bleuMoyen, bleuClair],
               atLocations: [0, 0.46, 1], colorSpace: .sRGB)!
        .draw(in: NSRect(x: 0, y: 0, width: cote, height: cote), angle: 315)
}

func barre(x: CGFloat, centre: CGFloat, hauteur: CGFloat, epaisseur: CGFloat,
           alpha: CGFloat = 1) {
    blanc.withAlphaComponent(alpha).setFill()
    let r = NSRect(x: x, y: centre - hauteur/2, width: epaisseur, height: hauteur)
    NSBezierPath(roundedRect: r, xRadius: epaisseur/2, yRadius: epaisseur/2).fill()
}

func ligne(x: CGFloat, y: CGFloat, largeur: CGFloat, epaisseur: CGFloat, alpha: CGFloat = 1) {
    blanc.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: largeur, height: epaisseur),
                 xRadius: epaisseur/2, yRadius: epaisseur/2).fill()
}

/// Le dessin, en unités de centièmes du côté.
func dessiner(_ cote: CGFloat, simplifie: Bool) {
    let u = cote / 100
    squircle(cote).addClip()
    fond(cote)

    if simplifie {
        // Sous 40 px : trois barres, deux lignes, tout plus épais et plus grand.
        // Mieux vaut un motif lisible qu'un dessin fidèle qu'on ne distingue pas.
        for (i, h) in [(0, CGFloat(30)), (1, 52), (2, 34)].map({ ($0.0, $0.1) }) {
            barre(x: (20 + CGFloat(i) * 12)*u, centre: 50*u, hauteur: h*u, epaisseur: 7*u)
        }
        ligne(x: 60*u, y: 55*u, largeur: 24*u, epaisseur: 8*u)
        ligne(x: 60*u, y: 39*u, largeur: 17*u, epaisseur: 8*u)
    } else {
        // Le dessin complet : l'onde se calme de gauche à droite, puis se range
        // en lignes de texte. Le son entre, le document sort.
        let hauteurs: [CGFloat] = [24, 42, 30, 50, 32, 20]
        for (i, h) in hauteurs.enumerated() {
            barre(x: (17 + CGFloat(i) * 7.5)*u, centre: 50*u, hauteur: h*u,
                  epaisseur: 4.2*u, alpha: 0.92 + CGFloat(i % 2) * 0.08)
        }
        for (i, largeur) in [CGFloat(27), 27, 18].enumerated() {
            ligne(x: 65*u, y: (60 - CGFloat(i) * 11)*u, largeur: largeur*u, epaisseur: 5*u,
                  alpha: 1 - CGFloat(i) * 0.12)
        }
    }
}

func rendre(_ cote: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: cote, height: cote))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    dessiner(cote, simplifie: cote < 40)
    image.unlockFocus()
    return image
}

func png(_ image: NSImage) -> Data {
    NSBitmapImageRep(data: image.tiffRepresentation!)!
        .representation(using: .png, properties: [:])!
}

// MARK: - Le .icns

let args = CommandLine.arguments
let destination = args.count > 1 ? args[1] : "ressources/Greffier.icns"
let gestionnaire = FileManager.default

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Greffier.iconset")
try? gestionnaire.removeItem(at: iconset)
try! gestionnaire.createDirectory(at: iconset, withIntermediateDirectories: true)

// Les noms qu'`iconutil` attend. La taille entre parenthèses est celle qui est
// réellement dessinée : « 16x16@2x » fait 32 pixels, et doit donc être dessinée
// comme une 32, non comme une 16 agrandie.
let variantes: [(nom: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for variante in variantes {
    try! png(rendre(variante.pixels))
        .write(to: iconset.appendingPathComponent(variante.nom + ".png"))
}

let sortie = URL(fileURLWithPath: destination)
try? gestionnaire.createDirectory(at: sortie.deletingLastPathComponent(),
                                  withIntermediateDirectories: true)
let outil = Process()
outil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
outil.arguments = ["-c", "icns", iconset.path, "-o", sortie.path]
try! outil.run()
outil.waitUntilExit()
guard outil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil a échoué\n".utf8))
    exit(1)
}
print("Icône écrite : \(sortie.path)")

// MARK: - Planche de contrôle

guard args.count > 2 else { exit(0) }

let tailles: [CGFloat] = [128, 64, 32, 16]
let demi: CGFloat = 230
let largeurP: CGFloat = 700
let planche = NSImage(size: NSSize(width: largeurP, height: demi * 2))
planche.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

NSColor(white: 0.96, alpha: 1).setFill()
NSRect(x: 0, y: demi, width: largeurP, height: demi).fill()
NSColor(white: 0.11, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: largeurP, height: demi).fill()

for (clair, base) in [(true, demi), (false, CGFloat(0))] {
    let encre = clair ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.94, alpha: 1)
    let doux = clair ? NSColor(white: 0.42, alpha: 1) : NSColor(white: 0.62, alpha: 1)

    NSAttributedString(string: "Greffier — l'onde et le texte", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: encre,
    ]).draw(at: CGPoint(x: 24, y: base + demi - 28))

    // Deux rangées : le dessin complet partout, puis le dessin réellement
    // employé — simplifié sous 40 px. C'est la comparaison qui tranche.
    for (rangee, force) in [(0, true), (1, false)] {
        let y = base + 118 - CGFloat(rangee) * 96
        var x: CGFloat = 150
        for taille in tailles {
            let image = NSImage(size: NSSize(width: taille, height: taille))
            image.lockFocus()
            dessiner(taille, simplifie: force ? false : taille < 40)
            image.unlockFocus()
            image.draw(in: NSRect(x: x, y: y, width: taille, height: taille))
            if rangee == 1 {
                NSAttributedString(string: "\(Int(taille)) px", attributes: [
                    .font: NSFont.systemFont(ofSize: 9), .foregroundColor: doux,
                ]).draw(at: CGPoint(x: x, y: y - 16))
            }
            x += 128 + 12
        }
        NSAttributedString(string: rangee == 0 ? "dessin complet" : "dessin employé",
                           attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: doux,
        ]).draw(at: CGPoint(x: 24, y: y + 40))
    }
}
planche.unlockFocus()
try! png(planche).write(to: URL(fileURLWithPath: args[2]))
print("Planche de contrôle : \(args[2])")
