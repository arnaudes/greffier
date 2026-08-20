# Greffier

Une application Mac qui transforme une réunion en compte rendu.

Elle capte l'audio, le transcrit **sur votre ordinateur**, vous pose les
questions nécessaires pour lever les ambiguïtés, puis rédige. Elle n'invente
rien : ce qu'elle ne sait pas, elle le demande.

## Ce qu'elle produit

Pour chaque réunion, dans un dossier qui lui est propre :

- un **compte rendu interne** en Markdown ;
- le **même document en PDF**, et un **document Word** — un vrai, avec ses
  styles, ses tableaux et sa pagination — si vous voulez l'annoter ou le
  faire relire ;
- le **transcript** intégral, pour pouvoir vérifier d'où vient une phrase ;
- un **email au client**, dérivé du compte rendu — dont vous choisissez le
  contenu point par point. Il est écrit sur le disque, **jamais envoyé**.

## Ce qui la distingue

**Elle ne devine pas qui a parlé.** En visioconférence, elle enregistre deux
pistes séparées : votre micro d'un côté, le son des autres participants de
l'autre. L'attribution des propos n'est pas une supposition, elle est exacte par
construction.

**Elle pose des questions.** Un moteur de transcription se trompe avec aplomb :
il écrit des mots plausibles à la place des noms propres et du vocabulaire
métier, sans jamais signaler qu'il hésite. Plutôt que de lisser, Greffier
demande — et retient vos réponses dans un **lexique**, si bien que la même
question ne revient jamais deux fois.

**Le son ne quitte pas votre Mac.** La transcription se fait sur l'appareil.

## D'où peut venir une réunion

| | |
|---|---|
| **Le micro** | une réunion dans la pièce |
| **Une visioconférence** | deux pistes séparées, vous et les autres |
| **Un transcript collé** | enregistré ailleurs, sur un téléphone par exemple |
| **Vos notes** | prises à la main, même incomplètes — rien n'y sera comblé |

Le raccourci **⌃⌥⌘R** démarre ou arrête un enregistrement depuis n'importe où :
une réunion commence quand quelqu'un dit « on y va », pas au moment prévu.

## Ce qu'il vous faut

