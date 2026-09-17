---
tag: C36
statut: ouvert
gravité: coût
origine: notes/prd-parallelize-implement-epic §3.7 + C15 acte 2 / C17 du backlog v1
---

# C36 — passer le témoin sans passer par le contexte de l'orchestrateur

Aujourd'hui `kairos-implement` → `kairos-close` se relaient **par le contexte de
l'orchestrateur** : rapport structuré remonté, puis re-descendu. C17 dit que la survie de
l'orchestrateur au-delà de 3 stories n'est **pas mesurée** — 55 à 140 k jetons au pic.

**Ce qui a changé** : l'API expose désormais `SendMessage` (reprendre un agent déjà lancé,
contexte intact), la reprise nommée, `TaskStop`, et le handback explicite. Un closer pourrait
recevoir le témoin **directement** ; un correcteur sur `BLOCKED` être relancé sans
ré-instancier toute la story.

**L'arbitrage est déjà pris**, c'est D8.3 : *témoin < 15 k, artefact sur disque*. Seul le
mécanisme manquait. Il existe maintenant.

**Ce que ça débloque** : sans canal de retour, [C35](C35-vagues-paralleles-lanes-declarees.md)
recrée exactement le problème qu'il prétend résoudre — N stories en parallèle qui remontent
toutes dans le même contexte.
