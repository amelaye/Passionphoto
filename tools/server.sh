#!/bin/sh
# Serveur Luanti de DÉVELOPPEMENT, headless, pour passionphoto. Tout vit dans .run/ (ignoré par git).
#
#   tools/server.sh start              démarre le serveur (monde v7 à graine fixe, créatif, 127.0.0.1:30002)
#   tools/server.sh stop               arrêt propre (le moteur sauvegarde)
#   tools/server.sh restart            recharge le code du mod (Luanti ne recharge pas les mods à chaud)
#   tools/server.sh status             état du serveur
#   tools/server.sh logs [-f]          journal (50 dernières lignes, ou suivi continu)
#   tools/server.sh cmd "/commande …"  exécute une commande (ou un message) au nom d'un FAUX joueur, sans client
#   tools/server.sh lua "code Lua"     exécute du Lua dans le serveur (raccourci de cmd "/pptest_lua …")
#   tools/server.sh photos [N]         N dernières images exportées (chemins absolus, défaut 10)
#   tools/server.sh reset              arrête le serveur et efface le monde de dev
#
# Variables : PP_PORT=30002  PP_LAN=1 (écoute le réseau local)  PP_PLAYER=dev (faux joueur de « cmd »)
#             PP_MAPGEN=v7  PP_SEED=20261126  PP_CMD_TIMEOUT=60 (s)  LUANTI_BIN=… (voir tools/luanti_bin.sh)
# Jamais de fenêtre Luanti lancée par un agent : pour essayer en jeu, l'utilisatrice connecte SON client
# (Rejoindre une partie → 127.0.0.1, port 30002, nom « dev » = admin).
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN="$ROOT/.run"
USERDIR="$RUN/user"
WORLD="$USERDIR/worlds/dev"
CONF="$RUN/luanti.conf"
LOG="$RUN/server.log"
PORT=${PP_PORT:-30002}
INBOX="$WORLD/passionphoto_test_inbox.txt"
OUTBOX="$WORLD/passionphoto_test_outbox.txt"
OUTDIR="$WORLD/passionphoto_test_out"

