---
tag: F31
statut: en cours — implémenté sur feature/pursue-goals (f3a0369), à valider sur un run réel
gravité: coût
origine: capture 20261013a — run pursue-goal profile-field-model sur Client-1,
  telemetry/reports/20261013-pursue-goal-profile-field-model.md §1 et §5
---

# F31 — `/kairos:create-goal` livre des sondes jamais éprouvées contre les données réelles

## L'écart mesuré

La sonde C2 du goal `profile-field-model` mappait les catégories numériques de main vers
les slugs cibles avec `num_to_slug.get(str(e.get("categorie")))`. Sur main, 12 champs
portent la sous-catégorie `"2.1"` — la sonde les mappe sur `None`, donc **C2 ne pouvait
jamais passer**, quel que soit le code produit. Un seul accès aux données de main
(`git show main:data/…` + `Counter`) suffisait à le voir : c'est précisément la
vérification que le générateur du round 1 a faite pour diagnostiquer le défaut.

La chaîne de sécurité a fonctionné — et c'est ça qui coûte :

1. le générateur signale le défaut au lieu de maquiller (bien) ;
2. le classifieur de permissions refuse que l'orchestrateur édite `measure.sh`,
   fichier sous verrou (bien) ;
3. l'orchestrateur continue les autres lots puis s'arrête proprement à 7/8 (bien) ;
4. **la run attend l'owner 6 h 39** pour un correctif d'une ligne (c'est le prix).

## Pourquoi c'est important

Le verrou sur `measure.sh` est la bonne règle : un mètre qu'on peut tordre en cours de run
ne mesure plus rien. Mais il a une conséquence directe : **toute erreur de sonde devient un
arrêt owner**. La qualité des sondes à la création n'est donc pas un confort, c'est la
variable qui décide si une run de nuit va au bout. Chaque sonde fausse convertit le verrou
— une protection — en frein à l'autonomie.

## Le geste

Dans `skills/create-goal/SKILL.md`, avant de proposer le goal à l'approbation :

- **Exécuter `measure.sh` complet sur l'arbre de départ** et exiger de chaque ligne un
  FAIL *motivé* (l'évidence attendue : « fichier absent », « route absente ») — jamais un
  FAIL d'erreur (`rc` d'exception, KeyError, mapping vide). Une sonde qui plante ou dont
  l'évidence ne correspond pas à l'état réel de main est à réécrire avant approbation.
- Pour toute sonde qui **compare à main** (migration, renommage, invariant de
  non-régression) : la moitié « lecture de main » doit être éprouvée seule — elle doit
  produire un résultat plein et plausible sur main (compteurs non vides, aucun `None`
  inattendu), pas seulement ne pas planter.
- Écrire dans `GOAL.md` que la mesure 0 fait partie de l'approbation : l'owner approuve un
  contrat **et** la preuve que son mètre lit correctement l'existant.

`pursue-goal` fait déjà la mesure 0, mais trop tard : le verrou est pris au même moment.
C'est à `create-goal`, avant verrou, que la sonde se répare à coût nul.
