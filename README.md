# SBMS0 – Electrodacus Solar/BMS Monitoring-Stack

Automation & Monitoring für Electrodacus SBMS0 Komponenten.

## System

| Komponente | Wert |
|---|---|
| **Batterie** | **280 Ah / 24 V** (8s LiFePO4, ~6,72 kWh) |
| Logger | `sbms0-LiveLogger.py` – 1 Datapoint/Sekunde → InfluxDB 1.8 |
| Datenbank | InfluxDB, DB `SBMS`, RP `raw_1s` (365d, DEFAULT) + `downsampled_1m` |
| Visualisierung | Grafana (Dashboards s. u.) |

## Grafana-Dashboards

| Datei | UID | Zweck |
|---|---|---|
| `SBMS-Dash-START.json` | `sbms-start-01` | Übersicht / Startseite |
| `SBMS-Dash-LIVE.json` | `sbms-live-01` | Live-Werte (1 s) |
| `SBMS-Dash-BERECHNUNGEN.json` | `sbms-calc-01` | Tagesenergie & Lade-Prognosen (280 Ah) |
| `SBMS-Dash-HISTORIE.json` | `sbms-hist-01` | Verlauf (1-Min-Daten) |
| `SBMS-Grafana Dashboard.json` | `sbms-legacy-today-01` | Legacy (migriert: raw_1s, 280 Ah) |
| `SBMS-Mojo-Grafana-Dashboard.json` | `sbms-legacy-live-01` | Legacy (migriert: raw_1s, 280 Ah) |

Datasource-UID: `dg20jcsde4wlcd` (InfluxDB, DB `SBMS`).

## Installation

### DietPi / Debian (Dell Wyse 3040) – empfohlen
```bash
sudo ./install_dietpi.sh
```
Installiert InfluxDB, Grafana, Python-Module, richtet `SBMS-LiveLogger` als systemd-Dienst ein und konfiguriert Retention/Downsampling.

### Raspberry Pi (Legacy)
```bash
sudo mkdir /home/SBMS0
cd /home/SBMS0
sudo wget -O SBMS_Pi_install.py https://raw.githubusercontent.com/LeoAlioth/SBMS0/master/SBMS_Pi_install.py
sudo python3 SBMS_Pi_install.py
```
Nutzt den klassischen `sbms0-SerialToInfluxDB.py`-Logger (ohne Live-Anzeige).

## Wichtige Berechnungs-Formeln (BERECHNUNGEN-Dashboard)

- Energie: `sum(<Power W>) / 3600 / 1000` → kWh (bei 1 Hz-Daten)
- Time to full: `280 × (100 − SOC)/100 ÷ Ladestrom(A) × 60` → Minuten
- Time to empty: `280 × SOC/100 ÷ Entladestrom(A) × 60` → Minuten
- Kapazität **280 Ah** ist in den Time-to-Queries hart hinterlegt (6 Stellen).

## Dienste

| Unit | Beschreibung |
|---|---|
| `SBMS-LiveLogger.service` | 1-Hz-Logger → InfluxDB (+ eigene 1-Min-Mittelwerte) |
| `SBMS-Logger.service` | Legacy-Logger `sbms0-SerialToInfluxDB.py` |
