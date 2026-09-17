# `telemetry/` — mesurer Kairos sur des runs réels

Trois choses vivent ici, et une seule est versionnée.

| | Quoi | Régime |
|---|---|---|
| `analyze_telemetry.py` | Dépouille une capture brute en CSV plats | **versionné** |
| `analysis_YYYYMMDD<lettre>/` | Les CSV d'une capture | **non versionné** — archive compressée hors git |
| `reports/` | Les rapports rédigés à partir des CSV | **non versionné** |

Les conclusions, elles, sont dans le journal du projet — une entrée datée par capture — et la
série complète (numéro, date, objet, version, coût) est tenue en **§5 de `BACKLOG.md`**.
C'est l'index à lire, pas ce répertoire.

## Prendre et dépouiller une capture

La capture brute est écrite par la sonde dans `~/.civilia-telemetry/api-bodies/<session-uuid>/`
— un fichier `.request.json` et un `.response.json` par appel API. Une session d'épic pèse
100 à 600 Mo.

```sh
# la capture la plus récente, sortie dans analysis_<aujourd'hui><prochaine lettre>
python3 analyze_telemetry.py --label "implement-epic story-346..350, hôte AFK"

# ou une capture nommée, vers un répertoire choisi
python3 analyze_telemetry.py ~/.civilia-telemetry/api-bodies/<uuid> \
    --out analysis_20260914d --label "..."
```

Le `--label` ne sert qu'à nommer la source dans les CSV : le modèle, l'effort et le thinking
sont lus dans les corps de requête, qui font foi.

**Règle d'hygiène : on supprime la capture brute une fois l'analyse produite.** 16 captures
conservées faisaient 2,7 Go pour 5 Mo de CSV. Les CSV sont la base de preuve, pas le brut.

## Convention de nommage

`analysis_YYYYMMDD<lettre>` — la date du dépouillement, puis `a`, `b`, `c`… dans la journée.
Le script attribue la prochaine lettre libre tout seul quand on omet `--out`.

Les noms d'avant le 2026-09-17 étaient thématiques. Correspondance, pour retrouver une
référence dans une note ancienne ou un export :

| Ancien | Nouveau | | Ancien | Nouveau |
|---|---|---|---|---|
| `analysis_run122` | `analysis_20260830a` | | `analysis_epic24` | `analysis_20260908a` |
| `analysis_epic22` | `analysis_20260901a` | | `analysis_playwright` | `analysis_20260910a` |
| `analysis_732b` | `analysis_20260901b` | | `analysis_afk` | `analysis_20260913a` |
| `analysis_epic2stories` | `analysis_20260903a` | | `analysis_epic27` | `analysis_20260914a` |
| `analysis_epic17views` | `analysis_20260904a` | | `analysis_pw2` | `analysis_20260914b` |
| `analysis_v113` | `analysis_20260905a` | | `analysis_pw3` | `analysis_20260914c` |
| `analysis_epic6stories` | `analysis_20260907a` | | `analysis_afk2` | `analysis_20260914d` |
| `analysis_v1133` | `analysis_20260907b` | | | |

`analysis/` n'était pas une sortie de capture — ses CSV étaient vides — mais trois rapports
rédigés. Il est devenu `reports/`.
