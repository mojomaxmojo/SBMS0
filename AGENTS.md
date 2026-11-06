# AGENTS – Hinweise für KI-Agenten

## Git-Remotes

**Einziger Remote ist `origin`:**

```
origin  https://github.com/mojomaxmojo/SBMS0 (fetch/push)
```

`origin` darf **niemals** entfernt oder umkonfiguriert werden.

### Entfernt: Remote `upstream` (2026-11-05)

| Feld | Wert |
|---|---|
| Name | `upstream` |
| URL | `https://github.com/LeoAlioth/SBMS0.git` |
| Letzter Commit dort | `0719105` – 2023-03-12 – „Update SBMS_Pi_install.py" |

**Grund der Entfernung:** Das Repo `LeoAlioth/SBMS0` ist das ursprüngliche
Fremd-Repo, aus dem dieses Projekt hervorging. Es wird nicht mehr genutzt und
seit März 2023 nicht aktualisiert. Der Remote-Tracking-Ref `upstream/master`
führte dazu, dass das Shakespeare-Git-Panel dauerhaft eine falsche Anzeige wie
„96 commits ahead of upstream/master" zeigte, obwohl `master` und
`origin/master` vollständig synchron waren (`git rev-list --left-right --count
origin/master...HEAD` → `0 0`). Das Panel vergleicht offenbar gegen alle
vorhandenen Remote-Tracking-Refs.

Zeitgleich wurden die Tracking-Refs `.git/refs/remotes/upstream/*` gelöscht.
`FETCH_HEAD` existierte nicht; `packed-refs` war leer; es gab keine
`upstream`-Einträge in `.git/logs`.

### Wiederherstellen (falls je benötigt)

```bash
git remote add upstream https://github.com/LeoAlioth/SBMS0.git
git fetch upstream
```

### Weitere Randnotiz

`.git/config` enthält einen `[shakespeare]`-Block mit
`autosync = true` und `clonedAt = 07191051fc4c4acca5fd289543e0c7f6e73ff1a3`
(= der `upstream`-Commit von 2023). Dieser Marker stammt aus dem
Projekt-Import durch Shakespeare und blieb bewusst unverändert.

## Wichtig für Agenten in dieser Sandbox

- `git remote remove <name>` wirkt hier **nicht** – stattdessen den
  `[remote "<name>"]`-Block per `awk` aus `.git/config` entfernen und mit
  `cat .cfg.new > .git/config` zurückschreiben (`mv` nach `/tmp` schlägt mit
  „cannot safely determine whether … are the same file" fehl; `python3` ist
  häufig nicht verfügbar).
- Keine History-Umschreibung (kein `rebase`/`squash`/`filter-branch`),
  keine bestehenden Commits verändern.
- Keine neuen Remotes oder Repos anlegen, deren Notwendigkeit unklar ist.
