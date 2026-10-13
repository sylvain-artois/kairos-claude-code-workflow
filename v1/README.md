# v1 — porter Kairos sur l'API des Skills

> **Cycle clos et gelé** le 2026-09-17, à la publication de la **1.14.0**. On ne modifie plus
> rien ici : ni le backlog, ni les décisions, ni le journal. Ce qui restait ouvert au §7 du
> backlog est reparti dans [`../v2/backlog/`](../v2/backlog/).
>
> Les répertoires `analysis_*/` que citent les entrées de journal ne sont plus sur le disque :
> ils sont dans `telemetry/analysis-v1.tar.gz` (968 Ko, hors git). La série complète des
> 16 captures — date, objet, version, coût — est en **§5 de [`BACKLOG.md`](BACKLOG.md)**.

Quatre fichiers, quatre métiers. **Le seul qu'on modifie au quotidien est `BACKLOG.md`.**

| Fichier | Question | Régime |
|---|---|---|
| [`BACKLOG.md`](BACKLOG.md) | *Que reste-t-il à faire, et qu'est-ce qui bloque la release ?* | **modifié en place** — état courant, et lui seul |
| [`DECISIONS.md`](DECISIONS.md) | *Qu'a-t-on déjà tranché ?* | **append-only** — on amende, on ne supprime pas |
| [`journal/`](journal/) | *Qu'a-t-on vu, et quand ?* | **un fichier par observation datée, jamais modifié** |
| [`plan-2026-08-29.md`](plan-2026-08-29.md) | *D'où vient tout ça ?* | **gelé** — valeur historique |

Les mesures brutes vivent à côté, dans
[`../telemetry/`](../telemetry/) : un répertoire `analysis_*/` par capture,
produit par `analyze_telemetry.py`, qui lit indifféremment un `.zip` ou un répertoire de
capture brute :

```sh
python3 telemetry/analyze_telemetry.py \
    ~/.client-1-telemetry/api-bodies/<session-uuid> \
    --out telemetry/analysis_<nom> --label <nom>
```

## Le rituel après une observation

Deux gestes. Jamais une couche de plus — c'est la leçon des 3 412 lignes de
`plan-refactoring-skills-api.md`, qui empilait douze mises à jour dont chacune déclarait primer
sur les précédentes (voir [D9](DECISIONS.md)).

1. Écrire `journal/{date}-{ce-qui-a-été-observé}.md`, avec en tête sa provenance (répertoire
   `analysis_*/` pour une capture, l'hôte et le mode de reproduction pour un retour de terrain),
   les versions concernées et l'objet.
2. Mettre à jour **les lignes touchées** de `BACKLOG.md` — y compris §4 (compteurs de
   prédictions ouvertes) et, s'il s'agit d'une capture, §5 (série de captures).

## Conventions d'identifiants

- **C{n}** — chantier. Une chose à construire. `C25` est le dernier attribué.
- **F{n}** — défaut mesuré. `F29` est le dernier attribué. *(F10 et F11 n'ont jamais été
  attribués.)*
- **D{n}** — décision tranchée. `D9` est la dernière.
- **V{n}** — sondage technique sur l'API des Skills. Journal des réponses dans
  [`plan-2026-08-29.md`](plan-2026-08-29.md) §6.2.

Un identifiant n'est **jamais réutilisé**, même après clôture — les entrées de journal les
citent, et une entrée de journal ne se réécrit pas.
