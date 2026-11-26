# Passion Photo — plan, conception et décisions

Document vivant. Légende : ✅ décidé · 🟡 proposé (à valider par Amelaye) · ❓ question ouverte.
Mis à jour par l'agent principal et l'agent `game-designer` ; une décision non validée reste 🟡.

## 1. Vision

La photographie argentique sur *Amelaye in Minerland* : cadrer dans un viseur, déclencher, **développer** la pellicule,
**tirer** les photos, puis les ranger dans un **album** ou les accrocher **au mur**. Sur un serveur pacifique et
semi-roleplay, la photo sert à raconter : lieux, constructions, événements, portraits.
Mécaniques **inspirées de près d'Exposure** (Minecraft) ; noms, visuels, sons et code **originaux**.

```
 fabriquer l'appareil ─► charger une pellicule ─► viser (zoom, réglages, accessoires) ─► déclencher (16 poses)
        ─► pellicule exposée ─► DÉVELOPPER (cuve + chimie) ─► négatifs ─► TIRER (agrandisseur : papier + encres)
        ─► photos ─► album · cadre au mur · pile · copie · photo vieillie
```

## 2. Exposure → passionphoto

| Exposure | passionphoto | |
|---|---|---|
| Viseur, zoom à la molette | viseur en HUD + FOV ; zoom par la touche zoom du client (`zoom_fov` réglé par l'objectif) et par les réglages — la molette n'est pas visible du serveur | 🟡 |
| Réglages : vitesse d'obturation, guides de composition, flash non/oui/auto, retardateur | identiques (vitesse = exposition en IL) | 🟡 |
| Selfie (F5, vue de face) | `player:set_camera{ mode = "third_front" }` (clients 5.12+) pendant la visée | 🟡 |
| 4 accessoires : pellicule, flash, objectif (longue-vue), filtre (vitre teintée) | pellicule ; flash ; objectifs standard / grand-angle / téléobjectif (jumelles de MTG) ; filtres en verre teinté | 🟡 |
| Pellicules N&B, couleur, haute sensibilité (plus claires, bruitées), 16 poses | identiques | 🟡 |
| Développement = fabrication (flacon d'eau ; potions pour la couleur) | **cuve de développement** (nœud) + chimie + minuterie ; option chambre noire | ❓ Q1, Q2 |
| Lightroom : papier + teinture noire (N&B) ou + cyan, magenta, jaune ; aperçu des négatifs ; automatisation redstone | **agrandisseur** : papier + encres, aperçu des négatifs, copies ; automatisation mesecons plus tard | 🟡 |
| Procédé chromatique (vues R/V/B combinées) | plus tard | 🟡 |
| Photo vieillie (teinture marron) | photo + colorant marron | 🟡 |
| Piles de photos | oui | 🟡 |
| Album : 16 pages, photo + légende, signature, pupitre | oui (pas de pupitre dans minetest_game) | 🟡 |
| Cadres 1×1, 2×2, 3×3 ; variante verre (sans bordure) ; lumineux ; sol et plafond | oui | ❓ Q6 |
| Appareil instantané | plus tard (pellicule instantanée = tirage immédiat) | 🟡 |
| Projecteur interplanaire (image du PC du joueur) | **non** : le serveur n'a pas accès aux fichiers du joueur | ✅ |

## 3. Contenu proposé 🟡

Recettes à préciser par l'agent `game-designer`, avec des objets **vérifiés** dans les sources (minetest_game,
`../Awards/.audit_src`).

| Objet / nœud | Rôle |
|---|---|
| Appareil photo `passionphoto:camera` | viseur (clic droit), déclenchement (clic gauche dans le viseur), réglages (s'accroupir dans le viseur), accessoires (s'accroupir + clic droit hors viseur) ; vues restantes affichées sur l'objet (`count_meta`) |
| Pellicules : N&B, couleur, N&B haute sensibilité, couleur haute sensibilité | 16 poses ; états neuve → en cours → exposée ; renommable |
| Objectifs : standard (72°), grand-angle (~100°), téléobjectif (zoom ×2 à ×4, avec les jumelles de MTG) | FOV de la photo et du viseur |
| Filtres : verre teinté par colorant ; rouge, vert, bleu | teinte de la photo ; procédé chromatique plus tard |
| Flash | éclaire la scène proche (~12 nœuds) ; modes non / oui / auto |
| Chimie : révélateur, fixateur (N&B) ; kit couleur | consommés par la cuve |
| Cuve de développement (nœud) | pellicule exposée + chimie → négatifs après une minuterie (30 s N&B, 60 s couleur) |
| Agrandisseur (nœud) | négatifs + papier photo + encres → photos ; choix de la vue, copies |
| Papier photo, encres (noire, cyan, magenta, jaune) | consommables du tirage |
| Photo `passionphoto:photo` | visionneuse ; titre, auteur, date ; vignette d'inventaire ; vieillie ; piles |
| Album | 16 pages, photo + légende, signature (verrouille) |
| Cadres (petit 1×1, moyen 2×2, grand 3×3 ; bois, verre, lumineux) | nœud mural + entité qui affiche la photo |
| Plus tard : trépied + retardateur (selfies, photos de groupe), appareil instantané, procédé chromatique, automatisation mesecons de l'agrandisseur |

## 4. Faisabilité vérifiée dans le moteur ✅ (Luanti 5.15.1 headless, 26/11/2026)

Scénarios `moteur:` et `mesure:` (`make sim`), refaits à chaque changement de moteur.

| Point | Résultat |
|---|---|
| API nécessaires (encode_png, médias dynamiques, get_node_raw, lumière, fichiers, HUD…) | toutes présentes |
| `core.encode_png` + `[png:` | OK ; photo 64×64 bruitée = 12,4 Ko de PNG = 16 500 caractères de texture → `[png:` seulement pour les vignettes |
| Lecture des textures des autres mods (sécurité activée) | OK (241 textures dans `default`) ; écriture hors du monde refusée |
| `core.raycast` : normale de la face, liquides | OK |
| Lumière | plein air midi 15, minuit 2 ; torche en boîte fermée 11, naturelle 0 |
| `dynamic_add_media{ filename, filedata }` | accepté (true) |
| Coût d'un rayon `core.raycast` | 35 à 95 µs (jusqu'à 420 µs machine chargée), surtout des frais fixes par appel → 128×128 ≈ 0,6 à 1,5 s |
| Coût d'un rayon DDA Lua + `core.get_node_raw` | **7 à 12 µs** (54 nœuds visités, ~0,2 µs/nœud), 5 à 8 fois moins que raycast, même nœud touché dans 99 % des cas → 128×128 ≈ 0,1 à 0,2 s de parcours |
| Lecture VoxelManip ±96 nœuds | 0,8 à 1,5 s, 9 M d'entrées : à proscrire |
| Décodeur PNG en Lua (`src/lib/png.lua`) | 23 images de test (tous types, profondeurs, palettes, Adam7, blocs deflate) + toutes les textures de minetest_game décodées (tests unitaires) |
| Rendu texturé du mod (`src/render/`) | 128 px : 0,2–0,4 s ; 256 px : 0,5–1,2 s ; 256 px anticrénelé 2×2 : 1,6–4,9 s de calcul (6–18 µs/rayon selon la scène) ; PNG 256 px : 55–85 Ko ; 20–30 textures décodées par scène (~25 ms) |
Les temps absolus varient d'un passage à l'autre (JIT, charge de la machine) : relancer `make sim F=mesure` plusieurs
fois et comparer des rapports. Images de la sonde (scène studio jour/nuit, paysage v7) : `.headless/runs/<id>/photos/`.

