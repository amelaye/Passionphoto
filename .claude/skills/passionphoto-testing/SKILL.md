---
name: passionphoto-testing
description: Stratégie de test de passionphoto — tests unitaires LuaJIT de la logique pure, scénarios dans le vrai moteur headless, bugs connus, couverture attendue par fonctionnalité (appareil, pellicule, développement, tirage, photo, album, cadres, rendu, sécurité, performance), format du compte rendu. À utiliser pour ajouter un test, reproduire un bug, valider une correction ou rédiger un compte rendu de test.
---

# Tests de passionphoto

## Deux niveaux, jamais confondus
1. **Unitaires** (`tests/unit/test_*.lua`, `make test`, LuaJIT seul) : la logique **pure** de `src/lib/` (décodage PNG,
   couleurs, courbes de pellicule, sérialisation, pagination de l'album, quotas…). Rapides. Ils ne prouvent pas le moteur.
   ```lua
   local T = ...
   local film = dofile(T.root .. "/src/lib/film.lua")
   T.describe("pellicule", function()
   	T.it("16 poses par rouleau", function() T.eq(film.new("bw").frames_left, 16) end)
   end)
   ```
   Assertions : `T.eq`, `T.near`, `T.ok`, `T.contains`, `T.raises`, `T.deep_eq`. Un module pur n'utilise pas `core`
   au chargement (dépendances passées en paramètres) : c'est ce qui le rend testable ici.
   Données de référence produites par un outil **indépendant** du code testé : ex. `tools/gen_png_fixtures.py` encode
   en Python (zlib) des PNG dont le résultat attendu est connu par construction (`tests/unit/fixtures/png/`).
2. **Scénarios** (`tests/passionphoto_test/scenarios/`, `make sim`) : vrai serveur Luanti 5.15.1 (skill headless-luanti).
   **Seul ce niveau autorise à écrire « testé dans le moteur ».** Toute fonctionnalité visible par un joueur y a son scénario.
Ne jamais annoncer un résultat qui n'a pas tourné : citer la sortie réelle (`BILAN …`, chiffres).

## Bugs connus
Numérotation `Bxx` = celle de `docs/PLAN.md` (section Bugs). Le test décrit le comportement **correct** :
- scénario : `T.known_bug("B07 cadre: la photo reste affichée après rechargement du bloc", fn)` → `CONNU` tant qu'il
  échoue (non bloquant), `CORRIGÉ` dès qu'il passe (bloquant) → le passer en `T.register` et cocher B07 ;
- unitaire : `T.known_bug("B07 …", fn)` (raison visible avec `PP_TEST_VERBOSE=1`).
Vérifier qu'un bug connu échoue pour la bonne raison : `tools/headless/run.sh -f B07 -o passionphoto_test.verbose=true`.

## Couverture attendue (à compléter au fil des étapes de docs/PLAN.md)
- **Chargement** (`mod:`) : tout ce qui est enregistré existe (objets, nœuds, entités, recettes, commandes, LBM) ;
  textures et sons référencés présents ; avec et sans mods facultatifs (`make sim` et `make sim-min`).
- **Appareil** : viseur ouvert/fermé (HUD ajouté puis retiré, drapeaux remis, FOV remis — aussi à la déconnexion et à la
  mort), zoom borné par l'objectif, déclenchement sans pellicule / pellicule pleine / pellicule exposée, une pose =
  une vue, réglages (vitesse, guides, flash, retardateur) bornés, accessoires mis et retirés sans duplication.
- **Pellicule** : types (N&B, couleur, haute sensibilité), compteur de poses dans la méta et `count_meta`, une pellicule
  ne peut pas être développée deux fois, renommage borné.
- **Développement** : entrées refusées (mauvais objet, mauvais produit chimique), minuterie, résultat, conditions
  (obscurité si retenue), protection, pas de perte ni de duplication si le nœud est creusé pendant le traitement.
- **Tirage** : choix d'une vue valide uniquement (index hors bornes, champs forgés), coût en papier/encres, copies,
  photo vieillie, pile de photos.
- **Photo** : visionneuse (formspec), titre borné et échappé, auteur et date, envoi du média avant affichage.
- **Album** : 16 pages, légendes bornées et échappées, signature verrouillant l'album, photo qu'on retire = photo rendue.
- **Cadres** : pose sur mur, sol, plafond ; tailles 1×1 à 3×3 ; protection ; entité recréée après rechargement (LBM) ;
  pas de doublon d'entité ; creuser rend le cadre ET la photo.
- **Rendu** (`rendu:`) : scènes de référence (studio, nuit, intérieur éclairé, sous l'eau, paysage v7) exportées en PNG ;
  métriques (couleurs distinctes, luminance moyenne, durée) comparées aux valeurs de référence notées dans le scénario.
- **Sécurité** (`securite:`) : champs de formulaire forgés (index négatifs, NaN, 10 000 caractères, `]` et `;`),
  identifiants de photo inconnus ou d'un autre joueur, objets retirés de la main avant la réponse, joueur parti avant la
  fin d'un rendu, quotas de photos (disque), spam de déclenchements.
- **Performance** (`perf:`, `mesure:`) : temps de rendu par photo et par pas serveur (budget), nombre de rayons,
  plusieurs joueurs qui déclenchent en même temps.

## Compte rendu de test
Dire exactement ce qui a tourné (lint ? unitaires ? scénarios, avec quel filtre, quel mapgen, avec ou sans mods ?),
recopier `BILAN` et les mesures utiles, lister les échecs avec fichier:ligne, et donner **un lien markdown cliquable par
image produite** (chemin absolu, ex. `[jour_64](/Users/amelaye/Documents/Passionphoto/.headless/runs/…/photos/x.png)`).
Finir par ce qui reste à vérifier à la main avec un vrai client (affichage, sons, confort du viseur).
