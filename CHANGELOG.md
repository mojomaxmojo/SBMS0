# Changelog

Alle nennenswerten Änderungen an diesem Projekt.

## 2026-11-05

### Entfernt
- Git-Remote `upstream` (`https://github.com/LeoAlioth/SBMS0.git`, letzter
  Commit 2023-03-12) aus `.git/config` sowie die zugehörigen Tracking-Refs
  `.git/refs/remotes/upstream/`. Ursache: Das Shakespeare-Git-Panel zeigte
  dauerhaft „96 commits ahead of upstream/master", obwohl `master` mit
  `origin/master` synchron war (`0 0`). Einziger Remote ist jetzt `origin`.
  Wiederherstellen: `git remote add upstream https://github.com/LeoAlioth/SBMS0.git && git fetch upstream`

### Hinzugefügt
- `AGENTS.md` – Dokumentation der Remote-Konventionen und Sandbox-Besonderheiten
- `CHANGELOG.md` – dieses Änderungsprotokoll

## 2026-10-28

### Geändert (Grafana-Dashboards)
- Dashboard-Links mit festen Zeitbereichen (`keepTime: false`, `?from=…&to=now`)
- HISTORIE: Standard-Zeitraum 7d → 30d
- LIVE: SOC volle Breite, Power/Monitor Flags je 50 %, Panels höher (Touchscreen),
  Titel von „Power (Live)" und „Monitor Flags" entfernt
- LIVE: Cells-Delta-Gauge auf `last("Cell Delta") * 1000` mit 5-s-Fenster
  (vorher 1m-Gruppierung über 600 Rohpunkte) – echter Live-Wert und deutlich
  weniger Last (Load Average ~9 → ~0,2–0,5)
- LIVE: Panel „Leistung (Live-Verlauf)" auf Today (`timeFrom: now/d`) mit
  1-Minuten-Abtastung aus `downsampled_1m`
- BERECHNUNGEN: Time to full/empty zeigen Hinweistext statt „No data"
- Cell-Beschriftungen: `alias: "$col"` an den Targets (entfernt
  `SBMS_Metrics.`-Präfix → `Cell 1` … `Cell 8`)
- README um Dashboard-Konventionen, Performance-Erkenntnisse und Kiosk-Setup
  erweitert
