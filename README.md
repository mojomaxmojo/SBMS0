# SBMS0 – Electrodacus Solar/BMS Monitoring-Stack

Automation & Monitoring für Electrodacus SBMS0 Komponenten.

## System

| Komponente | Wert |
|---|---|
| **Batterie** | **280 Ah / 24 V** (8s LiFePO4, ~6,72 kWh) |
| Logger | `sbms0-LiveLogger.py` – 1 Datapoint/Sekunde → InfluxDB 1.8 |
| Datenbank | InfluxDB, DB `SBMS`, RP `raw_1s` (365d, DEFAULT) + `downsampled_1m` |
| Visualisierung | Grafana (**Port 3001**) |

## Grafana-Dashboards

| Datei | UID | Zweck |
|---|---|---|
| `SBMS-Dash-START.json` | `sbms-start-01` | Übersicht / Startseite (Today) |
| `SBMS-Dash-LIVE.json` | `sbms-live-01` | Live-Werte (10 min, 5 s Refresh) |
| `SBMS-Dash-BERECHNUNGEN.json` | `sbms-calc-01` | Tagesenergie & Lade-Prognosen (280 Ah) (Today) |
| `SBMS-Dash-HISTORIE.json` | `sbms-hist-01` | Verlauf (1-Min-Daten) (30 Tage) |
| `SBMS-Grafana Dashboard.json` | `sbms-legacy-today-01` | Legacy (migriert: raw_1s, 280 Ah) |
| `SBMS-Mojo-Grafana-Dashboard.json` | `sbms-legacy-live-01` | Legacy (migriert: raw_1s, 280 Ah) |

Datasource-UID: `dg20jcsde4wlcd` (InfluxDB, DB `SBMS`).

### Dashboard-Konventionen (wichtig bei Änderungen!)

- **Feste Zeitbereiche pro Dashboard:** START/BERECHNUNGEN `now/d` (Today), LIVE `now-10m`, HISTORIE `now-30d`. Die Dashboard-Links untereinander haben `keepTime: false` und tragen den Ziel-Zeitbereich in der URL (`?from=…&to=now`) – so wird der Zeitbereich beim Umschalten nicht aus der Browser-Session mitgeschleppt.
- **Kiosk-Start-URL** (DietPi, `/boot/dietpi.txt` → `SOFTWARE_CHROMIUM_AUTOSTART_URL`): enthält `?from=now-10m&to=now&kiosk&refresh=5s`, damit auch der Kiosk-Neustart immer korrekt startet.
- **„Leistung (Live-Verlauf)"** im LIVE-Dashboard hat einen Panel-Override auf `now/d` (Feld `timeFrom`) + 1-Min-Abtastung aus `downsampled_1m` (`mean("Battery Power W")`, `mean("PV Power W")`, `mean("Consumption Power W")`). Rest des Dashboards bleibt live auf `raw_1s`.
- **Hinweis zu Panel-Time-Overrides:** Moderne Grafana-Versionen benötigen dafür `timeFrom: "now/d"` am Panel – der legacy-`time`-Block allein wirkt nicht.
- **Cell-Beschriftung:** Targets der Cell-Panels (LIVE + BERECHNUNGEN) haben `alias: "$col"` – das entfernt den Präfix `SBMS_Metrics.` und zeigt `Cell 1` … `Cell 8`. Transformationen (renameByRegex) reichen hierfür nicht.
- **Cells-Delta-Gauge (LIVE):** `last("Cell Delta") * 1000` mit 5-s-Fenster – echt live und sehr günstig. Die 1-Min-Verlaufs-Query liegt im HISTORIE-Dashboard.
- **Time to full/empty (BERECHNUNGEN):** zeigen statt „No data" einen Hinweistext („– lädt gerade nicht (entlädt)" bzw. umgekehrt) über eine Status-Serie + Value-Mapping. Die Prognose-Queries nutzen bewusst eigene gleitende Zeitfenster (5m/15m/1h/24h), unabhängig vom Dashboard-Zeitraum.
- **Layout (Touchscreen):** SOC volle Breite oben (h=4), Power + Monitor Flags je 50 % darunter (ohne Titel), Cell Voltages/Cells Delta, darunter „Leistung (Live-Verlauf)" in voller Breite (h=13).

