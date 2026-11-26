#!/bin/sh
# Prépare .deps/ (ignoré par git) : ce qu'il faut pour faire tourner passionphoto dans un serveur headless.
#   .deps/games/minetest/   jeu minetest_game (requis : passionphoto dépend de « default »)
#   .deps/mods/<mod>/       mods facultatifs chargés par les tests (PP_EXTRA_MODS)
#   .deps/luanti/           moteur (la version de production d'AIM, 5.15.1)
#
# Par défaut tout est COPIÉ depuis des dossiers locaux, sans réseau :
#   jeu et mods : PP_DEPS_FROM (défaut ../Awards/.audit_src : sources des mods du serveur AIM, lecture seule)
#   moteur      : LUANTI_APP   (défaut ../chester/.deps/luanti : Luanti 5.15.1 déjà préparé pour chester)
# À défaut de source locale, le jeu est cloné (git --depth 1) ; le moteur est alors celui que trouve
# tools/luanti_bin.sh (/Applications/luanti.app = 5.18 : ce n'est pas la version de production).
#
# Variables :
#   PP_EXTRA_MODS="unifieddyes areas"   mods à copier en plus depuis PP_DEPS_FROM
#   PP_DEPS_LINK=1                      liens symboliques au lieu de copies (plus léger, dépend des sources)
# Les éléments déjà présents sont conservés (relancer le script est sans danger). Rien n'est écrit hors de .deps/.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
mkdir -p .deps/games .deps/mods

DEPS_FROM=${PP_DEPS_FROM:-}
if [ -z "$DEPS_FROM" ] && [ -d "$ROOT/../Awards/.audit_src" ]; then DEPS_FROM="$ROOT/../Awards/.audit_src"; fi
APP=${LUANTI_APP:-}
if [ -z "$APP" ] && [ -d "$ROOT/../chester/.deps/luanti" ]; then APP="$ROOT/../chester/.deps/luanti"; fi

import() { # <source> <destination>
	src=$(cd "$1" && pwd -P)
	if [ "${PP_DEPS_LINK:-0}" = 1 ]; then
		ln -s "$src" "$2"; echo "lien     $2 -> $src"
	elif command -v ditto >/dev/null 2>&1; then
		ditto "$src" "$2"; echo "copié    $2 <- $src"     # macOS : préserve la signature des .app
	else
		cp -R "$src" "$2"; echo "copié    $2 <- $src"
	fi
}

present() { # <destination> : vrai si déjà là (signale un lien cassé)
	if [ -L "$1" ] && [ ! -e "$1" ]; then echo "CASSÉ    $1 (lien vers un dossier disparu : le supprimer)"; return 0; fi
	if [ -e "$1" ]; then echo "présent  $1"; return 0; fi
	return 1
}

# jeu
if ! present .deps/games/minetest; then
	if [ -n "$DEPS_FROM" ] && [ -d "$DEPS_FROM/minetest_game" ]; then
		import "$DEPS_FROM/minetest_game" .deps/games/minetest
	else
		git clone -q --depth 1 https://github.com/luanti-org/minetest_game.git .deps/games/minetest
		echo "cloné    .deps/games/minetest"
	fi
fi

# mods facultatifs
for m in ${PP_EXTRA_MODS:-}; do
	present ".deps/mods/$m" && continue
	if [ -z "$DEPS_FROM" ] || [ ! -d "$DEPS_FROM/$m" ]; then
		echo "ignoré   $m (introuvable dans ${DEPS_FROM:-PP_DEPS_FROM non défini})"; continue
	fi
	import "$DEPS_FROM/$m" ".deps/mods/$m"
done

# moteur
if ! present .deps/luanti; then
	if [ -n "$APP" ] && [ -d "$APP/luanti.app" ]; then
		mkdir -p .deps/luanti
		import "$APP/luanti.app" .deps/luanti/luanti.app
	elif [ -n "$APP" ] && [ -d "$APP/bin" ]; then
		import "$APP" .deps/luanti
	else
		echo "moteur   aucune copie locale (LUANTI_APP) : tools/luanti_bin.sh cherchera ailleurs"
	fi
fi

echo "moteur   $(./tools/luanti_bin.sh 2>&1)"
