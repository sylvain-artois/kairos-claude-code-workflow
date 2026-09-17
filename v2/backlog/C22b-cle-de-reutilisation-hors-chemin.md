---
tag: C22b
statut: ouvert
gravité: coût
origine: v1 §7 (M.22.3, M.22.4)
---

# C22b — la clé de réutilisation d'un verdict ignore les fichiers hors `path`

C22 (à la reprise d'une clôture, réutiliser un verdict de gate si le diff du service n'a pas
bougé) calcule sa clé sur l'empreinte du `path` du service **seul**. Limite **acceptée** en
v1 (D11), mais exposée concrètement chez un hôte dont les tests vivent hors du `path` : le
diff du service n'a pas bougé, les tests si, et le verdict est réutilisé à tort.

**Piste** : clé = empreinte du `path` + empreinte des fichiers en attente hors de tout `path`
déclaré.

Même racine que [F27b](F27b-filet-mecanique-du-recu.md) : ce qui vit hors des `path` déclarés
n'est vu par aucun mécanisme.
