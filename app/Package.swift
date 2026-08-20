// swift-tools-version: 6.0
import PackageDescription

// Greffier — application Mac locale de comptes rendus de réunion.
//
// Construction par Swift Package Manager plutôt que par un projet Xcode :
// tout se compile et se teste en ligne de commande, et rien de la
// configuration ne vit dans un fichier de projet illisible en révision.
// Xcode reste nécessaire pour ses SDK.

let package = Package(
    name: "Greffier",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NoyauCR", targets: ["NoyauCR"]),
        .executable(name: "greffier-outil", targets: ["OutilCR"]),
        .executable(name: "Greffier", targets: ["Greffier"]),
    ],
    targets: [
        // L'application elle-même. `build.sh` en fait un bundle .app ; lancée
        // directement, elle s'affiche tout de même, ce qui suffit à travailler
        // l'interface sans passer par Xcode.
        .executableTarget(name: "Greffier", dependencies: ["NoyauCR"]),

        // Le noyau : modèle, lexique, dialogue avec Claude, production des
        // documents. Aucune dépendance à l'interface — c'est ce qui le rend
        // vérifiable sans ouvrir de fenêtre.
        .target(name: "NoyauCR"),

        // Outil en ligne de commande, pour éprouver le noyau pendant la
        // construction. Ne fait pas partie de l'application livrée.
        .executableTarget(name: "OutilCR", dependencies: ["NoyauCR"]),

        .testTarget(name: "NoyauCRTests", dependencies: ["NoyauCR"]),
    ]
)
