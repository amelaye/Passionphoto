---
name: luanti-api
description: Aide-mémoire vérifié de l'API Lua de Luanti 5.15.1 (version de production d'AIM) pour passionphoto — objets et métadonnées, clics, contrôles et regard du joueur, zoom/FOV, HUD, lecture rapide du monde (get_node_raw, raycast, lumière), PNG et médias dynamiques, fichiers et sécurité des mods, formspecs, nœuds muraux et entités, inventaires détachés, sons, protection. À utiliser avant d'écrire ou de relire du code Lua du mod, ou pour vérifier qu'une fonction existe et se comporte comme supposé.
---

# API Luanti 5.15.1 pour passionphoto

## Règle d'or : ne jamais supposer une API
Vérifier dans l'ordre :
1. **Doc officielle de la version de production** : `.cache/lua_api_5.15.1.md` (12 000 lignes : `grep -n`, ne pas la lire
   en entier). Absente ? `curl -sfL -o .cache/lua_api_5.15.1.md https://raw.githubusercontent.com/luanti-org/luanti/5.15.1/doc/lua_api.md`
2. **Sources** : minetest_game dans `.deps/games/minetest/mods/` ; mods du serveur AIM dans `../Awards/.audit_src/<mod>/`
   (lecture seule ; liste réelle des mods installés : `../Awards/docs/audit/server_mods.txt`).
3. **Le moteur lui-même** : scénario ad hoc (`tools/headless/run.sh -s essai.lua -f adhoc`) ou
   `tools/server.sh lua "return core.xxx(...)"` (skill headless-luanti).
Le moteur du poste `/Applications/luanti.app` est en 5.18 : un comportement vu seulement là n'est pas une preuve.
Les tests headless tournent sur `.deps/luanti` = 5.15.1. Une API plus récente que 5.15 est interdite.

Mesuré dans le moteur 5.15.1 (scénarios `moteur:` et `mesure:`) : toutes les API de ce document existent ; les chiffres
cités viennent de ces passages.

## Objets et métadonnées (ItemStack)
- Méta d'objet = le seul stockage par objet : `stack:get_meta()` (`get_string/set_string/get_int/set_int/get_float/…`).
  Y mettre des **identifiants** (photo, pellicule), jamais des images : la méta voyage dans les inventaires.
- Clés spéciales lues par le moteur : `description`, `short_description`, `inventory_image`, `inventory_overlay`,
  `wield_image`, `wield_overlay`, `wield_scale` (vector.to_string), `color`, `palette_index`, `count_meta` (texte à la
  place du nombre, ex. poses restantes), `count_alignment`. Une photo peut donc avoir sa propre vignette d'inventaire.
- Objets avec méta différente = piles différentes ; `stack_max = 1` pour appareil, pellicule, photo, album.

## Clics avec un objet en main
| Callback | Quand | Retour |
|---|---|---|
| `on_use(itemstack, user, pointed_thing)` | clic gauche (remplace le minage pour cet objet) | ItemStack → remplace l'objet tenu ; nil → inchangé |
| `on_secondary_use(itemstack, user, pointed_thing)` | clic droit sans nœud pointé | idem |
| `on_place(itemstack, placer, pointed_thing)` | clic droit sur un nœud | idem ; **appeler soi-même** `on_rightclick` du nœud si le joueur ne s'accroupit pas (sinon un appareil empêcherait d'ouvrir les coffres) |
| `on_drop(itemstack, dropper, pos)` | touche Q | idem |
`user`/`placer` peut être nil ou un non-joueur (déployeurs, pipeworks) : tester `user and user:is_player()`.

## Joueur : contrôles, regard, zoom, HUD
- `player:get_player_control()` → booléens `up down left right jump aux1 sneak dig place zoom` (+ `LMB`/`RMB` alias,
  `movement_x/y`). **Pas de molette** : le serveur ne voit que le changement d'emplacement de la barre (`get_wield_index`).
