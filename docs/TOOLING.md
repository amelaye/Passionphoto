# Outillage de passionphoto

Tout s'exécute depuis la racine du dépôt. Aucun outil n'écrit hors du dépôt ; les dossiers générés sont `.deps/`,
`.run/`, `.headless/`, `.cache/` et `dist/` (tous ignorés par git). Aucune fenêtre Luanti n'est jamais ouverte.

## 1. Configuration Claude Code

| Élément | Rôle |
|---|---|
| `CLAUDE.md` | Référence permanente : projet, sécurité, architecture cible, conventions, commandes, critères. |
| `.claude/skills/*/SKILL.md` | 7 skills : `luanti-api`, `headless-luanti`, `passionphoto-testing`, `photo-render`, `formspec-ui`, `pixel-art-assets`, `release-deploy`. |
| `.claude/agents/*.md` | 6 sous-agents (chacun précharge ses skills) : `game-designer`, `luanti-developer`, `render-engineer`, `qa-tester`, `luanti-reviewer`, `pixel-artist`. |
| `.claude/hooks/check_edit.py` | Après chaque Edit/Write : syntaxe Lua (LuaJIT + luacheck), Python, JSON, shell (sh/bash) ; format des sources `.px` ; en-tête des `.tr` ; frontmatter des agents/skills ; refuse toute écriture dans `.deps/`, `.run/`, `.headless/`. |
| `.claude/settings.json` | Permissions du projet et branchement du hook. |
| `.cache/lua_api_5.15.1.md` | Copie de la doc officielle de la version de production (à chercher par grep). |

Permissions : autorisé sans demande `make`, `luajit`, `luacheck`, `tools/*`, `python3 -I tools/*`,
`git status/diff/log/show`, lecture de `../Awards` ; confirmation pour `ssh`/`scp`/`rsync`, `git commit/push`, `pip`,
création de venv, `brew` ; interdit d'écrire dans `.deps/`, `.run/`, `.headless/`, `../Awards`, `../chester`,
`rm -rf`, `git reset --hard`, `git clean`.

| Agent | Quand |
|---|---|
| `game-designer` | préciser une étape, des recettes, une question de gameplay (ne code pas) |
| `luanti-developer` | réaliser une étape de `docs/PLAN.md`, corriger un bug Bxx |
| `render-engineer` | moteur de rendu, qualité d'image, performance du rendu |
| `qa-tester` | après chaque étape, avant livraison ; chasse aux abus et aux duplications |
| `luanti-reviewer` | avant livraison, après un changement de formulaires, inventaires, fichiers, rendu, cadres (lecture seule) |
| `pixel-artist` | textures et sons originaux |

## 2. Commandes (`Makefile`)

| Commande | Effet |
|---|---|
| `make check` | lint + traductions (`i18n-check`) + tests unitaires |
| `make lint` | `tools/lint.sh` : luacheck (`.luacheckrc`) ou, à défaut, syntaxe LuaJIT |
| `make test` | `luajit tests/unit/run.lua` (un fichier : `luajit tests/unit/run.lua <filtre>`) |
| `make sim` | `tools/headless/run.sh` : scénarios dans un vrai serveur 5.15.1 ; `F=` filtre, `S=` scénario ad hoc, `G=v7` |
| `make sim-min` | idem sans les mods facultatifs de `.deps/mods/` |
| `make deps` | `tools/fetch_deps.sh` : prépare `.deps/` par copies locales |
| `make server-start` / `server-stop` / `server-restart` / `server-status` / `server-logs` | serveur de dev |
| `make cmd C="…"` | commande au serveur de dev sans client (faux joueur `dev`) |
| `make photos` | dernières images exportées par le serveur de dev |
| `make i18n` / `make i18n-check` | `tools/i18n.py` : extrait les `S("…")`, met à jour `locale/` / vérifie |
| `make textures` | `tools/pixelart.py build tools/textures_src` |
| `make dist` | `make check` puis `dist/passionphoto-<version>.zip` (mod seul) |
| `make clean` | supprime `dist/`, `tests/_tmp/`, `.headless/` (jamais `.run/` ni `.deps/`) |

## 3. Scripts (`tools/`)