## 5. Architecture technique 🟡

Voir `CLAUDE.md` §4 et le skill photo-render. Points clés : logique pure dans `src/lib/` (testée sous LuaJIT) ; rendu
dans `src/render/` (palette par `content_id` calculée depuis les textures, parcours de rayons, file de rendus avec
budget par pas) ; photos en fichiers dans `<monde>/passionphoto/`, index dans le mod storage, objets ne portant qu'un
identifiant ; affichage par médias dynamiques envoyés à la demande.

## 6. Étapes

| # | Étape | Agents | État |
|---|---|---|---|
| 0 | Outillage : CLAUDE.md, 7 skills, 6 agents, hook, tests unitaires, runner de scénarios headless 5.15.1 avec faux joueurs, serveur de dev piloté sans client, sonde et mesures de faisabilité | — | ✅ 26/11/2026 |
| 1 | Socle : `config`, `storage` (identifiants, fichiers, index, quotas), objet photo + visionneuse, médias dynamiques ; commande d'admin de test qui crée une photo depuis une position | luanti-developer, qa-tester | à faire |
| 2 | Rendu v1 : palette depuis les textures (décodeur PNG Lua), DDA, lumière, ciel, eau/verre, file de rendus ; scénarios `rendu:` sur scènes de référence | render-engineer | **en cours** — fait le 26/11 : décodeur PNG, textures échantillonnées au point d'impact, courbe d'éclairement du client, transparences (verre, eau, feuillage), plantes en croix, boîtes tournées, ciel/soleil/brouillard, travail étalable par pas. Reste : entités et joueurs, file de rendus en production, rotation des textures (facedir), hauteur de l'eau qui coule, palettes vérifiées (unifieddyes) |
| 3 | Appareil : viseur (HUD, guides, FOV), déclenchement, son, vues restantes, accessoires (formspec), réglages | luanti-developer, pixel-artist | à faire |
| 4 | Pellicules et développement : types, états, chimie, cuve (minuterie, protection, sans duplication) | luanti-developer, game-designer | à faire |
| 5 | Tirage : agrandisseur (négatifs, papier, encres, copies), photo vieillie, piles | luanti-developer | à faire |
| 6 | Album : pages, légendes, signature | luanti-developer | à faire |
| 7 | Cadres : 1×1 à 3×3, verre, lumineux, sol/plafond, entités restaurées (LBM), protection | luanti-developer, qa-tester | à faire |
| 8 | Accessoires : objectifs, filtres, flash, haute sensibilité ; selfie | render-engineer, luanti-developer | à faire |
| 9 | Finitions : textures et sons, traduction anglaise, quotas et commandes d'admin, revue, livraison | pixel-artist, luanti-reviewer | à faire |
| — | Plus tard : trépied + retardateur, appareil instantané, procédé chromatique, mesecons | | |

