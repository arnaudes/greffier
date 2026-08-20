#!/bin/bash
#
# Greffier — contrôle de confidentialité avant publication
#
# Ce dépôt est public. Une donnée personnelle qui y entre est publiée, et un
# « git push --force » ne l'efface pas : GitHub conserve les objets d'un commit
# écrasé, atteignables par leur empreinte. Le seul moment où l'on peut encore
# agir est donc AVANT l'envoi.
#
# Ce contrôle est passé le 20/08/2026, après qu'un nom de société écrit en dur
# et le nom d'un client réel se sont retrouvés en ligne. Il ne remplace pas la
# relecture : il rattrape ce qu'une relecture fatiguée laisse passer.
#
#   ./outils/verifier-confidentialite.sh
#
# La liste des noms à ne jamais publier vit HORS du dépôt, dans
# ~/Documents/Greffier/motifs-prives.txt — une ligne par motif. Elle ne peut
# pas vivre ici : elle serait elle-même la fuite qu'elle prévient.

set -uo pipefail
cd "$(dirname "$0")/.."

MOTIFS="$HOME/Documents/Greffier/motifs-prives.txt"
FAUTES=0

signaler() {
    FAUTES=$((FAUTES + 1))
    echo "✗ $1"
}

echo "Contrôle de confidentialité — $(git ls-files | wc -l | tr -d ' ') fichiers suivis"
echo

# 1. Les noms propres à ne jamais publier.
if [ -f "$MOTIFS" ]; then
    while IFS= read -r motif; do
        [ -z "$motif" ] && continue
        case "$motif" in \#*) continue ;; esac
        if trouve=$(git grep -n -i -e "$motif" -- . 2>/dev/null); then
            signaler "motif privé trouvé :"
            echo "$trouve" | head -5 | sed 's/^/    /'
        fi
    done < "$MOTIFS"
    echo "· liste privée : $(grep -cve '^$' -e '^#' "$MOTIFS") motifs vérifiés"
else
    signaler "liste des motifs privés introuvable : $MOTIFS"
    echo "    Sans elle, ce contrôle ne vérifie que les règles générales."
fi

# 2. Une adresse email est toujours une donnée personnelle.
if trouve=$(git grep -nE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" -- . 2>/dev/null); then
    signaler "adresse email dans le dépôt :"
    echo "$trouve" | head -5 | sed 's/^/    /'
fi

# 3. Un chemin absolu porte le nom du compte de celui qui l'a écrit.
if trouve=$(git grep -nE "/(Users|home)/[a-z]" -- . 2>/dev/null); then
    signaler "chemin absolu personnel :"
    echo "$trouve" | head -5 | sed 's/^/    /'
fi

# 4. L'identité des commits : elle part sur GitHub avec le code, et c'est
#    par là que l'adresse professionnelle a fuité la première fois.
AUTEURS=$(git log --format='%ae%n%ce' | sort -u | grep -v "users.noreply.github.com" || true)
if [ -n "$AUTEURS" ]; then
    signaler "adresse non anonyme dans l'historique :"
    echo "$AUTEURS" | sed 's/^/    /'
    echo "    → git config user.email '<id>+<login>@users.noreply.github.com'"
fi

echo
if [ "$FAUTES" -eq 0 ]; then
    echo "✓ Rien à signaler. La publication peut avoir lieu."
    exit 0
fi
echo "✗ $FAUTES point(s) à régler AVANT de pousser."
exit 1