| Script | Rôle |
|---|---|
| `fetch_deps.sh` | `.deps/games/minetest` (copie de `../Awards/.audit_src/minetest_game`, sinon clone git), `.deps/luanti` (copie de `../chester/.deps/luanti` = 5.15.1), `.deps/mods/<m>` pour `PP_EXTRA_MODS`. `PP_DEPS_FROM`, `LUANTI_APP`, `PP_DEPS_LINK=1`. |
| `luanti_bin.sh` | Choisit le moteur : `$LUANTI_BIN`, `.deps/luanti`, `luantiserver` du PATH, `/Applications/luanti.app` ; toujours `--server`. |
| `headless/run.sh` | Runner de scénarios : monde jetable dans `.headless/runs/<id>/` (copie du mod + kit de test + `.deps/mods`), config sécurisée, chien de garde, résultats (`results.json`), photos (`photos/*.png`), codes 0/1/2. Options `-f -s -g -M -o -t -k -q`. |
| `server.sh` | Serveur de dev headless dans `.run/` : `start`, `stop`, `restart`, `status`, `logs [-f]`, `cmd "…"`, `lua "…"`, `photos [N]`, `reset`. Variables `PP_PORT` (30002), `PP_LAN`, `PP_PLAYER`, `PP_MAPGEN`, `PP_SEED`, `PP_CMD_TIMEOUT`. |
| `lint.sh`, `dist.sh` | Voir `make lint`, `make dist`. |
| `i18n.py` | Traductions (repris de chester ; source française, `passionphoto.en.tr`). |
| `pixelart.py` | Pixel art (repris de Cavepatate) : `build` (.px → PNG), `preview` (agrandi, mosaïque) vers `.cache/previews/`, `extract`, `palette`. |
| `contact_sheet.py` | Planche contact de PNG (grille, agrandissement) pour comparer des rendus : `python3 -I tools/contact_sheet.py sortie.png --cols 4 a.png b.png …`. |
| `gen_png_fixtures.py` | Génère les PNG de test du décodeur Lua et leur résultat attendu (`tests/unit/fixtures/png/`), encodés en Python indépendamment du décodeur. |

## 4. Tests

- **Unitaires** (`tests/unit/`) : `harness.lua` (describe/it/known_bug, eq/near/ok/contains/raises/deep_eq), `run.lua`,
  `test_*.lua` : `test_png.lua` (23 images de test + toutes les textures de minetest_game si `.deps/` est présent),
  `test_texstring.lua`, `test_harness.lua`. Pour la logique pure de `src/lib/`.
- **Kit headless** (`tests/passionphoto_test/`, mod jamais livré, inactif sans `passionphoto_test.mode`) :
  - `lib/intercept.lua` : interceptions moteur pour les faux joueurs (formspecs, chat, sons, médias, privilèges, protection) ;
  - `lib/fake_player.lua` : faux joueurs ; `lib/ctx.lua` : contexte des scénarios ; `lib/png.lua` : export d'images ;
  - `lib/scenes.lua` : scènes de référence (studio, paysage) ; `lib/probe_render.lua` : sonde de faisabilité (raycast) ;
  - `runner.lua` (mode « scenarios ») ; `dev.lua` (mode « dev » : boîte de réception/sortie, commandes `/pptest_*`) ;
  - `scenarios/00_moteur.lua` (capacités du moteur), `01_mod.lua` (chargement), `02_mesures.lua` (coût d'un rayon),
    `03_rendu.lua` (rendu texturé du mod : studio 128/256 px, nuit, paysage v7 au point de vue de référence).
  - Commandes de dev pour le rendu : `/pptest_load`, `/pptest_photo` (voir le skill headless-luanti).

## 5. État au 26/11/2026 (étape 0 faite, étape 2 en cours)

- `.deps/` : Luanti 5.15.1 (copie de chester) et minetest_game (copie de l'audit Awards) ; pas de mod facultatif.
- `make check` : lint OK (0 avertissement), 0 message à traduire, 33 tests unitaires réussis.
- `make sim` (5.15.1, singlenode) : 13 scénarios réussis, 2 ignorés (paysages, qui demandent `-g v7`) ;
  `make sim G=v7 F=paysage` : 2 réussis. Mesures : `docs/PLAN.md` §4.
- Serveur de dev : démarrage, `cmd`, `/pptest_ground`, `/pptest_load`, `/pptest_scene`, `/pptest_photo`,
  `/pptest_probe`, `lua`, `photos`, arrêt vérifiés.
