---
name: photo-render
description: Conception du rendu des photos de passionphoto — modèle d'appareil (œil, regard, FOV, objectifs), parcours de rayons en Lua avec core.get_node_raw, couleur des nœuds tirée des textures (décodage PNG en Lua, modificateurs, palettes), lumière jour/nuit, ciel, eau et verre, entités, émulation des pellicules et filtres, flash, stockage et affichage des photos (fichiers du monde, médias dynamiques), budget de performance, évaluation de la qualité. À utiliser pour tout travail sur la prise de vue, le rendu, le développement ou l'affichage des images.
---

# Rendu des photos

Le serveur ne voit pas l'écran du joueur : une photo est **recalculée côté serveur** à partir du monde, comme une
petite image en pixel art. Tout ce document vise une image fidèle, rapide et jamais bloquante.

## Mesures de référence (Luanti 5.15.1, scénarios `moteur:` et `mesure:`)
| Méthode | Coût | Verdict |
|---|---|---|
| `core.raycast` (un appel par pixel) | 35 à 95 µs/rayon, jusqu'à 420 machine chargée (frais fixes par appel) ; 128×128 = 0,6 à 1,5 s | à éviter pour le rendu |
| DDA Lua + `core.get_node_raw` | **7 à 12 µs/rayon** (54 nœuds visités, ~0,2 µs/nœud), 5 à 8 fois plus rapide, même nœud touché que raycast dans 99 % des cas | **méthode retenue** |
| DDA sur VoxelManip | 10 µs/rayon mais lecture ±96 nœuds = 0,8–1,5 s et 9 M d'entrées | interdit (ou petite zone) |
Budget indicatif : 128×128 = 16 384 rayons ≈ 0,1 à 0,2 s de parcours (+ ombrage) → étalé sur plusieurs pas serveur.
Les temps absolus varient d'un passage à l'autre (JIT, charge de la machine) : comparer des rapports sur plusieurs
passages (`make sim F=mesure`), jamais une valeur isolée.
La sonde du kit de test (`T.probe_render`) utilise `core.raycast` : elle sert à comparer, pas de modèle à copier.