| | |
|---|---|
| **macOS 14** ou plus récent | |
| **[Claude Code](https://claude.com/claude-code)** installé et connecté | **indispensable** : la rédaction passe par votre abonnement |
| La **dictée** activée | Réglages Système → Clavier → Dictée, en français. La transcription en dépend, même hors ligne |
| **Google Chrome** | seulement pour produire les PDF |

Sans abonnement Claude Code, l'application enregistre et transcrit, mais ne
rédige pas.

L'onglet **État** des réglages vérifie ces conditions et les autres —
autorisations du micro, de la reconnaissance vocale, de l'écran et du
calendrier — et dit pour chacune ce qu'on perd sans elle.

## Installer

```bash
git clone https://github.com/arnaudes/greffier.git
cd greffier/app
./build.sh
```

L'application est déposée dans `~/Applications/Greffier.app`.

À la première ouverture, macOS affichera « développeur non identifié » :
**clic droit sur l'application → Ouvrir**, puis confirmez. Une seule fois.

Greffier demandera ensuite l'accès au micro, à la reconnaissance vocale, au
calendrier et à l'enregistrement de l'écran — ce dernier sert à capter le son
des autres participants en visioconférence, c'est le seul moyen que macOS offre
de le faire sans installer de pilote audio.

## Se présenter

Ouvrez les réglages, onglet **Vous**. Le nom suffit à commencer, mais deux
champs décident de la qualité des comptes rendus :

- **ce que fait votre société** — sans quoi Greffier ignore ce qu'est un
  livrable, un jalon ou une réserve dans votre métier ;
- **ce qui ne sort jamais au client** — écarté automatiquement de l'email.

Deux champs s'y ajoutent : une **charte rédactionnelle** — votre façon
d'écrire — et **ce qu'il faut savoir de votre métier**, qui porte sur le fond.
Ni l'une ni l'autre ne peut défaire les règles ci-dessous.

Chaque dossier peut recevoir ses **propres consignes**, depuis le panneau de
droite : un client n'attend pas ce qu'attend l'autre.

Et quand un compte rendu ne convient pas, **« Ajuster la rédaction »** permet de
dire ce qui n'allait pas ; Greffier en tire une consigne et vous demande si elle
vaut pour ce dossier ou pour tous. On ne configure pas, on corrige, et l'outil
retient — c'est le procédé du lexique appliqué au style.

Un bouton **« Voir ce que Claude reçoit »** affiche les consignes exactes qui
seront envoyées. L'application ne cache pas son mécanisme.

## La forme de vos documents

Le PDF et le document Word partagent une **charte** : des couleurs, une police,
une taille. Elle est fournie sobre et se règle dans les réglages, onglet
**Charte**, avec un aperçu de ce que cela donnera. Rien n'y est écrit en dur :
le nom qui apparaît au-dessus du titre est celui de la société que vous avez
renseignée, et rien d'autre.

Elle est enregistrée dans `charte.json`, à la racine de votre dossier de
travail — elle suit donc vos documents quand vous les sauvegardez, et se
corrige aussi à la main.

## Retrouver ce qui a été écrit

Un compte rendu se relit des mois plus tard, souvent sans qu'on se souvienne du
client — mais en se souvenant d'un montant ou d'une phrase dite en séance. La
recherche porte sur le nom du client, l'objet de la réunion et le **corps** des
comptes rendus, et montre le passage qui a fait ressortir chacun.

Un compte rendu peut être **repris** pour être corrigé et voir son PDF refait.

## Où vivent vos documents

Dans `~/Documents/Greffier`, hors de ce dépôt, et vous pouvez en changer.
Un dossier par client, un sous-dossier par réunion :

```
comptes-rendus/Menuiseries Vidal/2026-08-19 — Devis et subvention/
    Compte rendu.md
    Compte rendu.pdf
    Transcript.md
    Email client.md
    Fabrication/          l'audio compressé, la page HTML du PDF
```

L'audio est compressé une fois le compte rendu produit : une réunion de trente
minutes occupe une trentaine de mégaoctets au lieu de neuf cents. Les
enregistrements qui n'ont produit aucun compte rendu se retrouvent dans une
fenêtre dédiée, où ils peuvent être écoutés, transcrits ou supprimés.

## Ce qu'elle ne fait pas

- **Elle n'envoie aucun email.** Elle prépare, vous envoyez.
- **Elle ne tranche jamais à votre place.** Une question laissée sans réponse
  devient un point ouvert dans le compte rendu, jamais une supposition.
- **Elle n'ajoute ni analyse ni recommandation.** Elle restitue ce qui a été dit.
- **Elle ne se met pas à jour toute seule.** Elle vous prévient quand une
  version plus récente est publiée, et vous installez.

Ces règles ne se règlent pas : elles sont ce que l'application garantit.

## Une chose à savoir

Le son et la transcription restent sur votre Mac. Le **transcript**, lui, est
envoyé à Claude pour la rédaction — c'est ce qui permet le compte rendu. Si vos
réunions portent sur des sujets qui ne doivent pas quitter votre machine,
tenez-en compte.

## Construire et vérifier

```bash
cd app
swift build && swift test     # 219 cas
swift run greffier-outil      # l'aide de l'outil en ligne de commande
```

Ce dépôt est public et l'application travaille sur des réunions réelles. Un
contrôle refuse la publication si une donnée personnelle y est entrée — adresse
email, chemin de compte, identité non anonyme dans l'historique, ou l'un des
noms d'une liste que chacun tient **hors du dépôt** :

```bash
./outils/verifier-confidentialite.sh
```

Pas de projet Xcode : tout se compile et se teste en ligne de commande, et rien
de la configuration ne vit dans un fichier illisible en révision.

## Licence

Application personnelle, partagée en l'état, sans garantie ni engagement de
maintenance.
