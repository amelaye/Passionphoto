#!/usr/bin/env bash
# Scénarios passionphoto dans un VRAI serveur Luanti headless (aucun client, aucune fenêtre).
#
#   tools/headless/run.sh                     tous les scénarios (tests/passionphoto_test/scenarios/)
#   tools/headless/run.sh -f moteur           seulement ceux dont le nom contient « moteur »
#   tools/headless/run.sh -s /tmp/essai.lua   ajoute un scénario ad hoc (non commité) ; avec -f adhoc : lui seul
#   tools/headless/run.sh -g v7               vrai paysage (mapgen v7, graine fixe) au lieu de singlenode
#   tools/headless/run.sh -M                  minimal : sans les mods facultatifs de .deps/mods/
#   tools/headless/run.sh -o clé=valeur       réglage en plus dans la config du serveur (répétable)
#   tools/headless/run.sh -t 300 -k -q        délai max (s, défaut 120), garder la carte, sortie réduite
#
# Codes de sortie : 0 tout passe | 1 un scénario échoue ou une erreur du mod est journalisée
#                   2 le serveur a planté, dépassé le délai, ou n'a produit aucun résultat
# Artefacts : .headless/runs/<id>/ (debug.txt, results.json, photos/*.png) ; .headless/last -> dernier passage.
# Variables : LUANTI_BIN (moteur, voir tools/luanti_bin.sh), PP_SEED (graine, défaut 20261126).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

FILTER="" ; SCRIPTS=() ; TIMEOUT=120 ; KEEP=0 ; EXTRA=() ; QUIET=0 ; MAPGEN="singlenode" ; MINIMAL=0
while getopts "f:s:t:o:g:Mkqh" opt; do
	case "$opt" in
		f) FILTER="$OPTARG" ;;
		s) SCRIPTS+=("$OPTARG") ;;
		t) TIMEOUT="$OPTARG" ;;
		o) EXTRA+=("$OPTARG") ;;
		g) MAPGEN="$OPTARG" ;;
		M) MINIMAL=1 ;;
		k) KEEP=1 ;;
		q) QUIET=1 ;;
		*) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	esac
done

SRV=$("$ROOT/tools/luanti_bin.sh") || exit 2
GAME="$ROOT/.deps/games/minetest"
[ -d "$GAME" ] || { echo "jeu absent : lancer make deps (tools/fetch_deps.sh)" >&2; exit 2; }

# --- monde jetable -------------------------------------------------------------------------------------------
# Le mod est COPIÉ (instantané de l'arbre de travail), jamais lié : un lien vers la racine ferait boucler
# les outils récursifs (luacheck, grep -r) et laisserait le serveur écrire dans le dépôt.
RUNS="$ROOT/.headless/runs"
ID="$(date +%Y%m%d-%H%M%S)-$$"
RUN="$RUNS/$ID"
USERDIR="$RUN/user"
WORLD="$USERDIR/worlds/test"
mkdir -p "$USERDIR/games" "$WORLD/worldmods" || exit 2
ln -s "$GAME" "$USERDIR/games/minetest"
ln -sfn "runs/$ID" "$ROOT/.headless/last"

cat > "$WORLD/world.mt" <<EOF
gameid = minetest
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
EOF

rsync -a --exclude .git --exclude .claude --exclude .deps --exclude .run --exclude .headless --exclude .cache \
	--exclude dist --exclude tests --exclude tools --exclude docs "$ROOT/" "$WORLD/worldmods/passionphoto/" || exit 2
cp -R "$ROOT/tests/passionphoto_test" "$WORLD/worldmods/passionphoto_test" || exit 2
mkdir -p "$WORLD/worldmods/passionphoto_test/scenarios"
for s in ${SCRIPTS[@]+"${SCRIPTS[@]}"}; do
	[ -f "$s" ] || { echo "scénario introuvable : $s" >&2; exit 2; }
	cp "$s" "$WORLD/worldmods/passionphoto_test/scenarios/zz_adhoc_$(basename "$s")"