## 7. Décisions

| # | Date | Décision |
|---|---|---|
| D1 | 26/11/2026 | ✅ Outillage « comme d'hab » (chester, chair_lift) : skills, agents, hook de contrôle, tests unitaires LuaJIT + scénarios dans un vrai serveur headless 5.15.1 avec faux joueurs, serveur de dev piloté par fichiers. Jamais de fenêtre Luanti. |
| D2 | 26/11/2026 | ✅ Un seul mod `passionphoto` à la racine du dépôt ; outils, tests, docs et configuration Claude hors de l'archive. |
| D3 | 26/11/2026 | ✅ Rendu par parcours de grille (DDA) en Lua avec `core.get_node_raw` : 7–12 µs/rayon contre 35–95 µs pour `core.raycast` (5 à 8 fois plus rapide, mesuré sur 4 passages), sans allocation, avec la lumière (param1) et les identifiants de contenu directement. |
| D4 | 26/11/2026 | 🟡 Affichage des photos par médias dynamiques (un PNG par photo) ; `[png:` réservé aux vignettes ≤ 32×32. |
| D5 | 26/11/2026 | 🟡 Textes écrits en français, traduits en anglais (`locale/passionphoto.en.tr`), comme chester. |
| D6 | 26/11/2026 | 🟡 Licences : code MIT (comme chester), médias CC BY-SA 4.0. |
| D7 | 26/11/2026 | 🟡 Pas de réglages serveur (`settingtypes.txt`) : constantes dans `src/config.lua`, sauf demande. |
| D8 | 26/11/2026 | ✅ Photos **texturées** (retour d'Amelaye : « trop pixellisé » sur les sondes en aplats 64–128 px) : texture du nœud échantillonnée au point d'impact (décodeur PNG Lua), courbe d'éclairement reconstituée d'après le client ; anticrénelage 2×2 possible. Le rendu se fait en tâche de fond pendant que la pellicule attend d'être développée. |

## 8. Questions ouvertes pour Amelaye ❓

1. **Développement** : cuve + chimie + minuterie (proposé, plus « roleplay ») ou simple fabrication comme Exposure ?
2. **Chambre noire** : la cuve ne fonctionne-t-elle que dans l'obscurité (lumière ≤ 3) ?
3. **Résolution** des photos (64–128 px jugé « trop pixellisé ») : **256 px anticrénelé** (proposé : 1,6–4,9 s de calcul
   étalées en tâche de fond, 55–85 Ko par photo) ou 256 px sans anticrénelage (0,5–1,2 s, bords plus crénelés) ?
4. **Quotas** : combien de photos par joueur (ex. 200), et une commande d'admin pour en accorder plus ?
5. **Coût** : appareil accessible dès le début (fer, verre) ou objet de milieu de partie (mese) ?
6. **Cadres** : tailles fixes par objet (petit, moyen, grand) ou remplissage automatique de la place libre comme Exposure ?
7. **Automatisation** de l'agrandisseur par mesecons (présent sur le serveur) : utile ?

## 9. Bugs

| # | Description (fichier:ligne, reproduction) | Test | État |
|---|---|---|---|
| — | aucun pour l'instant | | |
