---
tag: F26b
statut: ouvert
gravité: hygiène
origine: v1 §7 (M.22.6)
---

# F26b — généraliser `grep -F` aux motifs littéraux

Les 3 contrôles de préfixe fautifs ont été corrigés en v1 (exception accordée le 2026-09-14).
Reste la règle générale, non écrite.

**Trois gestes** :

- dans la prose des skills, préférer `grep -F` pour tout motif littéral ;
- ne jamais compter sur `grep -r` pour voir un fichier ignoré par git ;
- un test de `run-tests.sh` qui refuse un `grep` sans `-F` sur un motif contenant `$`.

Le troisième est le seul qui empêche la rechute — les deux premiers sont de la discipline, et
la discipline seule a déjà échoué trois fois.