done
MODS="aucun"
if [ "$MINIMAL" = 0 ]; then
	for m in "$ROOT"/.deps/mods/*; do
		[ -d "$m" ] || continue
		ln -s "$m" "$WORLD/worldmods/$(basename "$m")"
		[ "$MODS" = "aucun" ] && MODS=""
		MODS="$MODS $(basename "$m")"
	done
else
	MODS="aucun (-M)"
fi

PORT=$(( 30000 + RANDOM % 20000 ))
CONF="$RUN/luanti.conf"
{
	echo "mg_name = $MAPGEN"
	echo "fixed_map_seed = ${PP_SEED:-20261126}"
	echo "server_announce = false"
	echo "bind_address = 127.0.0.1"
	echo "port = $PORT"
	echo "enable_damage = false"
	echo "creative_mode = false"
	echo "dedicated_server_step = 0.05"
	echo "max_forceloaded_blocks = 1024"
	echo "secure.enable_security = true"
	echo "debug_log_level = action"
	echo "passionphoto_test.mode = scenarios"
	echo "passionphoto_test.filter = $FILTER"
	for e in ${EXTRA[@]+"${EXTRA[@]}"}; do echo "${e/=/ = }"; done
} > "$CONF"

# --- exécution sous chien de garde --------------------------------------------------------------------------
LOG="$RUN/debug.txt"
echo "== moteur : $($SRV --version 2>/dev/null | head -1) | mapgen $MAPGEN | mods facultatifs :${MODS# }"
# shellcheck disable=SC2086
MINETEST_USER_PATH="$USERDIR" LUANTI_USER_PATH="$USERDIR" \
	perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$TIMEOUT" \
	$SRV --world "$WORLD" --config "$CONF" --logfile "$LOG" > "$RUN/stdout.txt" 2>&1
CODE=$?

[ -f "$WORLD/passionphoto_test_results.json" ] && cp "$WORLD/passionphoto_test_results.json" "$RUN/results.json"
if [ -d "$WORLD/passionphoto_test_out" ]; then
	mkdir -p "$RUN/photos"
	cp "$WORLD"/passionphoto_test_out/* "$RUN/photos/" 2>/dev/null
fi

# --- compte rendu ---------------------------------------------------------------------------------------------
grep -a "\[passionphoto_test\]" "$LOG" 2>/dev/null | sed 's/^.*\[passionphoto_test\] //' | grep -v "^FICHIER " | {
	if [ "$QUIET" = 1 ]; then grep -E "^(ÉCHEC|CORRIGÉ|BILAN)" ; else cat; fi
}

STATUS=2
if [ -f "$RUN/results.json" ] && grep -q '"complete":true' "$RUN/results.json"; then
	if grep -q '"failed":0' "$RUN/results.json"; then STATUS=0; else STATUS=1; fi
fi

# Erreurs Lua ou erreurs journalisées mentionnant le mod (ou son kit de test) : échec même si tout est « OK ».
ERRS=$(grep -a "ERROR\[" "$LOG" 2>/dev/null | grep -i "passionphoto\|stack traceback\|attempt to\|runtime error")
if [ -n "$ERRS" ]; then
	echo "!! erreurs journalisées :"
	echo "$ERRS" | head -15 | sed 's/^/   /'
	[ "$STATUS" = 0 ] && STATUS=1
fi
WARNS=$(grep -a "WARNING\[" "$LOG" 2>/dev/null | grep -i "passionphoto")
[ -n "$WARNS" ] && { echo "!! avertissements (non bloquants) :"; echo "$WARNS" | head -10 | sed 's/^/   /'; }

if [ "$STATUS" = 2 ]; then
	if [ "$CODE" = 142 ]; then echo "!! serveur arrêté après ${TIMEOUT} s (délai dépassé, -t pour l'allonger)"
	else echo "!! le serveur s'est arrêté (code $CODE) avant la fin des scénarios"; fi
	echo "---- dernières lignes du journal ($LOG) ----"
	grep -av "^\s*$" "$LOG" 2>/dev/null | tail -n 40
	tail -n 20 "$RUN/stdout.txt" 2>/dev/null
fi

if [ -d "$RUN/photos" ]; then
	echo "photos :"
	for f in "$RUN"/photos/*.png; do [ -f "$f" ] && echo "  $f"; done
fi
echo "artefacts : $RUN"

# garder les 10 derniers passages
ls -1dt "$RUNS"/*/ 2>/dev/null | tail -n +11 | while read -r d; do rm -r -- "$d"; done
[ "$KEEP" = 1 ] || rm -f -- "$WORLD/map.sqlite"
exit "$STATUS"
