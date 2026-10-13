---
tag: C42
statut: ouvert
gravité: hygiène
origine: discussion du 2026-09-18, à l'ouverture du flux goal (C41)
---

# C42 — le nommage de la v2

Kairos n'a pas encore communiqué, et le domaine `kairos.ing` est posé. La v2 ajoute un second
flux ; c'est le moment de faire une passe de nommage avant que les mots ne se figent dans les
docs et les blogs.

## Tranché le 2026-09-18

- **Le plugin reste `kairos`, le marketplace reste `kairos`.** Le nom du plugin est le préfixe
  de chaque commande (`/kairos:pursue-goal`) : il doit être court. Le nom du marketplace est en
  kebab-case sans point (doc Claude Code) : `kairos.ing` n'est pas un identifiant valide,
  `kairos-ing` se lit mal. Le domaine vit sur le site et dans le README, pas dans la ligne
  d'installation.
- **`agentic-workflows` est un descripteur, pas un nom** — c'est une catégorie (« web-framework »),
  et `agentic` est un mot déjà usé, redondant dans le contexte Claude Code. Il va dans la
  *description* et le titre du site, où l'on cherche par catégorie. Fait : `plugin.json` et
  `marketplace.json` disent désormais « Two agentic workflows for Claude Code… story-driven
  delivery with gates… goal-driven pursuit against an executable yardstick ».

## À faire, après l'essai de C41

Le vrai chantier n'est pas le nom du plugin, c'est **le vocabulaire des deux flux**, à passer
en revue avec `docs/concepts.md` sous les yeux une fois que l'essai aura montré quels mots
servent vraiment :

| Mot actuel | Où | Question |
|---|---|---|
| `story` / `goal` | les deux flux | bons ; garder |
| `pursue-goal` | commande | tranché (C41), à confirmer à l'usage face à `implement-goal` |
| `contract` / `invariants` / `terrain` | `GOAL.md` | « contract » est chargé (sprint contract, review contract) — un seul sens ou un autre mot |
| `yardstick` / `measure.sh` | C41 | le mot anglais est juste mais rare ; `measure` tout court ? |
| `signal` / `alarm` | `pursue-goal` | clair ; vérifier que les messages ⛔ le disent |
| `round` | `pursue-goal` | face à « turn » (Claude Code) et « iteration » (Ralph) — garder `round` évite la collision |
| `generator` / `evaluator` | agents | vocabulaire d'Anthropic ; `judge` serait plus court que `evaluator` |
| « story-driven agile workflow » | README, tagline | à réécrire pour deux flux — le README ne documente encore que le premier |

Et deux noms de commandes historiques à regarder au passage : `sync-pm` et `setup-worktree-isolation`
sont les seuls qui ne se devinent pas.

## Règle

Un nom propre pour l'identifiant, un descripteur pour la découverte. On ne renomme pas une
commande installée chez des utilisateurs sans alias ; tant qu'il n'y en a pas, tout est
encore gratuit — c'est la fenêtre.
