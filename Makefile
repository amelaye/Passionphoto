# Passion Photo — commandes de développement (détail : docs/TOOLING.md)
VERSION := $(shell sed -n 's/^version *= *//p' mod.conf)
ifeq ($(VERSION),)
VERSION := dev
endif

.PHONY: help check lint test sim sim-min deps server-start server-stop server-restart server-status server-logs \
	cmd photos i18n i18n-check textures dist clean

help:            ## liste des commandes
	@grep -E '^[a-z-]+:.*##' Makefile | sed 's/:.*## /	/'

check: lint i18n-check test ## sans moteur : lint, traductions, tests unitaires (quelques secondes)

lint:            ## luacheck (ou syntaxe LuaJIT si absent)
	@./tools/lint.sh

test:            ## tests unitaires de la logique pure (LuaJIT) ; un fichier : luajit tests/unit/run.lua <filtre>
	@luajit tests/unit/run.lua

sim:             ## scénarios dans un VRAI serveur headless : make sim [F=filtre] [S=adhoc.lua] [G=v7]
	@./tools/headless/run.sh $(if $(F),-f "$(F)") $(if $(S),-s "$(S)") $(if $(G),-g "$(G)")

sim-min:         ## idem, sans les mods facultatifs de .deps/mods/
	@./tools/headless/run.sh -M $(if $(F),-f "$(F)") $(if $(S),-s "$(S)") $(if $(G),-g "$(G)")

deps:            ## prépare .deps/ (moteur 5.15.1, minetest_game, mods) — voir tools/fetch_deps.sh
	@./tools/fetch_deps.sh

server-start:    ## démarre le serveur de dev headless (.run/, 127.0.0.1:30002)
	@./tools/server.sh start

server-stop:     ## arrête le serveur de dev
	@./tools/server.sh stop

server-restart:  ## redémarre le serveur de dev (recharge le code du mod)
	@./tools/server.sh restart

server-status:   ## état du serveur de dev
	@./tools/server.sh status

server-logs:     ## dernières lignes du journal du serveur de dev
	@./tools/server.sh logs

cmd:             ## commande au serveur de dev, sans client : make cmd C="/pptest_where"
	@./tools/server.sh cmd "$(C)"

photos:          ## dernières images exportées par le serveur de dev
	@./tools/server.sh photos

i18n:            ## extrait les S("…") et met à jour locale/ (modèle + entrées manquantes)
	@python3 -I tools/i18n.py

i18n-check:      ## traductions complètes et modèle à jour
	@python3 -I tools/i18n.py --check

textures:        ## compile tools/textures_src/*.px en textures/*.png
	@if ls tools/textures_src/*.px >/dev/null 2>&1; then python3 -I tools/pixelart.py build tools/textures_src; \
	else echo "aucune source .px dans tools/textures_src/"; fi

dist: check      ## archive du mod seul : dist/passionphoto-<version>.zip
	@./tools/dist.sh $(VERSION)

clean:           ## supprime dist/, tests/_tmp/ et les passages du runner (jamais .run/ ni .deps/)
	@rm -rf dist tests/_tmp .headless