- Regard : `get_look_dir()`, `get_look_horizontal()` (lacet : 0 = +Z, croît vers −X), `get_look_vertical()` (tangage > 0 =
  vers le bas). Œil = `get_pos()` + (0, `get_properties().eye_height`, 0) + `get_eye_offset()` (1re personne) / 10.
- FOV : le FOV réel du client n'est pas connu du serveur (réglage client `fov`, 72° **vertical** par défaut).
  `player:set_fov(fov, is_multiplier, transition_time)` l'impose ; `get_fov()` → 0 si non imposé. Touche zoom (Z) du
  client : propriété `zoom_fov` (`set_properties{zoom_fov = 15}` ; 0 = désactivée), comme les jumelles de MTG.
- `core.get_player_window_information(name)` (clients 5.7+, peut être nil) : `size` (pixels), `max_formspec_size`,
  `real_gui_scaling`, `real_hud_scaling`.
- HUD : `player:hud_add{ type = "image"|"text"|…, position, scale, text, alignment, offset, z_index }` → id ;
  `hud_change(id, champ, valeur)`, `hud_remove(id)`. Le champ s'appelle **`type`** (`hud_elem_type` déprécié depuis 5.9).
  `hud_set_flags{ crosshair = false, wielditem = false }` pour un viseur ; tout remettre à la sortie du viseur
  (et à la déconnexion : `core.register_on_leaveplayer`).

## Lire le monde vite (rendu des photos)
| API | À savoir (mesuré en 5.15.1) |
|---|---|
| `core.get_node_raw(x, y, z)` | → `content_id, param1, param2, pos_ok` ; **~0,2 µs/nœud** ; `pos_ok == false` = zone non chargée (`CONTENT_IGNORE`). Base du parcours de rayons (skill photo-render). |
| `core.get_content_id(name)`, `core.get_name_from_content_id(id)`, `core.CONTENT_AIR`, `core.CONTENT_IGNORE` | tables par identifiant construites une fois après le chargement des mods |
| `core.raycast(p1, p2, objects, liquids, pointabilities)` | `pointed_thing` avec `intersection_point`, `intersection_normal`, `box_id` ; **35 à 95 µs par appel** (jusqu'à 420 machine chargée) : très bien pour un rayon (ce que vise le joueur), pas pour un par pixel (5 à 8 fois plus lent que le DDA Lua) |
| VoxelManip `read_from_map` | ±96 nœuds = 9 millions d'entrées = 0,8 à 1,5 s : interdit pour une photo |
| `core.get_node_light(pos, tod)` | 0–15 ou nil (non chargé) ; mesurer la lumière dans le nœud d'air **devant** la face |
| `core.get_natural_light(pos, tod)` / `core.get_artificial_light(param1)` | jour plein air : 15 ; minuit : 2 ; torche en boîte fermée : 11 et naturelle 0 |
| param1 d'un nœud `paramtype = "light"` | lumière en deux banques : jour = `param1 % 16`, nuit (= artificielle) = `math.floor(param1 / 16)` |
| `core.get_timeofday()` | 0 = minuit, 0,5 = midi ; `core.time_to_day_night_ratio(tod)` → 0..1 |

## Images : PNG, textures, médias dynamiques
- `core.encode_png(w, h, data, [compression])` : `data` = chaîne RGBA brute (w×h×4 octets, de haut en bas) ou table de
  ColorSpec ; PNG 32 bits. `core.colorspec_to_bytes(c)` → 4 octets RGBA. Pas de décodeur PNG dans l'API (à écrire en Lua).
- Texture `"[png:" .. core.encode_base64(png)` : la doc demande de l'éviter pour les grandes images. Mesuré : photo
  64×64 bruitée = 12,4 Ko de PNG = 16 500 caractères de texture → réservé aux toutes petites vignettes.
- `core.dynamic_add_media({ filename, filedata | filepath, to_player, ephemeral, client_cache }, callback(name))` → `true`
  si accepté (vérifié avec `filedata` en mémoire). `ephemeral` vaut **false par défaut** ; non éphémère sans `to_player`
  = envoyé à tous et aux joueurs qui arrivent ; **rien n'est persistant entre deux démarrages** (ré-ajouter au démarrage
  avec `callback = nil`) ; un même nom de fichier une seule fois, sauf `to_player` non éphémère vers plusieurs joueurs ;
  le callback indique quand le client l'a reçu (attendre avant d'afficher). `client_cache` existe depuis 5.14.

