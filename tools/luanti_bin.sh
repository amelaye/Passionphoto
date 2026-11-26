#!/bin/sh
# Affiche la commande qui lance un serveur Luanti headless (binaire + éventuel « --server »), ou échoue.
# Ordre de recherche :
#   1. $LUANTI_BIN (chemin d'un luantiserver, ou d'un client « luanti » lancé avec --server)
#   2. .deps/luanti/ : moteur préparé par tools/fetch_deps.sh (la version de production, 5.15.1)
#   3. luantiserver / minetestserver dans le PATH (Linux)
#   4. /Applications/luanti.app (macOS, 5.18 sur le poste)
# Le client n'est JAMAIS lancé en fenêtre : toujours avec --server (headless).
cd "$(dirname "$0")/.." || exit 1
wrap() {
	case "$1" in
		*luantiserver|*minetestserver) echo "$1" ;;
		*) echo "$1 --server" ;;
	esac
}
if [ -n "${LUANTI_BIN:-}" ]; then
	[ -x "$LUANTI_BIN" ] || { echo "LUANTI_BIN=$LUANTI_BIN n'est pas exécutable" >&2; exit 1; }
	wrap "$LUANTI_BIN"; exit 0
fi
for c in .deps/luanti/luanti.app/Contents/MacOS/luanti .deps/luanti/bin/luantiserver .deps/luanti/bin/luanti; do
	[ -x "$c" ] && { wrap "$(pwd)/$c"; exit 0; }
done
for c in luantiserver minetestserver; do
	p=$(command -v "$c" 2>/dev/null) && { wrap "$p"; exit 0; }
done
[ -x /Applications/luanti.app/Contents/MacOS/luanti ] && { wrap /Applications/luanti.app/Contents/MacOS/luanti; exit 0; }
echo "Aucun moteur Luanti trouvé : définir LUANTI_BIN ou lancer tools/fetch_deps.sh (make deps)" >&2
exit 1
