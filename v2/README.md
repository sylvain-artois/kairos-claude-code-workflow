# v2 — le cycle ouvert

Ouvert le 2026-09-17, au lendemain de la **1.14.0**.

Même discipline qu'en [v1](../v1/), moins le plan. Trois régimes, et un seul change au
quotidien.

| | Question | Régime |
|---|---|---|
| [`backlog/`](backlog/) | *Que reste-t-il à faire ?* | **une note par sujet**, modifiée en place |
| [`DECISIONS.md`](DECISIONS.md) | *Qu'a-t-on déjà tranché ?* | **append-only** — on amende, on ne supprime pas |
| [`journal/`](journal/) | *Qu'a-t-on vu, et quand ?* | **un fichier par observation datée, jamais modifié** |

**Pas de `plan.md`.** C'est la seule différence de forme avec la v1, et elle est délibérée :
le plan de la v1 avait atteint 3 412 lignes en douze mises à jour dont chacune se déclarait
prioritaire sur les précédentes (D9). Le backlog porte l'état courant, et lui seul.

## Ce qui change de la v1 : une note par sujet

En v1, le backlog était **un** fichier de 231 lignes où chaque sujet tenait sur une ligne de
tableau, forcément dense — et qui a fini par frôler l'illisible. Ici chaque sujet a son
fichier, ce qui laisse la place d'écrire la mesure, le mode d'échec et le geste envisagé
sans les comprimer.

```
backlog/{tag}-{slug}.md
```

Chaque note porte un en-tête minimal :

```markdown
---
tag: C26            # C = chantier (à construire) · F = défaut mesuré
statut: ouvert      # ouvert | en cours | tranché | clos | abandonné
gravité: coût       # bloquant | coût | hygiène
origine: v1 §7      # d'où ça vient : capture Mn, retour de terrain, idée
---
```

Les identifiants **continuent la numérotation de la v1** : `C25` et `F29` étaient les derniers
attribués, donc la v2 commence à `C26` et `F30`. On ne recycle pas un numéro — une référence
dans une vieille entrée de journal doit rester juste.

## Les trois gravités

| | |
|---|---|
| **🔴 bloquant** | un **faux vert** : un gate qui certifie ce qu'il n'a pas vu, une perte silencieuse, un reçu qui atteste une substitution. Ne peut pas partir dans une release stable. |
| **🟠 coût** | c'est cher, lent ou inélégant, mais le résultat est juste. Peut partir tel quel. |
| **⚪ hygiène** | dette de forme, doc, ou nommage. |

## Le rituel après une observation

Deux gestes, jamais une couche de plus.

1. Écrire `journal/{date}-{ce-qui-a-été-observé}.md`, avec en tête sa provenance (le répertoire
   `analysis_*/` pour une capture, l'hôte et le mode de reproduction pour un retour de terrain),
   les versions concernées et l'objet.
2. Mettre à jour **les notes de `backlog/` que ça touche** — et elles seules.

La mesure elle-même se prend avec [`../telemetry/`](../telemetry/), dont le README dit comment.
