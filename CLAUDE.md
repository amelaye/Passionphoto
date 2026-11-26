# CLAUDE.md — Passion Photo (`passionphoto`)

Référence permanente pour l'agent principal et les sous-agents. À lire avant toute modification.

## 1. Le projet

Mod Luanti **`passionphoto`** pour le serveur pacifique et semi-roleplay *Amelaye in Minerland* (AIM) : la photographie
argentique, **inspirée de près du mod Minecraft Exposure** pour les mécaniques — appareil photo et viseur, pellicules,
accessoires (objectif, filtre, flash), développement, tirage, photos à ranger dans un **album** ou à accrocher **au mur**.
Noms, textures, sons et code sont **originaux** (rien de repris d'Exposure ni de Minecraft).

État : outillage en place (étape 0) ; **rendu texturé des photos en cours** (étape 2 : `src/lib/`, `src/render/`) ; pas
encore d'objets jouables. Conception, étapes, décisions, questions ouvertes et bugs : `docs/PLAN.md`.
Outillage : `docs/TOOLING.md`.

## 2. Environnement et compatibilité

- Production : **Luanti 5.15.1**, serveur Linux, `/home/minetest/luanti5_15_1/mods/` (non accessible depuis le poste).
  Jeu : minetest_game. Liste réelle des mods du serveur : `../Awards/docs/audit/server_mods.txt` ; sources en lecture
  seule dans `../Awards/.audit_src/`. Le nom d'un mod est celui de son `mod.conf`, pas celui du dossier.
- Développement : moteur 5.15.1 dans `.deps/luanti` (tests headless) ; `/Applications/luanti.app` est en 5.18 et ne
  prouve rien pour la production. **Aucune API postérieure à 5.15** (doc : `.cache/lua_api_5.15.1.md`).
- API `core.*` (pas `minetest.*`). Lua 5.1 / LuaJIT : pas d'opérateurs 5.3, `unpack` (pas `table.unpack`).
- Dépendance : `default` ; facultatives à déclarer au fil des intégrations (`dye`, `unifieddyes`, `binoculars`…), toujours
  protégées par `core.get_modpath`.

## 3. Règles de sécurité (impératives)

1. Ne jamais modifier un mod tiers, `../Awards`, `../chester`, ni les dossiers générés `.deps/`, `.run/`, `.headless/`.
2. Ne jamais toucher aux mondes, sauvegardes ni à l'installation Luanti de l'utilisatrice.
3. **Jamais de fenêtre Luanti** sur le poste (pas de client lancé, pas de capture d'écran) : tout passe par le serveur
   headless ; une image se regarde en PNG exporté. L'essai en jeu, c'est l'utilisatrice qui le fait avec SON client.
4. Aucune action sur le serveur de production sans autorisation écrite (ssh/scp/rsync : toujours demander).
5. Aucune commande destructive (`rm -rf` hors dossiers générés du projet, `git reset --hard`, `git clean`).
6. **Formulaires hostiles** : les champs reçus ne servent qu'à naviguer ; index, identifiants et textes sont revalidés,
   le contexte est revérifié (objet tenu, nœud présent, distance, protection), tout texte affiché est échappé.
7. **Aucune duplication** : les accessoires, pellicules, photos et contenus de nœuds passent par des inventaires dont
   chaque mouvement est contrôlé (`allow_*`) et réécrit dans la méta ; creuser un nœud en cours de traitement rend tout.
8. **Disque** : écriture seulement dans le dossier du monde ; noms de fichiers construits à partir d'identifiants
   numériques, jamais d'un texte joueur ; quotas de photos et limite de cadence des déclenchements.
9. **Le rendu ne bloque jamais le serveur** : travail étalé sur plusieurs pas avec un budget mesuré (skill photo-render).
10. Aucun privilège accordé ; la protection (`core.is_protected`) est respectée pour poser et retirer.

## 4. Architecture cible (proposée, détail et décisions : `docs/PLAN.md`)

```
passionphoto/
  init.lua            -- chargement ordonné, rien d'autre ; une seule globale : passionphoto
  src/config.lua      -- constantes (résolution, poses, durées, quotas) — pas de réglage sauf demande
  src/lib/*.lua       -- logique PURE (pas de core au chargement) : décodage PNG, couleurs, chaînes de texture,
                      -- pellicules et courbes, quotas… testée sous LuaJIT (tests/unit/)
  src/storage.lua     -- identifiants et index des photos (mod storage), fichiers <monde>/passionphoto/, quotas
  src/media.lua       -- médias dynamiques : envoi à la demande, ré-ajout au démarrage
  src/render/         -- textures.lua (index + décodage + composition), nodes.lua (fiche par content_id),
                      -- raymarch.lua (parcours de rayons, travail étalable) ; file de rendus à venir
  src/camera.lua      -- appareil : accessoires, viseur (HUD, FOV), réglages, déclenchement
  src/items.lua       -- pellicules, chimie, papier, encres, objectifs, filtres, flash (données)
  src/darkroom.lua    -- cuve de développement ; src/enlarger.lua -- tirage
  src/photo.lua       -- photo, visionneuse, photo vieillie, piles ; src/album.lua ; src/frame.lua (cadres + LBM)
  src/ui/theme.lua    -- thème « chambre noire » et aides de formspec ; src/crafts.lua ; src/admin.lua
  textures/ sounds/ locale/
```
- Modules : `local M = {}` … `return M`, chargés par `dofile` depuis `init.lua`, rangés dans `passionphoto.<module>`.
- Les définitions (types de pellicules, objectifs, filtres) sont des **données** : ajouter un objectif = ajouter une
  entrée, jamais modifier le cœur.
- Boucles chaudes du rendu : pas d'allocation de tables, pas d'accès aux registres par nom (tables par `content_id`).

## 5. Conventions

- Indentation tabulations, lignes ≤ 120 colonnes, `local` partout, fonctions courtes, pas de code mort.
- Textes joueurs : écrits **en français** via `local S = core.get_translator("passionphoto")`, traduits en anglais dans
  `locale/passionphoto.en.tr` (`make i18n`). Jamais de texte joueur en dur sans `S()`.
- Préfixes : objets et nœuds `passionphoto:` ; textures et sons `passionphoto_` ; formname `passionphoto:<écran>` ;
  champs de formulaire `pp_` ; commandes `/pp_…` (`/pptest_…` est réservé au kit de test).
- Valeurs fixes en constantes nommées dans `src/config.lua` ; **pas de `settingtypes.txt`** sauf demande explicite.
- Journaux : `core.log("action"|"warning"|"error", "[passionphoto] …")`.
- Identifiants (photos, objets, clés de méta) **immuables** une fois publiés ; format des données versionné.
- Appeler `core.show_formspec`, `core.get_player_by_name`, `core.chat_send_player`, `core.sound_play`,
  `core.dynamic_add_media` via `core.` au moment de l'appel (le kit de test les intercepte) : pas de copie locale.

## 6. Photos : rendu, stockage, affichage (détail : skill photo-render)

- Une photo est **recalculée par le serveur** : parcours de rayons en Lua avec `core.get_node_raw` (7 à 12 µs/rayon
  mesuré, 5 à 8 fois moins que `core.raycast`, à ne pas appeler par pixel), **texture du nœud échantillonnée au point
  d'impact** (décodeur PNG Lua), lumière jour/nuit avec la courbe du client, ciel, eau, puis (à venir) entités,
  pellicule, filtres et flash. 256 px anticrénelé ≈ 1,6–4,9 s de calcul, toujours étalé en tâche de fond.
- Image dans `<monde>/passionphoto/<id>.png`, index dans le mod storage, objets ne contenant que l'identifiant.
- Affichage par médias dynamiques (`passionphoto_p<id>.png`), attendus avant d'ouvrir une visionneuse.

## 7. Commandes

```sh
make check            # lint, traductions, tests unitaires — après chaque modification (quelques secondes)
make sim              # scénarios dans un VRAI serveur Luanti 5.15.1 headless (~30 s) ; F=filtre, S=adhoc.lua, G=v7
make sim-min          # idem sans les mods facultatifs de .deps/mods/
make deps             # prépare .deps/ (copies locales : moteur 5.15.1, minetest_game ; PP_EXTRA_MODS="…")
make server-start     # serveur de dev headless (.run/, 127.0.0.1:30002) ; server-stop / server-restart / server-logs
make cmd C="/pptest_where"        # commande au serveur de dev sans client (faux joueur « dev »)
tools/server.sh lua "return …"    # Lua dans le serveur de dev ; tools/server.sh photos : images exportées
make i18n             # après ajout/modification d'un S("…") : met à jour locale/ (puis traduire)
make textures         # compile tools/textures_src/*.px en textures/*.png
make dist             # archive du mod seul : dist/passionphoto-<version>.zip
```

## 8. Tests (détail : skills passionphoto-testing et headless-luanti)

- **Unitaires** (`tests/unit/`, LuaJIT) : logique pure de `src/lib/`. Ils ne prouvent pas le moteur.
- **Scénarios** (`tests/passionphoto_test/scenarios/`, vrai serveur headless, faux joueurs) : seuls ils autorisent à
  écrire « testé dans le moteur ». Ne jamais annoncer un résultat qui n'a pas tourné.
- **Bugs connus** : `T.known_bug` décrit le comportement correct ; il bascule en `CORRIGÉ` (bloquant) une fois réparé
  → test normal et bug coché dans `docs/PLAN.md`.
- Compte rendu : sorties réelles (`BILAN`, mesures), et **un lien markdown cliquable par image produite**.

## 9. Critères de validation d'un changement

- `make check` passe sans nouvel avertissement luacheck ; `make sim` passe (`make sim-min` si les dépendances bougent).
- Tout changement de comportement : test unitaire ou scénario ajouté ou mis à jour.
- Tout changement du rendu : mesures (`-f mesure`, `-f rendu`) et images avant/après dans le compte rendu.
- Formulaires, inventaires, fichiers, cadres : revue `luanti-reviewer`.
- Décision technique non triviale : une ligne dans `docs/PLAN.md` (Décisions).

## 10. Livraison

`make dist` → `dist/passionphoto-<version>.zip` (le mod seul : ni tools/, ni tests/, ni docs/). Installation en
production : **par l'administratrice**, jamais par un agent. Procédure : skill `release-deploy`.