## État de l'implémentation (26/11/2026, étape 2 en cours)
| Fichier | Rôle |
|---|---|
| `src/lib/png.lua` | décodeur PNG pur (inflate, filtres, types 0/2/3/4/6, 1–16 bits, tRNS, Adam7) ; tests : 23 images de `tools/gen_png_fixtures.py` + toutes les textures de minetest_game |
| `src/lib/texstring.lua` | analyse des chaînes de texture (`^`, groupes, modificateurs, échappements) ; tests unitaires |
| `src/render/textures.lua` | index des fichiers de tous les mods, décodage à la demande + cache, composition ; modificateurs : colorize, multiply, opacity, brighten, noalpha, invert, verticalframe, sheet, resize, combine |
| `src/render/nodes.lua` | fiche par `content_id` : forme, 6 faces (animations : 1re image), couleurs de tuile/nœud/palette, boîtes `fixed` tournées (facedir, 4dir) |
| `src/render/raymarch.lua` | `new_job(view, opts)` → `job.step(budget_µs)` / `job.result()` ; `render()` d'un bloc |
Mesuré : 6–18 µs/rayon texturé ; 256 px anticrénelé 2×2 = 1,6–4,9 s de calcul ; PNG 256 px = 55–85 Ko ; 20–30
textures décodées par scène (~1 ms chacune). Essayer : `/pptest_photo 256 2` (serveur de dev), scénarios `rendu:`.
Formes rendues : cube, liquide, verre, feuillage (allfaces, face opposée vue par les trous), plantes en croix, boîtes,
maillages approchés (boîte de sélection + couleur moyenne), rails, clôtures. **Limites connues** : pas encore d'entités
ni de joueurs ; rotation des textures des nœuds tournés ignorée ; eau qui coule rendue pleine ; cadres du verre
connecté visibles entre deux blocs ; pas d'occlusion ambiante (« smooth lighting » du client) ; torches murales et
panneaux (torchlike, signlike) ignorés. Les feuilles de minetest_game sont sombres par nature (texture #182016…).

## 1. Modèle d'appareil
- Œil = `get_pos()` + (0, `eye_height`, 0) + `eye_offset` 1re personne / 10 ; direction depuis `get_look_horizontal`
  (0 = +Z, croît vers −X) et `get_look_vertical` (> 0 = vers le bas) :
  `dir = (-sin(lacet)·cos(tangage), -sin(tangage), cos(lacet)·cos(tangage))`, `droite = (cos(lacet), 0, sin(lacet))`,
  `haut = dir × droite`. Pixel (i, j) : `u = ((i+0.5)/w·2−1)·tan(fov_h/2)`, `v = (1−(j+0.5)/h·2)·tan(fov_v/2)`.
- FOV vertical de base 72° (défaut du client) ; l'objectif et le zoom le réduisent (téléobjectif) ou l'élargissent
  (grand-angle) ; la même valeur pilote `set_fov` dans le viseur pour que la photo corresponde à ce que le joueur voit.
- Cadre carré par défaut (décision à confirmer dans docs/PLAN.md) ; résolution = constante de `src/config.lua`.

## 2. Parcours des rayons (DDA)
- Algorithme d'Amanatides-Woo sur la grille des nœuds (nœud = cube centré sur des coordonnées entières, bornes ±0,5),
  lecture par `core.get_node_raw(x, y, z)` ; `pos_ok == false` (non chargé) → le rayon s'arrête et prend le ciel.
- La face touchée vient de l'axe du dernier pas (normale ±X, ±Y, ±Z) ; la case précédente (air) donne la lumière.
- Table par `content_id` construite une fois (au premier pas après le chargement des mods) : classe de forme, opacité,
  couleur par face, émission de lumière, liquide/verre. Jamais de `core.registered_nodes[name]` dans la boucle chaude.
- Formes : `normal`/`allfaces`/`glasslike`/`liquid` = cube ; `airlike` = vide ; `plantlike` = couverture partielle
  (part opaque estimée de la texture, tramage déterministe) ; `nodebox` fixe (dalles, escaliers) = test des boîtes
  (AABB) quand la classe le demande ; `mesh`, `torchlike`, `signlike` = boîtes de sélection approchées.
- Distance maximale 96–128 nœuds, limitée de fait par la zone chargée autour des joueurs.

## 3. Couleur des nœuds (textures)
- Index des fichiers de textures : pour chaque mod (`core.get_modnames()`), `core.get_modpath(m) .. "/textures"`
  et ses sous-dossiers via `core.get_dir_list` ; nom de fichier → chemin. Lecture autorisée (vérifié, sécurité active).
- Tuiles : `def.tiles` (chaînes ou tables `{ name = … }`), ordre +Y, −Y, +X, −X, +Z, −Z (la dernière se répète) ;
  `overlay_tiles` par-dessus ; analyser la chaîne de texture : base `a.png^b.png` (superposition), `[colorize:#rrggbb:alpha`,
  `^[multiply:#rrggbb`, `[opacity`, sinon repli sur la base.
- Décodage PNG en Lua pur (`src/lib/png.lua`), **à la demande** quand un rayon rencontre le nœud pour la première
  fois (~1 ms par texture 16×16), cache en mémoire pour toute la session : aucun coût au démarrage. Couleur moyenne
  pondérée par l'alpha pour les formes approchées. La texture est échantillonnée au point d'impact (plus proche
  voisin, comme le client par défaut).
- Couleur de nœud : `def.color` multiplie ; palettes (`paramtype2 = "color"`, `colorwallmounted`, `colorfacedir`,
  `color4dir` + `palette`) : pixel de la palette à l'index tiré de param2 (nœuds teints d'unifieddyes, fréquents sur AIM).
- Repli si aucune texture lisible : heuristique par nom (comme la sonde), jamais d'erreur.

