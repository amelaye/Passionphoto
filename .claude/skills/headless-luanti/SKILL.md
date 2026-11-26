---
name: headless-luanti
description: Faire tourner passionphoto dans le VRAI moteur Luanti 5.15.1 sans interface — runner de scénarios (tests en jeu automatisés, monde jetable, photos exportées en PNG), serveur de dev piloté sans client (commandes /pptest_* au nom d'un faux joueur, sonde de rendu, Lua), lecture des journaux. À utiliser pour vérifier une modification dans le moteur, reproduire un bug, simuler un changement, écrire un scénario, ou regarder une photo produite par le mod.
---

# Luanti headless pour passionphoto

**Jamais de fenêtre Luanti** sur le poste de l'utilisatrice (pas de client lancé, pas de capture d'écran) : tout
passe par un serveur headless. Pour voir une image, on l'exporte en PNG et on donne son lien.

## Prérequis (déjà prêts sur ce poste)
`make deps` remplit `.deps/` par copie locale, sans réseau : moteur **5.15.1** (copie de `../chester/.deps/luanti`),
minetest_game (copie de `../Awards/.audit_src/minetest_game`). Mods facultatifs : `PP_EXTRA_MODS="unifieddyes areas"
make deps` (copiés depuis `../Awards/.audit_src`) ; tous les dossiers de `.deps/mods/` sont chargés par les tests.
`tools/luanti_bin.sh` affiche le moteur retenu (`LUANTI_BIN` pour en forcer un).

## 1. Runner de scénarios (`tools/headless/run.sh`, `make sim`)
Un vrai serveur démarre sur un monde jetable contenant une **copie** de l'arbre de travail, le kit
`tests/passionphoto_test` et `.deps/mods/*`, exécute les scénarios puis s'arrête (~30 s pour la suite).
```sh
make sim                         # tout (singlenode : chaque scénario construit sa scène)
make sim F=moteur                # filtre sur le nom (sous-chaîne)
make sim G=v7 F=paysage          # vrai terrain généré (graine fixe PP_SEED, défaut 20261126)
make sim-min                     # sans les mods facultatifs : c'est là que cassent les « if mod then »
tools/headless/run.sh -s "$SCRATCH/essai.lua" -f adhoc   # scénario jetable, non commité
tools/headless/run.sh -o passionphoto_test.verbose=true -t 300 -k -q   # réglage en plus, délai, garder la carte, sortie courte
```
Codes : **0** tout passe · **1** un scénario échoue, un bug connu est CORRIGÉ, ou une erreur Lua mentionnant le mod est
journalisée · **2** plantage, délai dépassé ou aucun résultat (les 40 dernières lignes du journal sont affichées).
Artefacts : `.headless/runs/<id>/` (`debug.txt` journal complet, `results.json`, `photos/*.png`) ; `.headless/last`
pointe sur le dernier passage ; les 10 derniers sont gardés.
Journal : `RUN`, `OK`, `ÉCHEC` (+ raisons avec fichier:ligne), `CONNU`, `CORRIGÉ`, `IGNORÉ`, `BILAN`.

### Écrire un scénario
Fichiers `tests/passionphoto_test/scenarios/NN_sujet.lua` (ordre alphabétique). Nom : **`sujet: comportement`**
(sujets : `moteur`, `mesure`, `mod`, `appareil`, `pellicule`, `labo`, `tirage`, `photo`, `album`, `cadre`, `rendu`,
`securite`, `perf`). Scénario jetable : dans le scratchpad, nom préfixé `adhoc:`, lancé avec `-s fichier -f adhoc`.
```lua
local T = passionphoto_test
T.register("appareil: une pose consomme une vue de la pellicule", function(ctx)
	local view = T.scenes.studio(ctx)                       -- scène de référence + point de vue
	local p = ctx:fake_player("alice", { wield = "passionphoto:camera" })
	p:set_pos(vector.offset(view.eye, 0, -1.625, 0))
	p:set_look_horizontal(view.yaw); p:set_look_vertical(view.pitch)
	ctx:use(p)                                              -- clic gauche : on_use de l'objet tenu
	ctx:assert(ctx:wait_until(function() return … end, 10), "photo prête")   -- le serveur tourne pendant l'attente
	ctx:check_eq(…, 15, "vues restantes")                   -- check* note et continue, assert* arrête
	ctx:metric("ms", …)                                     -- chiffre dans results.json et le journal
	ctx:save_texture("pose", texture)                       -- exporte la photo du mod en PNG (lien dans le compte rendu)
end, { timeout = 30 })
```
Chaque scénario a sa zone (origine `idx*64, 0, 0`, rayon 24, générée et chargée de force à la demande) ; objets, faux
joueurs, zones protégées et heure sont remis en état après lui. Bug connu : `T.known_bug("B03 sujet: comportement
CORRECT", fn)` (skill passionphoto-testing). Abandon sans échec : `ctx:skip("raison")`.

