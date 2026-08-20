#!/bin/bash
# ---------------------------------------------------------------------------
# Greffier — fabrication du bundle applicatif
#
# Compile par Swift Package Manager, puis assemble Greffier.app à la main :
# c'est ce qui permet de tout construire et de tout vérifier en ligne de
# commande, sans dépendre d'un projet Xcode ni de l'interface graphique.
#
#   ./build.sh              compile et assemble
#   ./build.sh --lancer     compile, assemble et ouvre l'application
# ---------------------------------------------------------------------------
set -euo pipefail

ICI="$(cd "$(dirname "$0")" && pwd)"
cd "$ICI"

# Le CalVer a une seule source : Version.swift. Il est recopié dans
# l'Info.plist à la compilation, jamais tenu à deux endroits.
VERSION=$(sed -n 's/^public let versionGreffier = "\(.*\)"$/\1/p' Sources/NoyauCR/Version.swift)
if [ -z "$VERSION" ]; then
  echo "Version introuvable dans Sources/NoyauCR/Version.swift" >&2
  exit 1
fi

echo "Compilation d'Greffier ${VERSION}…"
swift build -c release --product Greffier

# L'application est installée dans ~/Applications, et non dans le dépôt. Ce n'est pas de la cosmétique : macOS traite différemment un
# bundle qui vit dans un répertoire de travail, et les autorisations de micro
# ou de calendrier peuvent lui être refusées sans le moindre message.
INSTALLATION="$HOME/Applications"
mkdir -p "$INSTALLATION"
APP="$INSTALLATION/Greffier.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Greffier "$APP/Contents/MacOS/Greffier"

# L'icône est conservée dans le dépôt plutôt que régénérée à chaque
# compilation : elle ne change qu'à la demande, et la fabriquer coûterait une
# seconde à chaque build pour un résultat identique.
ICONE="$ICI/../ressources/Greffier.icns"
if [ -f "$ICONE" ]; then
  cp "$ICONE" "$APP/Contents/Resources/Greffier.icns"
else
  echo "Icône absente : $ICONE — l'application prendra celle par défaut." >&2
fi

# Les descriptions d'usage ne sont pas décoratives : sans elles, macOS refuse
# l'accès et l'application échoue sans expliquer pourquoi. Elles s'affichent
# telles quelles dans la fenêtre d'autorisation, en français.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Greffier</string>
    <key>CFBundleDisplayName</key><string>Greffier</string>
    <key>CFBundleIdentifier</key><string>io.github.arnaudes.greffier</string>
    <key>CFBundleExecutable</key><string>Greffier</string>
    <key>CFBundleIconFile</key><string>Greffier</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Greffier</string>

    <key>NSMicrophoneUsageDescription</key>
    <string>Greffier enregistre la réunion pour en produire le compte rendu. Le son reste sur cet ordinateur.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Greffier transcrit l'enregistrement sur cet ordinateur, sans envoyer le son à un serveur.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Greffier lit votre calendrier professionnel pour reconnaître la réunion en cours et ses participants.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Greffier lit votre calendrier professionnel pour reconnaître la réunion en cours et ses participants.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>En visioconférence, Greffier capte le son des autres participants sur une piste distincte de la vôtre, ce qui permet de savoir qui a dit quoi. Aucune image n'est enregistrée.</string>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------------------
# Signature
#
# macOS retient les autorisations (micro, calendrier, écran) par IDENTITÉ DE
# SIGNATURE. Une signature ad hoc n'en a pas de stable : elle vaut l'empreinte
# du binaire, qui change à chaque compilation. Résultat, macOS voit une
# application différente à chaque build et redemande tout.
#
# Un certificat « Apple Development » — gratuit, obtenu en ajoutant son
# identifiant Apple dans Xcode, Réglages, Comptes — donne une identité stable :
# les autorisations sont alors accordées une fois pour toutes.
# ---------------------------------------------------------------------------
# Le « || true » n'est pas une négligence : sans identité, grep rend 1, et
# `set -e` couperait le script en silence — exactement le genre de panne muette
# qu'on cherche à éviter partout ailleurs.
IDENTITE=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)

if [ -n "$IDENTITE" ]; then
  # Les entitlements ne sont pas facultatifs sous Hardened Runtime : ils
  # déclarent le micro et le calendrier. Sans eux, macOS refuse l'accès sans
  # jamais présenter de fenêtre d'autorisation.
  codesign --force --options runtime \
    --entitlements "$ICI/Greffier.entitlements" \
    --sign "$IDENTITE" "$APP" 2>/dev/null \
    && echo "Signée avec : ${IDENTITE}"
else
  codesign --force --sign - "$APP" 2>/dev/null
  echo "Signature ad hoc : macOS redemandera les autorisations à chaque" >&2
  echo "recompilation, faute d'identité stable. Pour n'y répondre qu'une fois," >&2
  echo "ouvrir Xcode, Réglages, Comptes, et ajouter votre identifiant Apple :" >&2
  echo "un certificat de développement gratuit sera créé." >&2
fi

echo "Greffier.app assemblée ($VERSION)."
if [ "${1:-}" = "--lancer" ]; then
  open "$APP"
fi
