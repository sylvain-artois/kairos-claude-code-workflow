<!-- Entrée de journal — 2026-09-08, soir. Ce n'est PAS une capture de télémétrie :
     c'est un retour de terrain depuis un autre hôte, plus une reproduction locale.
     État courant des chantiers : ../BACKLOG.md — décisions : ../DECISIONS.md -->

**Origine** : retour d'un agent travaillant sur **Wispra** (architecture atypique, hôte
**macOS**), transmis sous forme d'une note de deux phrases proposant un correctif.
**Reproduction** : locale, sous `bash` 5.x et `dash`, sur `refactor/skills-api-step-1`.
**Statut** : **défaut confirmé** (F19) ; **cause zsh non confirmée** — sonde à lancer.
**Aucun code modifié.**

---

# Retour de terrain Wispra — les blocs pré-exec confondent quatre échecs avec un résultat vide

## La note reçue, verbatim

> Option B — rendre le pré-exec robuste dans kairos-claude-code-workflow (branche
> refactor/skills-api-step-1, tree propre) : un fallback `PM=${PM:-project_management}` et un
> `setopt +o nomatch` / `2>/dev/null || true`. Ça corrige les sept skills d'un coup, pour tous
> les repos. C'est un autre dépôt que celui de l'épic.

Elle donne un **remède sans symptôme** : on ne sait pas ce qui a été observé sur le Mac. C'est
la première chose à retenir de cet épisode — un retour d'agent qui saute au correctif fait
perdre le fait, et le fait est ici plus intéressant que le correctif.

## F19 — le défaut réel, reproduit

`PM` est résolu dans neuf blocs pré-exec par un `grep` sur `./spec.md` avec `2>/dev/null`, puis
utilisé sans être vérifié. **Quatre situations distinctes retombent sur la même chaîne**, sous
`bash` comme sous `dash` :

| Situation | Sortie injectée dans le contexte du modèle |
|---|---|
| `spec.md` absent | `(no open story files found)` |
| `spec.md` présent, champ `project_management_dir` absent | `(no open story files found)` |
| champ présent, répertoire inexistant | `(no open story files found)` |
| **nominal — l'épic n'a réellement plus de story ouverte** | `(no open story files found)` |

C'est **la classe de défaut contre laquelle ce dépôt a commité deux commits plus tôt** —
`ad2d8bc`, *« a filter that swallows a dirty tree is an error, not an empty scope »* — et le
motif exact de C16 / F13 : **un vide non distingué d'une erreur est un faux vert.**

Le dépôt porte déjà le bon idiome, à trois lignes de là — `sync-pm` (bloc de la ligne 43) :

```sh
echo "$k: ${v:-<unset>}"
```

On **nomme** le cas non résolu ; on ne lui substitue pas une valeur.

## Le décompte exact, qui n'est pas celui de la note

« Les sept skills » mélange deux ensembles qui ne se recouvrent pas :

| Exposition | Blocs | Skills |
|---|---|---|
| `$PM` utilisé dans un bloc pré-exec sans vérification | **9** | **6** — `close-story`, `create-prd` (×2), `create-story` (×2), `implement-epic` (×2), `implement-story`, `worktree` |
| **glob de nom de fichier non quoté** (la partie qui concerne zsh) | **5** | **4** — `close-story:24`, `create-prd:34` et `:39`, `create-story:48`, `implement-story:73` |