is_running() { # <fichier pid>
	[ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null
}

prepare() {
	[ -d "$ROOT/.deps/games/minetest" ] || { echo "dépendances absentes : lancer make deps (tools/fetch_deps.sh)"; exit 1; }
	mkdir -p "$USERDIR/games" "$WORLD/worldmods"
	[ -e "$USERDIR/games/minetest" ] || ln -s "$ROOT/.deps/games/minetest" "$USERDIR/games/minetest"
	# mods du monde : passionphoto (le dépôt lui-même, code lu en direct), le kit de test en mode « dev »,
	# et tout .deps/mods/*
	for link in "$WORLD"/worldmods/*; do [ -L "$link" ] && rm "$link"; done
	ln -s "$ROOT" "$WORLD/worldmods/passionphoto"
	ln -s "$ROOT/tests/passionphoto_test" "$WORLD/worldmods/passionphoto_test"
	for m in "$ROOT"/.deps/mods/*; do
		[ -d "$m" ] && ln -s "$m" "$WORLD/worldmods/$(basename "$m")"
	done
	[ -f "$WORLD/world.mt" ] || cat > "$WORLD/world.mt" <<EOF
gameid = minetest
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
EOF
	bind="127.0.0.1"; [ "${PP_LAN:-0}" = 1 ] && bind="0.0.0.0"
	cat > "$CONF" <<EOF
# Généré par tools/server.sh — serveur de DÉVELOPPEMENT (ne pas copier en production)
port = $PORT
bind_address = $bind
server_announce = false
server_name = Passion Photo (dev)
name = dev
mg_name = ${PP_MAPGEN:-v7}
fixed_map_seed = ${PP_SEED:-20261126}
creative_mode = true
enable_damage = false
default_privs = interact, shout, fly, fast, noclip, give, teleport, settime
secure.enable_security = true
passionphoto_test.mode = dev
EOF
}

cmd_start() {
	if is_running "$RUN/server.pid"; then echo "déjà démarré (pid $(cat "$RUN/server.pid"))"; return 0; fi
	SRV=$("$ROOT/tools/luanti_bin.sh") || exit 1
	prepare
	rm -f "$INBOX" "$OUTBOX"
	: > "$LOG"
	# shellcheck disable=SC2086
	MINETEST_USER_PATH="$USERDIR" LUANTI_USER_PATH="$USERDIR" nohup $SRV --world "$WORLD" --config "$CONF" \
		--logfile "$LOG" > "$RUN/server.out" 2>&1 &
	echo $! > "$RUN/server.pid"
	i=0
	until grep -aq "listening on" "$LOG" 2>/dev/null; do
		if ! is_running "$RUN/server.pid"; then
			echo "le serveur s'est arrêté au démarrage :"; grep -a "ERROR" "$LOG" | tail -20; tail -5 "$RUN/server.out"
			exit 1
		fi
		i=$((i + 1)); [ $i -gt 120 ] && { echo "pas prêt après 60 s (voir $LOG)"; exit 1; }
		sleep 0.5
	done
	echo "serveur : $($SRV --version 2>/dev/null | head -1) — 127.0.0.1:$PORT (pid $(cat "$RUN/server.pid"))"
	grep -a "\[passionphoto\]\|\[passionphoto_test\]" "$LOG" | sed 's/^/  /'
	grep -a "ERROR\|WARNING.*passionphoto" "$LOG" | sed 's/^/  ! /' | head -20
}

cmd_stop() {
	if is_running "$RUN/server.pid"; then
		pid=$(cat "$RUN/server.pid")
		kill -TERM "$pid"
		i=0
		while kill -0 "$pid" 2>/dev/null; do
			i=$((i + 1)); [ $i -gt 60 ] && { echo "arrêt forcé"; kill -KILL "$pid"; break; }
			sleep 0.25
		done
		echo "serveur arrêté"
	else
		echo "serveur non démarré"
	fi
	rm -f "$RUN/server.pid"
}

cmd_status() {
	if is_running "$RUN/server.pid"; then echo "serveur : en marche (pid $(cat "$RUN/server.pid"), port $PORT)"
	else echo "serveur : arrêté"; fi
}

cmd_logs() {
	[ -f "$LOG" ] || { echo "aucun journal"; exit 1; }
	if [ "${1:-}" = "-f" ]; then tail -f "$LOG"; else tail -n 50 "$LOG"; fi
}

# Protocole avec le kit de test (tests/passionphoto_test/dev.lua) :
#   inbox  : « id<TAB>joueur<TAB>message »    outbox : « id<TAB>texte » … puis « id<TAB>[fin] »
cmd_cmd() {
	msg=${1:-}
	[ -n "$msg" ] || { echo 'usage : tools/server.sh cmd "/pptest_where"'; exit 1; }
	is_running "$RUN/server.pid" || { echo "serveur non démarré (tools/server.sh start)"; exit 1; }
	player=${PP_PLAYER:-dev}
	id="c$(date +%s)_$$"
	pat=$(printf '^%s\t' "$id")
	touch "$OUTBOX"
	printf '%s\t%s\t%s\n' "$id" "$player" "$msg" >> "$INBOX"
	timeout=${PP_CMD_TIMEOUT:-60}
	waited=0; shown=0
	while [ "$waited" -lt $((timeout * 4)) ]; do
		n=$(grep -ac "$pat" "$OUTBOX" 2>/dev/null)
		if [ "${n:-0}" -gt "$shown" ]; then
			new=$(grep -a "$pat" "$OUTBOX" | sed -n "$((shown + 1)),${n}p" | cut -f2-)
			shown=$n
			echo "$new" | grep -v '^\[fin\]$' | sed 's/\\n/\
/g'
			echo "$new" | grep -q '^\[fin\]$' && return 0
		fi
		sleep 0.25; waited=$((waited + 1))
	done
	echo "(pas de [fin] après ${timeout} s — voir tools/server.sh logs ; PP_CMD_TIMEOUT pour attendre plus)"
	return 1
}

cmd_photos() {
	ls -1t "$OUTDIR"/*.png 2>/dev/null | head -n "${1:-10}"
}

cmd_reset() {
	cmd_stop
	if [ -d "$WORLD" ]; then rm -r "$WORLD"; echo "monde de dev effacé"; fi
}

case "${1:-}" in
	start) cmd_start ;;
	stop) cmd_stop ;;
	restart) cmd_stop; cmd_start ;;
	status) cmd_status ;;
	logs) cmd_logs "${2:-}" ;;
	cmd) cmd_cmd "${2:-}" ;;
	lua) cmd_cmd "/pptest_lua ${2:-}" ;;
	photos) cmd_photos "${2:-}" ;;
	reset) cmd_reset ;;
	*) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