## 4. Lumière, ciel, eau
- Lumière : param1 de la case d'air devant la face : jour = `param1 % 16`, nuit = `floor(param1 / 16)` ; mélange comme
  le moteur : `l = (ratio·jour + (1−ratio)·nuit)` avec `ratio = core.time_to_day_night_ratio(heure)` ; courbe
  d'éclairement du client reconstituée (réglages `light_curve_*` par défaut) : cubique d'Hermite de pentes 0,04 et 0,
  plus une bosse gaussienne de 0,2 centrée sur 0,5 (σ 0,2) → niveau 10 ≈ 0,88, 5 ≈ 0,41, 2 ≈ 0,09. Une courbe plus
  sombre (essayée d'abord) noircit à tort ombres et scènes de nuit.
- Ombrage par face du client : +Y 1,0 ; −Y 0,447 ; ±X 0,671 ; ±Z 0,837.
- Coordonnées de texture par face (fractions fx, fy, fz dans le nœud ; ligne 0 de la texture en haut) :
  +Y (fx, 1−fz) ; −Y (fx, fz) ; +X (fz, 1−fy) ; −X (1−fz, 1−fy) ; +Z (1−fx, 1−fy) ; −Z (fx, 1−fy).
- Ciel selon l'heure (jour, aube, nuit) et la hauteur du rayon ; soleil/lune si le rayon vise leur direction ;
  brouillard vers la couleur d'horizon avec la distance. `player:get_sky(true)` donne les couleurs réelles du joueur.
- Eau et verre : on continue derrière en accumulant teinte et transmission (eau ~55 % opaque par nœud, verre ~15 %).

## 5. Entités et joueurs
Objets proches (`core.objects_inside_radius` autour de l'œil, rayon borné) : intersection rayon/boîte de collision ;
couleur moyenne de leur texture (`get_properties().textures`, ex. peau du joueur) via le même index de textures.
Indispensable pour les selfies et photos de groupe (retardateur).

## 6. Pellicule, réglages, filtres, flash
Chaîne en RVB linéaire, dans cet ordre : lumière → **exposition** (vitesse d'obturation = multiplicateur en IL) →
**filtre** (multiplication par la couleur du filtre ; R, V, B pour le procédé chromatique) → **pellicule** (N&B :
luminance pondérée 0,299/0,587/0,114 + courbe en S ; couleur : légère saturation/chaleur ; haute sensibilité : +1,5 IL
et grain plus fort) → **grain** déterministe (graine = identifiant de la photo) → 8 bits.
Flash : éclairage ajouté depuis l'appareil, décroissant avec la distance (portée ~12 nœuds), plus un effet visible
(éclair blanc dans le HUD ; lumière temporaire éventuelle). Tirage : papier (sépia/vieilli = teinte brune).

## 7. Stockage et affichage
- Identifiant de photo : compteur dans le mod storage, jamais réutilisé. Fiche : auteur, date (`os.time()`), pellicule,
  réglages, taille, version du format. Image : `<monde>/passionphoto/<id>.png` (`core.safe_file_write`).
- La méta des objets ne contient que l'identifiant (et un titre borné) : jamais l'image.
- Affichage par **médias dynamiques** (`core.dynamic_add_media{ filename = "passionphoto_p<id>.png", filedata = … }`),
  envoyés à la demande (`to_player`, non éphémère) et attendus via le callback avant d'ouvrir la visionneuse ; au
  démarrage, rien n'est persistant : ré-ajouter les photos exposées dans des cadres. `[png:` réservé aux vignettes ≤ 32×32.
- Taille disque : 64×64 ≈ 4–12 Ko par photo → quotas par joueur et commande d'administration (décision dans PLAN).

## 8. Performance
File de travaux de rendu dans un globalstep, **budget ≤ 5–8 ms par pas** mesuré par `core.get_us_time()`, un travail
par joueur, plafond global ; le joueur peut partir pendant le rendu (vérifier à chaque reprise). Le développement de la
pellicule (minuterie) masque naturellement ce délai.

## 9. Évaluer la qualité
Scénarios `rendu:` sur scènes de référence (`T.scenes.studio`, nuit avec torche, intérieur, sous l'eau, `-g v7`
paysage) : exporter chaque image (`ctx:save_png`), noter couleurs distinctes, luminance moyenne, durée ; comparer à la
version précédente et regarder les images (lien cliquable pour chaque PNG dans le compte rendu). Graines fixes :
même scène + même code = même image (une différence est donc un vrai changement).
