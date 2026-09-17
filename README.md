# kairos-project-management

Le pilotage de Kairos : ce qu'on a mesuré, ce qu'on a tranché, ce qui reste à faire.
**Rien ici n'est distribué aux utilisateurs du plugin.**

## Pourquoi une branche orpheline

Kairos est son propre marketplace (`source: "./"` dans `.claude-plugin/marketplace.json`) :
tout ce qui est fusionné dans `main` part chez chaque utilisateur à sa prochaine mise à jour.
Et rien ne filtre en aval — le manifeste n'a ni champ `files` ni `ignore`, il n'existe pas de
`.claudeignore`, et `claude plugin package` n'existe pas. La seule frontière fiable est donc
la frontière git.

D'où cette branche `project-management` : **orpheline**, sans ancêtre commun avec `main`,
donc impossible à fusionner par accident. Elle est versionnée et poussée sur GitHub comme le
reste, mais l'installation du plugin ne voit que la branche par défaut.

## Disposition sur le disque

```
~/Documents/Sources/kairos-claude-code-workflow/     <- ouvrir CE dossier dans l'éditeur
    kairos-claude-code-workflow/                      <- le clone, branche main / feature/*
    kairos-project-management/                        <- ce worktree, branche project-management
```

Le worktree se remonte, sur une machine neuve, par :

```sh
git worktree add ../kairos-project-management project-management
```

## Ce qu'il y a dedans

| | |
|---|---|
| [`v1/`](v1/) | **Gelé.** Le cycle « porter Kairos sur l'API des Skills », d'août à la 1.14.0 du 2026-09-15 : backlog final, décisions, et 20 entrées de journal datées. |
| [`v2/`](v2/) | **En cours.** Le cycle ouvert. Une note par sujet dans [`v2/backlog/`](v2/backlog/), les arbitrages dans `v2/DECISIONS.md`, les observations datées dans `v2/journal/`. |
| [`telemetry/`](telemetry/) | L'outil de mesure : `analyze_telemetry.py` et les rapports rédigés. Les CSV ne sont pas versionnés. |

## La règle qui tient le tout

Une observation ne compte que si elle est datée et sourcée. Le journal dit **ce qu'on a vu et
quand**, `DECISIONS.md` dit **ce qu'on a tranché et pourquoi**, le backlog dit **ce qui reste**.
On n'empile pas de plan au-dessus : c'est la leçon des 3 412 lignes de
`plan-refactoring-skills-api.md`, qui superposait douze mises à jour dont chacune se déclarait
prioritaire sur les précédentes (v1, décision D9).