`sync-pm` utilise `$PM` **en prose illustrative** (bloc ```bash, ligne 70), pas dans un bloc `!` :
il n'est pas exposé. C'est lui le « septième ».

Les `*` visibles ailleurs ne sont **pas** des globs : `case "$G" in */worktrees/*)` est un motif
de `case` (`implement-epic:54` et `:91`), `$((BUD * 3))` est de l'arithmétique
(`worktree:79`, `create-prd:44`), `-not -path './.git/*'` est quoté.

## Pourquoi le remède proposé est mauvais, dans ses deux moitiés

**`PM=${PM:-project_management}` invente une donnée**, et au pire endroit. Wispra est décrit
comme atypique — c'est-à-dire, précisément, un projet dont `project_management_dir` n'est **pas**
la valeur par défaut. Le fallback ferait lire les stories d'un répertoire qui n'est pas le bon,
ou rendrait `(none)` pour une mauvaise raison. Il transforme une condition détectable en une
valeur plausible et muette : il **aggrave** F19 au lieu de le corriger.

**`setopt +o nomatch` est un builtin zsh.** Sous bash et sous dash — tous les hôtes Linux, et un
Mac dès que l'exécuteur n'est pas zsh — il produit `setopt: command not found` **dans la sortie
du bloc pré-exec**, donc directement dans le contexte du modèle. On rendrait sept skills
bruyants pour tout le monde afin de réparer un hôte. Et `|| true` **masquerait** l'erreur que le
correctif est censé faire remonter.

## La forme que devrait prendre le correctif (non appliqué)

Ne pas désarmer le glob du shell : **ne pas s'en servir**. Un `find` à motif quoté est immunisé
contre `nomatch` dans tous les shells, sans une ligne de code spécifique — le problème zsh
disparaît alors comme effet de bord plutôt que comme cible.

```sh
PM=$(grep -m1 -E '^- \*\*project_management_dir\*\*:' ./spec.md 2>/dev/null | sed -E 's/.*: *//')
if   [ -z "$PM" ];           then echo "project_management_dir: UNRESOLVED — spec.md missing or field absent"
elif [ ! -d "$PM/stories" ]; then echo "project_management_dir: $PM — but $PM/stories does not exist"
else L=$(find "$PM/stories" -maxdepth 1 -name 'STORY-*.md' | sort)
     [ -n "$L" ] && echo "$L" || echo "(no open story files found)"
fi
```

Quatre lignes, quatre sorties distinctes, zéro code spécifique à un shell.

## La sonde qui tranche, et pourquoi elle n'est pas facultative

L'hypothèse centrale de la note — *les blocs `!` s'exécutent sous zsh* — **n'est pas établie**.
Le dépôt a déjà de la conscience macOS, mais elle porte ailleurs : `scripts/kairos-diff.sh:77` et
un test dédié de `run-tests.sh` traitent du parsing `$( )` de **bash 3.2, le `/bin/sh` de
macOS**. Si l'exécuteur est ce `/bin/sh`-là, `nomatch` n'existe pas.

À faire tourner sur le Mac, dans un appel Bash de l'agent Wispra :

```sh
echo "shell=$0 zsh=${ZSH_VERSION:-no} bash=${BASH_VERSION:-no}"
ls /nonexistent/STORY-*.md 2>/dev/null || echo FALLBACK-OK
```

- `FALLBACK-OK` affiché → shell bash-like. **`nomatch` n'est pas le sujet** ; seule la moitié
  « nommer le cas non résolu » est à faire, et F19 reste 🟠.
- `no matches found` sans `FALLBACK-OK` → zsh confirmé. La sortie injectée n'est alors plus
  seulement ambiguë, **c'est un message d'erreur de shell** — et F19 passe 🔴.

## C23 — le trou structurel derrière l'incident

`scripts/tests/run-tests.sh` teste la portabilité des **scripts** (`sh`, bash 3.2, le piège des
parenthèses de `case`). **Il ne teste rien des 66 blocs `!` des SKILL.md.** Ces blocs sont
pourtant du shell exécuté chez l'utilisateur, sur un shell qu'on ne choisit pas, et dont la
sortie entre directement dans le contexte du modèle — surface au moins aussi exposée que celle
des scripts, et la seule qui n'a aucun filet.

## Ce que l'épisode dit du reste

Trois choses valent d'être retenues au-delà du bug :

1. **Un retour d'agent qui arrive sous forme de correctif a perdu son fait en route.** Demander
   le symptôme avant le remède, systématiquement.
2. **La bonne pratique existait déjà dans le dépôt** (`sync-pm`, `${v:-<unset>}`) et n'a pas
   essaimé. C1 — découper les SKILL.md — n'aiderait pas ; ce qui manquait est un test.
3. **Le dépôt corrige la même classe de défaut pour la troisième fois** (C16, `ad2d8bc`, F19) :
   un vide qui ne se distingue pas d'une erreur. C'est un motif de conception à écrire une fois
   pour toutes, pas un bug à re-corriger par endroit.
