import Foundation

/// Version CalVer de l'application, au format `AAAA.MM.JJ.XX`.
///
/// La convention UP place ce numéro dans `src/lib/version.ts`, ce qui n'a pas
/// de sens pour du Swift : il vit donc ici, dans le noyau, et `build.sh` le
/// recopie dans l'`Info.plist` du bundle au moment de la compilation. Une
/// seule source, deux emplacements dérivés.
public let versionGreffier = "2026.08.20.17"