## Fichiers et sécurité des mods (vérifié, sécurité activée)
- Lecture permise dans les dossiers de **tous les mods** (`io.open(core.get_modpath("default") .. "/textures/x.png", "rb")`)
  et listage par `core.get_dir_list(chemin, est_dossier)` : c'est ce qui permet de calculer la couleur des nœuds.
- Écriture **seulement dans le monde** : `core.get_worldpath()`, `core.mkdir`, `core.safe_file_write(chemin, contenu)`.
  L'écriture dans un autre mod est refusée. Jamais `secure.trusted_mods` ni `request_insecure_environment`.
- Petites données : `core.get_mod_storage()` (`get/set_string/int/float`, `contains`, `get_keys`). Images : fichiers.

## Formspecs
- `core.show_formspec(nom, formname, fs)` ; `formspec_version[10]` disponible (5.13+), utiliser au moins 6.
- `core.register_on_player_receive_fields(function(player, formname, fields) … return true end)` : renvoyer true pour
  arrêter la chaîne. **Les champs viennent du client et sont hostiles** (n'importe quelle clé, valeur, longueur).
- Formspec de nœud : méta `formspec` + `on_receive_fields(pos, formname, fields, sender)` (formname "").
- Tout texte inséré : `core.formspec_escape`. Détail et style : skill formspec-ui.

## Nœuds muraux et entités (cadres)
- `paramtype2 = "wallmounted"` : param2 0 = y+, 1 = y−, 2 = x+, 3 = x−, 4 = z+, 5 = z− (côté où le nœud est
  accroché) ; 6 et 7 = y± tournés de 90° si `wallmounted_rotate_vertical = true` (cadres au sol ou au plafond).
  `core.wallmounted_to_dir`, `core.dir_to_wallmounted`. Aussi `"4dir"` et `"facedir"` (`core.facedir_to_dir`).
- Entité d'affichage : `core.register_entity(nom, { initial_properties = { visual = "upright_sprite"|"mesh"|"cube",
  visual_size, textures, pointable, static_save = false }, on_activate, get_staticdata })` ;
  `obj:set_properties{ textures = { … } }`. Restaurer depuis la méta du nœud avec
  `core.register_lbm{ name, nodenames, run_at_every_load = true, action = function(pos, node, dtime_s) … end }`.

## Divers
- Inventaires détachés : `core.create_detached_inventory(nom, { allow_move/put/take, on_move/put/take }, nom_joueur)`
  (le 3e argument limite la visibilité à un joueur) ; `core.remove_detached_inventory(nom)`.
- Sons : `core.sound_play(spec, { pos | object | to_player, gain, max_hear_distance, pitch }, ephemeral)` ;
  fichiers Ogg Vorbis **mono** pour être positionnels.
- Temps : `core.after(s, f, …)` ; `core.register_globalstep(function(dtime) … end)` (~20 fois/s) avec budget mesuré par
  `core.get_us_time()` ; jamais de parcours de tous les objets à chaque pas.
- Protection : `core.is_protected(pos, nom)` puis `core.record_protection_violation(pos, nom)`.
- Traduction : `local S = core.get_translator("passionphoto")`. `core.get_translated_string` appelé pendant
  `register_on_mods_loaded` met en cache une langue vide (vérifié dans chester) : différer au premier pas (`core.after(0)`).
- `pairs()` sur les registres : ordre non déterministe → trier avant de choisir ou de tronquer.