## Performance (Wyse 3040, 2 GB RAM)

- Load wurde von ~9 auf ~0.2–0.5 gedrückt durch: Cells-Delta-Query (`last()`, 5-s-Fenster statt 1m-Gruppierung über 600 Rohpunkte), 5-s-Refresh, Chromium-Kiosk-Neustart.
- Größter Verbraucher bleibt der Chromium-Renderer (Softwarerendering, ~100 % Momentan-CPU), aber ohne Warteschlange – System ist gesund.
- Bei RAM-/Load-Anstieg über Tage: nächtlichen Reboot-Cron einplanen (z. B. `0 4 * * * /sbin/reboot`).
- Optional (noch nicht umgesetzt): Logger schreibt nur bei neuen Serial-Daten; Terminal-Render throtteln; `raw_1s`-Retention 365d → 60d (Verläufe laufen über `downsampled_1m`).

## Wichtige Berechnungs-Formeln (BERECHNUNGEN-Dashboard)

- Energie: `sum(<Power W>) / 3600 / 1000` → kWh (bei 1 Hz-Daten)
- Time to full: `280 × (100 − SOC)/100 ÷ Ladestrom(A) × 60` → Minuten
- Time to empty: `280 × SOC/100 ÷ Entladestrom(A) × 60` → Minuten
- Kapazität **280 Ah** ist in den Time-to-Queries hart hinterlegt (6 Stellen).

## Dienste

| Unit | Beschreibung |
|---|---|
| `SBMS-LiveLogger.service` | 1-Hz-Logger → InfluxDB (+ eigene 1-Min-Mittelwerte) — **DietPi-Standard, User `dietpi`** |
| `SBMS-Logger.service` | Legacy-Logger `sbms0-SerialToInfluxDB.py` (nur Pi-Installer, User `pi`) |

## Ziel-System

Primäres Zielsystem ist **DietPi (Debian Trixie) auf Dell Wyse 3040** — `install_dietpi.sh` deckt alles ab (Pakete, DB, Retention, Downsampling, Dienst, Grafana-Config inkl. 1-s-Refresh-Freischaltung). Die Pi-Installer sind nur Fallback für Raspberry-Pi-Hardware.

## Kiosk-Setup (DietPi / Dell Wyse 3040 Touchscreen)

- **Autostart:** `dietpi-autostart` → Option 11 „Chromium – Dedicated use without desktop"; URL-Abfrage schreibt `SOFTWARE_CHROMIUM_AUTOSTART_URL` in `/boot/dietpi.txt`.
- **Auflösung:** `SOFTWARE_CHROMIUM_RES_X/Y` in `/boot/dietpi.txt` (hier 1920×1200).
- **Chromium-Flags:** `/var/lib/dietpi/dietpi-software/installed/chromium-autostart.sh` → `CHROMIUM_OPTS` um `--no-first-run --no-default-browser-check --disable-component-update --disable-infobars --disable-session-crashed-bubble --disable-features=Translate` ergänzt (kein `--disable-gpu`!). Wird ggf. von DietPi-Updates überschrieben → Flags bei Bedarf erneut setzen.
- **Git-Permissions:** Falls `git pull` als `dietpi` mit „insufficient permission" fehlschlägt: `sudo chown -R dietpi:dietpi /home/SBMS0` (einmalig; Ursache sind vorherige Root-Write-Zugriffe in `.git/objects`).

## Update-Ablauf (Dashboard-Änderungen)

```bash
cd /home/SBMS0 && git pull && bash import_dashboards.sh
```
Anschließend Dashboard im Browser/Kiosk frisch laden (Shift+F5 bzw. Kiosk-Neustart).
