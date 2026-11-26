# Passion Photo (`passionphoto`)

Mod Luanti de photographie argentique pour le serveur *Amelaye in Minerland* : appareil photo et viseur, pellicules,
accessoires (objectif, filtre, flash), développement, tirage, album et cadres muraux. Mécaniques inspirées du mod
Minecraft Exposure ; noms, textures, sons et code originaux.

**État : en développement** (outillage en place, rendu texturé des photos en cours ; pas encore d'objets jouables).
Feuille de route et décisions : `docs/PLAN.md`.

- Luanti 5.15.1 ou plus récent, jeu minetest_game (dépendance : `default`).
- Installation : copier le dossier `passionphoto/` de l'archive (`make dist`) dans `mods/`, puis
  `load_mod_passionphoto = true` dans `world.mt`. Aucun réglage spécial.
- Les photos sont enregistrées dans le dossier du monde (`<monde>/passionphoto/`) : à inclure dans les sauvegardes.

Développement : `CLAUDE.md` et `docs/TOOLING.md` (`make check`, `make sim`, `make server-start`).

Licences : code MIT (`LICENSE`) ; médias CC BY-SA 4.0 (proposé, `LICENSE_MEDIA.txt` à créer avec les premières textures).
