---
tag: C40
statut: clos le 2026-10-13 — arbre anonymisé (client-1, client-2), commits de nouveau permis ; publication effective à la prochaine graine orpheline
gravité: hygiène
origine: session 2026-09-17 — `gh api .../branches` au moment d'écrire la section CONTRIBUTING
---

# C40 — préparer la publication de la branche de suivi

## L'écart mesuré

`kairos-project-management/README.md` affirme que la branche est « versionnée et poussée sur
GitHub comme le reste ». Elle ne l'est pas : `gh api repos/.../branches` ne rend que
`main`, `feature/loop` et `refactor/skills-api-step-1`. Localement, `project-management` porte
**un commit** (`d5d05e2`, 2026-09-17), **sans upstream**, arbre propre. Tout le pilotage — la v1
gelée, les 22 notes de v2, l'outil de télémétrie — n'existe donc qu'en un exemplaire, sur un
disque.

Et le remède évident n'en est pas un : **`sylvain-artois/kairos-claude-code-workflow` est
public**. Sur 53 fichiers suivis, **27 citent les projets hôtes, 155 occurrences** :

| | |
|---|---|
| `client-1` | 103 |
| `afk` | 52 |
| `client-2` | 8 |

Quatre le portent jusque dans leur nom de fichier, dont
`telemetry/reports/analyse_cout_kairos_sur_client-1.md` — 29 Ko d'analyse de coûts sur un client
nommé.

## Pourquoi ça bloque la publication

La règle « pas de nom d'hôte dans les artefacts livrés » autorise ces noms **ici**, et elle
l'autorise pour une raison précise : cette branche n'est pas distribuée. Un push vers le remote
public annule l'hypothèse qui fonde l'exception. Un dépôt public est indexable et forkable, et
la branche reste dans l'historique après suppression.

La gravité ci-dessus est un pis-aller : l'échelle (bloquant / coût / hygiène) qualifie la
qualité de ce que le workflow produit, pas la confidentialité de ce qu'on expose. Rien à voir
avec un faux vert — mais c'est un **prérequis dur** à la publication, pas une dette de forme
qu'on peut laisser courir.

## Ce qui reste à trancher

1. **La nomenclature d'anonymisation.** À déterminer. Contrainte : elle doit être *stable*,
   parce que les entrées de journal se citent entre elles et citent les captures par leur hôte
   — un nom recyclé ou renommé deux fois rend fausses des références anciennes, exactement ce
   que la règle « on ne recycle pas un numéro » protège pour les tags.
2. **La tension avec la discipline du journal.** `v2/README.md` pose que le journal est « un
   fichier par observation datée, **jamais modifié** ». Anonymiser, c'est modifier une vingtaine
   d'entrées de v1. Soit on assume une exception nommée et datée, soit on publie un journal
   tronqué — à trancher explicitement, pas par accident.
3. **L'analyse de coûts client.** Renommer le fichier et substituer les noms ne suffit
   peut-être pas : les volumes, les dates et les périmètres décrits peuvent rester
   identifiants. Question distincte de celle de la nomenclature — publier, ou garder hors dépôt.
4. **La cible.** Un dépôt privé séparé règle le risque « un seul disque » sans rien exposer et
   sans anonymiser quoi que ce soit ; le remote public demande les trois points ci-dessus
   d'abord. Les deux ne s'excluent pas.

## Le geste — et ce que cette note ne bloque pas

**Versionner le pilotage est l'objectif, pas une variable d'ajustement : cette note ne retient
aucun commit.** L'arbitrage ci-dessus ne pèse pas sur l'historique courant, parce que publier
ne veut pas dire réécrire cette branche.

Le jour où la cible est tranchée, une publication se fabrique en semant une **nouvelle** branche
orpheline à partir d'un instantané anonymisé — `git checkout --orphan`, un commit, un push —
tandis que l'historique complet et nominatif reste local et privé. Sa longueur n'entre donc pas
dans le coût. Ce qui coûte, c'est la passe d'anonymisation sur l'arbre *courant*, une fois, quel
que soit le nombre de commits derrière elle.

Donc : on commite normalement, et les points 1 à 4 se tranchent au moment de publier.
