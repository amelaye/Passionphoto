---
name: formspec-ui
description: Interfaces de passionphoto — thème « chambre noire », règles de sécurité des formulaires (champs hostiles, contexte revérifié, échappement), écrans du mod (accessoires de l'appareil, réglages, viseur HUD avec guides de composition, cuve de développement, agrandisseur avec négatifs, visionneuse de photo, album, cadre), affichage des photos par médias dynamiques, tests des formulaires en headless. À utiliser pour créer, modifier ou relire une formspec ou un HUD.
---

# Interfaces (formspecs et HUD)

## Thème « chambre noire » (constantes dans `src/ui/theme.lua` uniquement)
| Rôle | Couleur |
|---|---|
| fond | `#1b1416` (noir chaud), panneaux `#2a2023` |
| accent « lumière inactinique » | `#c0392b` (boutons actifs, sélection), survol `#e0503f` |
| texte | `#f2e6d0` (crème), secondaire `#b8a890` |
| laiton (appareil, cadres) | `#b08d57` |
| bande de film (négatifs) | `#0f0c0d` avec perforations `#3a3033` |
Pas de boutons gris par défaut : `style_type[button;bgcolor=…;textcolor=…]`, `bgcolor[…;true]`, `box[]`.
Pixel art net : images agrandies avec `[resize` ou par la formspec, jamais lissées.

## Règles impératives
1. **Champs hostiles** : un client peut envoyer n'importe quel champ, n'importe quand, avec n'importe quelle valeur.
   Les champs ne servent qu'à **naviguer et choisir** ; tout est revalidé côté serveur : index entier dans les bornes,
   identifiant de photo existant, texte tronqué (titres ≤ 40 caractères, légendes ≤ 120).
2. **Contexte revérifié à la réception** : le joueur tient-il toujours l'objet (même identifiant dans la méta) ? le nœud
   existe-t-il encore, à portée (≤ 10 nœuds), non protégé contre lui ? Sinon : ignorer et fermer.
3. **Échapper** tout texte inséré : `core.formspec_escape` (titres, légendes, noms de joueurs, descriptions).
4. Noms : formname `passionphoto:<écran>` ; champs préfixés `pp_` ; état par joueur côté serveur (table indexée par nom,
   nettoyée à `register_on_leaveplayer`), jamais dans un champ caché du formulaire.
5. `formspec_version[6]` au moins (coordonnées réelles, `style`, `scroll_container`) ; 10 disponible en 5.15.
6. Un retour de formulaire renvoie `true` seulement pour un formname du mod.

## Écrans prévus (docs/PLAN.md)
| Écran | Contenu |
|---|---|
| Accessoires de l'appareil | 4 emplacements (pellicule, objectif, filtre, flash) + inventaire du joueur ; inventaire détaché visible du seul joueur, réécrit dans la méta de l'appareil à chaque mouvement (aucune duplication possible) |
| Réglages (dans le viseur) | vitesse d'obturation, guide de composition, flash (non/oui/auto), retardateur ; vues restantes, focale |
| Viseur (HUD, pas une formspec) | cadre en surimpression (image à centre transparent), guides (tiers, centre, diagonale), indicateurs texte (vues, zoom) ; `hud_set_flags{ crosshair = false, wielditem = false }` ; tout est retiré à la sortie, à la mort, à la déconnexion |
| Cuve de développement | entrée pellicule exposée, chimie, sortie négatifs, barre de progression |
| Agrandisseur (tirage) | bande de négatifs défilante (vignettes), vue sélectionnée en grand, coût (papier, encres), boutons Tirer / Copies |
| Visionneuse de photo | image en grand, titre, auteur, date ; renommer si c'est sa photo |
| Album | double page, photo + légende par page, navigation, signature (titre + auteur, verrouille) |

## Afficher une photo
L'image d'une photo est un **média dynamique** (`passionphoto_p<id>.png`, skill photo-render) : l'envoyer au joueur,
attendre le callback, puis montrer la formspec avec `image[x,y;w,h;passionphoto_p<id>.png]`. En attendant : cadre vide
« développement… ». Jamais de `[png:` pour une photo entière (la doc le déconseille).

## Tester une interface en headless (skill headless-luanti)
```lua
local fs, formname = ctx:last_formspec(p)                     -- formspec montrée au faux joueur
ctx:check(T.formspec_has(fs, "image", "passionphoto_p"), "la photo est affichée")
ctx:submit(p, "passionphoto:enlarger", { pp_frame = "-3" })    -- champ forgé : doit être ignoré
ctx:submit(p, "passionphoto:enlarger", { pp_print = "1", pp_frame = "999999" })
```
Le HUD d'un faux joueur est dans `p._state.huds` (définitions complètes) et ses drapeaux dans `p:hud_get_flags()`.
L'aspect visuel réel (mise en page, lisibilité) ne se vérifie qu'avec un vrai client : le dire dans le compte rendu.