### API du contexte `ctx`
| Groupe | Méthodes |
|---|---|
| Monde | `p(x,y,z)` (relatif → absolu), `prepare(r)`, `set(pos,nom,p2)`, `get`, `meta`, `fill(a,b,nom,p2)` (VoxelManip), `dump_area(a,b)`, `set_time(h)`, `protect(a,b,propriétaire)` |
| Temps | `wait(s)`, `wait_until(f, délai, pas)` → valeur ou nil |
| Résultats | `check`, `check_eq`, `check_near(a,b,tol)`, `assert*` (idem, arrête), `pcall(f,msg,…)`, `metric(k,v)`, `log(msg)`, `skip(raison)` |
| Joueurs | `fake_player(nom, {pos, yaw, pitch, wield, inv_size, privs, lang})` |
| Objets | `use(j, pointed)` (on_use), `secondary_use(j)`, `place(j, under, above)` (on_place / core.item_place), `rightclick_node(j,pos)`, `punch_node(j,pos)`, `dig_node(j,pos)`, `command(j, cmd, param)` |
| Inventaires | `inv(pos)`, `inv_put(j,pos,liste,i,pile)`, `inv_take(j,pos,liste,i,n)`, `inv_move(j,pos,de,i,vers,k,n)`, `detached_put/take(j, nom_inv, liste, i, …)` — comme le moteur : `allow_*` puis `on_*` |
| Formspecs | `last_formspec(j)` → fs, formname ; `submit(j, formname, champs)` (callbacks globaux) ; `submit_node(j, pos, champs)` ; `T.formspec_elements(fs, "image")`, `T.formspec_has(fs, type, texte)` |
| Effets | `sounds()`, `media()` (appels à dynamic_add_media), `chat(j)`, `find_entities(pos, r, nom)` ; `T.rec.formspecs/closed/chat_all/protection_violations` |
| Images | `save_png(nom, w, h, rgba|ColorSpec[], {scale})`, `save_texture(nom, "[png:…" | nom de média dynamique)` |
| Scènes | `T.scenes.studio(ctx)` (mur de laine colorée, arbre, eau, verre, torche) ; `T.scenes.paysage(ctx)` (terrain v7) → `{eye, target, yaw, pitch}` ; `T.look_angles(eye, cible)`, `T.surface_y(x, z, haut, bas)` |
| Sonde | `T.probe_render(eye, yaw, pitch, {w, h, fov, distance})` → `{raw, rays, us, distinct, mean_luma}` — sonde de faisabilité, PAS le rendu du mod |

### Faux joueurs (`lib/fake_player.lua`)
Table qui imite un joueur connecté : position, regard (`get_look_dir`…), inventaire détaché réel (`main` 32, `craft`),
méta, HUD (`hud_add/change/remove/get`, drapeaux), FOV et `zoom_fov`, contrôles, ciel, privilèges, langue.
Aides de test : `p:test_set_controls{ sneak = true }`, `p:test_look_at(pos)`, `p:test_eye_pos()`. État brut :
`p._state` (`huds`, `formspecs`, `chat`, `calls` = méthodes inconnues appelées).
Interceptions (`lib/intercept.lua`) quand la cible est un faux joueur : `core.get_player_by_name`,
`get_connected_players`, `show_formspec`, `close_formspec`, `chat_send_player`, `sound_play`, `dynamic_add_media`
(callback simulé), `get_player_information`, `check_player_privs`, `get_player_privs` ; `core.is_protected` suit
`ctx:protect`. **Le mod doit appeler ces fonctions via `core.` au moment de l'appel** (pas de copie locale au chargement).

