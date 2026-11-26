#!/bin/sh
# Analyse statique du Lua : luacheck s'il est installé (config .luacheckrc), sinon contrôle de syntaxe LuaJIT.
# Avertissements non bloquants, erreurs bloquantes.
# La liste vient de find (qui ne suit PAS les liens symboliques) : .run/ contient un lien vers la racine du dépôt,
# qu'un parcours récursif suivrait en boucle. .headless/ contient des copies du mod : exclu aussi.
cd "$(dirname "$0")/.." || exit 1
files=$(find . \( -path ./.deps -o -path ./.run -o -path ./.headless -o -path ./.cache -o -path ./tests/_tmp \
	-o -path ./tests/unit/fixtures -o -path ./dist -o -path ./.git \) -prune -o -name '*.lua' -type f -print | sort)
status=0
if command -v luacheck >/dev/null 2>&1; then
	# shellcheck disable=SC2086
	luacheck --no-color -q $files || status=$?
	[ "$status" -le 1 ] && status=0   # 1 = avertissements seulement
else
	echo "luacheck absent : contrôle de syntaxe LuaJIT uniquement (installer : luarocks install luacheck)"
	for f in $files; do
		luajit -bl "$f" /dev/null >/dev/null || status=1
	done
fi
[ "$status" -eq 0 ] && echo "lint : OK ($(echo "$files" | wc -l | tr -d ' ') fichiers Lua)"
exit $status
