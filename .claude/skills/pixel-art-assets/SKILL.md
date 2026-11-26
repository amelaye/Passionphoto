---
name: pixel-art-assets
description: Textures et sons originaux de passionphoto — pixel art 16×16 au format .px compilé par tools/pixelart.py (aperçus agrandis à regarder), textures procédurales plus grandes (surimpression du viseur, cadres), sons synthétisés (déclencheur, avance du film, flash, cuve, pages) en Ogg Vorbis mono, licences et crédits. À utiliser pour créer ou retoucher une texture, un aperçu ou un son du mod.
---

# Textures et sons

## Originalité (impératif)
Rien de copié ni de décalqué depuis Minecraft, le mod Exposure, un autre jeu ou une marque d'appareils/pellicules,
même retouché. On s'inspire d'une ambiance (argentique, laiton, chambre noire), pas d'une image. Licence des médias :
CC BY-SA 4.0 (à confirmer par l'utilisatrice), crédits dans `LICENSE_MEDIA.txt`.

## Textures 16×16 : sources .px → PNG (outil repris de Cavepatate)
- Sources : `tools/textures_src/<nom>.px` (une ligne par rangée, 1 caractère = 1 pixel, palette en tête) ; sortie
  `textures/<nom>.png`. Format contrôlé par le hook à chaque écriture.
  ```
  # passionphoto_film_bw — original, CC BY-SA 4.0
  . = transparent
  a = #1c1a1a
  b = #3b3636
  ```
- Compiler : `make textures` (ou `python3 -I tools/pixelart.py build tools/textures_src/<nom>.px`).
- **Regarder** chaque résultat : `python3 -I tools/pixelart.py preview textures/<nom>.png --scale 16` (blocs : `--tile 3`
  pour vérifier les raccords) → `.cache/previews/` ; lire l'aperçu avec Read, itérer, puis donner à l'utilisatrice un
  lien cliquable par aperçu.
- Palette d'un modèle MTG : `python3 -I tools/pixelart.py palette .deps/games/minetest/mods/default/textures/default_wood.png`.
- Style : lumière venant du haut à gauche, 4 à 8 couleurs par objet, contour sombre pour les objets d'inventaire,
  fond transparent ; cohérent avec minetest_game.
- Noms : `passionphoto_<objet>[_<variante>].png` (`_top`, `_side`, `_front` pour les nœuds) ; vérifier que le code les
  référence (`grep -rn "passionphoto_" src init.lua`).

## Textures plus grandes ou procédurales
Surimpression du viseur (ex. 256×256 à centre transparent), guides de composition, cadres photo, bande de négatifs :
script Python pur dans `tools/` (sans PIL : réutiliser `png_write` de `tools/pixelart.py`), sortie dans `textures/`,
même vérification par aperçu. Un script = une famille de textures, relançable à l'identique.

## Sons
- Luanti ne lit que **Ogg Vorbis** ; **mono** obligatoire pour un son positionnel (un son stéréo s'entend au même volume
  partout). Noms : `passionphoto_<son>[.N].ogg` (variantes `.1`, `.2` tirées au hasard par le moteur).
- Sons prévus : déclencheur (clic sec), avance du film (cliquetis), chargement/éclair du flash, cuve (bulles), papier
  et pages d'album, pose d'un cadre.
- Synthèse en Python : sources `tools/sounds_src/*.py`. Il faut numpy et soundfile, **à installer seulement avec
  l'accord de l'utilisatrice**, dans un venv hors du dépôt (comme pour xocean) :
  `python3 -m venv "$TMPDIR/pp_venv" && "$TMPDIR/pp_venv/bin/pip" install -q numpy soundfile`.
  Volume cible : −18 dB RMS, rien d'agressif au-dessus de 6 kHz ; gain et distance d'écoute réglés dans le code.
- Aucun outil audio n'est installé sur le poste (pas de ffmpeg, sox, oggenc) : ne rien installer sans accord.

## Compte rendu
Liste des textures et sons créés ou modifiés, avec un lien cliquable vers chaque aperçu, les fichiers attendus par le
code mais encore absents, et la licence/les crédits ajoutés.