## 2. Serveur de dev (`tools/server.sh`, `make server-*`)
Monde `.run/user/worlds/dev` (mapgen v7, graine fixe, créatif), 127.0.0.1:30002, mod lu en direct (lien vers le
dépôt) : **`make server-restart` après chaque modification** (pas de rechargement à chaud). Kit en mode « dev ».
```sh
make server-start
tools/server.sh cmd "/pptest_ground 0 0 0 10"     # pose le faux joueur « dev » sur le sol, lacet 0°, tangage 10°
tools/server.sh cmd "/pptest_scene studio 200 150 0"   # scène de référence EN ALTITUDE (sinon enfouie, image noire)
tools/server.sh cmd "/pptest_probe 96"            # sonde 96×96 depuis l'œil du faux joueur → chemin du PNG
tools/server.sh cmd "/pptest_give passionphoto:camera" ; tools/server.sh cmd "/pptest_use"
tools/server.sh lua "return me:get_wielded_item():get_meta():to_table()"   # me = faux joueur, T = kit
tools/server.sh photos                            # dernières images exportées (chemins absolus)
tools/server.sh logs [-f] ; make server-stop ; tools/server.sh reset   # reset efface le monde de dev
```
Commandes : `/pptest_tp x y z [lacet° tangage°]`, `/pptest_look`, `/pptest_lookat x y z`, `/pptest_where`,
`/pptest_ground`, `/pptest_load [rayon]` (charge la zone avant une photo, défaut ±96), `/pptest_scene`,
`/pptest_photo [taille] [ssaa] [fov]` (**rendu texturé du mod**, étalé sur plusieurs pas), `/pptest_probe [l] [h] [fov]`
(ancienne sonde raycast), `/pptest_give`, `/pptest_use`, `/pptest_secondary`, `/pptest_place x y z`, `/pptest_inv`,
`/pptest_formspec` (dernier formspec montré), `/pptest_fields formname k=v …`, `/pptest_lua code`. Toute autre
commande du mod ou message de chat passe aussi par `cmd`.
Trouver un point de vue : `tools/server.sh lua` avec `core.get_biome_data`/`core.get_biome_name` et
`core.get_spawn_level(x, z)` (nil sous l'eau) ; puis `/pptest_ground x z lacet tangage`, `/pptest_load`, `/pptest_photo 128`
dans plusieurs directions, et `python3 -I tools/contact_sheet.py .cache/previews/planche.png --cols 4 *.png` pour
comparer. Même graine (`PP_SEED`) = même terrain dans le runner (`-g v7`) : le point retenu devient un scénario.
Protocole : `tools/server.sh cmd` écrit `id<TAB>joueur<TAB>message` dans `<monde>/passionphoto_test_inbox.txt` et
affiche les lignes `id<TAB>…` de l'outbox jusqu'à `[fin]` (commande asynchrone : `T.dev_hold()` retient `[fin]`).
Essai en jeu par l'utilisatrice : SON client → Rejoindre → 127.0.0.1:30002, nom `dev` (admin). Ne jamais le lancer soi-même.

## Limites (à dire dans les comptes rendus)
- Aucun client : rien n'est affiché ni joué. Formspecs, HUD, textures, sons, médias dynamiques ne sont vérifiés que
  côté serveur (ce que le mod envoie). L'affichage réel est un test manuel de l'utilisatrice.
- Faux joueurs = tables : pas de physique, pas d'attachement réel, pas de connexion ; les fonctions moteur qui exigent
  un vrai ObjectRef (ex. `core.show_formspec` sans interception) échouent ou ne font rien.
- Temps réel (`dedicated_server_step = 0.05`) : tolérances larges sur les durées ; mesures de performance variables
  d'un passage à l'autre (JIT, système) : comparer des ordres de grandeur, répéter avant de conclure.
- Seul minetest_game est chargé (+ `.deps/mods`) : les autres mods du serveur AIM ne sont pas testés sans `make deps`.

## Dépannage
- Image noire : scène enfouie dans le terrain (construire en altitude) ou nuit (`ctx:set_time(0.5)`).
- Code 2 : lire la 1re erreur Lua et sa pile dans `debug.txt` (`grep -n "ERROR\|stack traceback" .headless/last/debug.txt`).
- « jeu absent » : `make deps`. Port du serveur de dev occupé : `PP_PORT=30003`.
- `pas de [fin]` : commande longue → `PP_CMD_TIMEOUT=180`, ou erreur dans `tools/server.sh logs`.
