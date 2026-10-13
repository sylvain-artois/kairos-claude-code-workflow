<!-- Entrée de journal — rédigée le 2026-09-13.
     État courant des chantiers : ../BACKLOG.md — décisions : ../DECISIONS.md -->

**Provenance** : sonde locale, pas une capture (D10). Claude Code **2.1.270**, `claude -p`
headless, modèle Haiku, lancé dans un répertoire jetable du scratchpad portant deux skills de
projet. Aucun plugin Kairos en jeu.
**Versions concernées** : le mécanisme d'hôte ; conséquence sur `skills/review/SKILL.md` (1.13.3)
**Objet** : vérifier la cause de F14 avancée en M.21.2 avant d'arbitrer C24 (plan [D11](../DECISIONS.md), étape 1).

---

# Sonde du 2026-09-13 : un jeton positionnel dans un commentaire supprime la ligne `ARGUMENTS:`

## Pourquoi une sonde hors Kairos

Le premier essai a appelé `kairos:review` depuis la session de travail, après avoir retiré les
jetons du commentaire. Il a rendu `(whole tree)`, `effort medium`, sans recheck. **Il ne prouvait
rien** : cette session charge le plugin depuis `~/.claude/plugins/cache/kairos/kairos/1.13.3`
(commit `ad4a9e9`), une copie qui porte encore `$0`/`$1` à la ligne 12 et n'a pas la modification.
Leçon à retenir : **une sonde de skill se fait dans une session qui charge le checkout**, ou hors
du plugin.

## Protocole

Deux skills identiques, `context: fork`, dont le corps demande au fork de recopier son
commentaire HTML et toute ligne commençant par `ARGUMENTS:`. Seule différence : le commentaire de
`probe-with` cite `` `$0`/`$1` ``, celui de `probe-without` n'en cite aucun. Même appel pour les deux :

```
/probe-… alpha/beta --from /tmp/some-tree --effort low --recheck
```

## Résultat

| Skill | Commentaire reçu par le fork | Ligne `ARGUMENTS:` |
|---|---|---|
| `probe-with` | « quotes positional `` `alpha/beta`/`--from` `` substitution » | **aucune** |
| `probe-without` | inchangé | **`ARGUMENTS: alpha/beta --from /tmp/some-tree --effort low --recheck`** |

**La cause de F14 est établie au niveau de l'hôte** : un jeton positionnel présent n'importe où
dans le corps, commentaire compris, est substitué sur place et supprime l'ajout de la ligne
`ARGUMENTS:`. Sans jeton, le fork reçoit la chaîne complète, drapeaux compris.

## Ce que ça change

- **C24 voie (a) fonctionne au niveau du mécanisme.** Le correctif est écrit dans
  `skills/review/SKILL.md` : jetons retirés du commentaire, et un avertissement ajouté pour
  qu'aucun jeton n'y soit réintroduit. Vérifié : plus aucun jeton `$` positionnel ni
  `ARGUMENTS` dans le fichier.
- **Reste non mesuré** : que la Phase 0 de `review` exploite correctement la ligne reçue (portée,
  `--effort`, `--recheck`). C'est ce que confirmera la capture CLIENT-1 du plan D11, sur une session
  qui charge le checkout.
- **Garde-fou utile pour C23** : un test de `run-tests.sh` qui refuse tout jeton positionnel ou
  `ARGUMENTS` dans le corps d'un skill forké **sans bloc `!` qui l'utilise** transformerait cette
  classe de défaut en échec de test.
