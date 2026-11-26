---
name: release-deploy
description: Préparer une livraison de passionphoto (vérifications, version, archive, notes) et rédiger la procédure d'installation que l'administratrice applique sur le serveur Amelaye in Minerland (Luanti 5.15.1), sauvegarde des photos du monde et retour arrière. À utiliser avant de livrer une version ou pour rédiger les instructions d'installation.
---

# Livraison

## Avant de livrer (agent)
1. `make check` passe ; `make sim` **et** `make sim-min` passent (sorties citées dans le compte rendu).
2. Aucun `CORRIGÉ` en attente ; `docs/PLAN.md` à jour (étapes, bugs cochés, décisions).
3. Revue `luanti-reviewer` faite pour tout changement touchant formulaires, inventaires, fichiers, rendu ou cadres.
4. Version incrémentée **à deux endroits** : `mod.conf` (`version = x.y.z`) et `init.lua` (`passionphoto.version`) —
   le scénario « mod: version » vérifie qu'elles sont identiques. `depends`/`optional_depends` exacts,
   `min_minetest_version = 5.15`.
5. Traductions complètes (`make i18n-check`), textures et sons référencés présents, `LICENSE_MEDIA.txt` à jour.
6. `make dist` → `dist/passionphoto-<version>.zip` ; vérifier avec `unzip -l` : un dossier `passionphoto/` avec
   `mod.conf`, `init.lua`, `src/`, `textures/`, `sounds/`, `locale/`, licences — **pas** de `tools/`, `tests/`
   (ni le kit `passionphoto_test`), `docs/`, `.claude/`, `.deps/`, `.run/`, `.headless/`, `.px`.
7. `CHANGELOG.md` : changements visibles par les joueurs, recettes nouvelles ou modifiées, commandes d'administration.

## Installation en production (administratrice uniquement — jamais un agent)
Serveur : `/home/minetest/luanti5_15_1/mods/` (non accessible depuis le poste ; aucun ssh/scp sans accord écrit).
1. Sauvegarder l'ancien `mods/passionphoto` s'il existe, et le dossier `<monde>/passionphoto/` (les photos).
2. Copier le dossier `passionphoto/` de l'archive dans `mods/`.
3. `world.mt` : `load_mod_passionphoto = true`. Aucun réglage spécial : ni `secure.http_mods`, ni `trusted_mods`.
4. Redémarrer ; journal : ligne `[passionphoto] <version> chargé`, aucune erreur `[passionphoto]`.
5. En jeu : fabriquer un appareil, prendre une photo, développer, tirer, l'accrocher au mur, la mettre dans un album.

## Données et retour arrière
- Les photos vivent dans le monde : `<monde>/passionphoto/*.png` + l'index dans le mod storage. Les inclure dans les
  sauvegardes du monde ; surveiller la taille (`du -sh <monde>/passionphoto`).
- Retour arrière : remettre l'ancien dossier du mod et redémarrer. Le format des données est versionné : une version
  plus ancienne doit ignorer (sans les détruire) les champs qu'elle ne connaît pas.
