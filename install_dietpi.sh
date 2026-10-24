#!/bin/bash
# ==============================================================================
# SBMS0-Stack Installer für DietPi (Debian Trixie) auf Dell Wyse 3040
#
# Struktur:
#   TEIL 1: ALLE Pakete via apt (Abhängigkeiten inklusive)
#   TEIL 2: Dienste anlegen (Datenbank, Logger-Unit, Grafana-Config)
#
# Idempotent: kann mehrfach ausgeführt werden.
# Updates später:  sudo apt update && sudo apt upgrade
#
# Aufruf:   sudo ./install_dietpi.sh
# ==============================================================================
set -e

SBMS_DIR="/home/SBMS0"
RUN_USER="dietpi"

echo "=============================================================="
echo " SBMS0-Stack Installation - Teil 1: PAKETE (apt)"
echo "=============================================================="

if [ "$EUID" -ne 0 ]; then
  echo "Bitte mit sudo ausführen:  sudo ./install_dietpi.sh"
  exit 1
fi

# ------------------------------------------------------------------------------
# TEIL 1 - ALLE PAKETE VIA APT
# ------------------------------------------------------------------------------

# --- Repositories: DietPi bringt InfluxDB- UND Grafana-Repo bereits mit -------
echo ">>> [1/6] Prüfe Repositories (DietPi-Repo behalten, Duplikate entfernen) ..."
for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
  [ -f "$f" ] || continue
  # InfluxDB-Repo:
  if grep -q "repos.influxdata.com" "$f" 2>/dev/null; then
    if grep -q "dietpi-influxdb" "$f" 2>/dev/null; then
      echo "    DietPi-InfluxDB-Repo gefunden: $f - ok"
      DIETPI_INFLUX=1
    else
      echo "    Entferne doppeltes InfluxDB-Repo: $f"
      rm -f "$f"
    fi
  fi
  # Grafana-Repo:
  if grep -q "apt.grafana.com" "$f" 2>/dev/null; then
    if grep -q "dietpi-grafana" "$f" 2>/dev/null; then
      echo "    DietPi-Grafana-Repo gefunden: $f - ok"
      DIETPI_GRAFANA=1
    else
      echo "    Entferne doppeltes Grafana-Repo: $f"
      rm -f "$f"
    fi
  fi
done
# Verwaiste Keys alter Skript-Läufe entfernen:
rm -f /etc/apt/trusted.gpg.d/influxdata.gpg /etc/apt/keyrings/grafana.gpg /etc/apt/keyrings/influxdata.gpg

# Fallback: Falls kein Repo existiert (z. B. reines Debian ohne DietPi), anlegen:
if [ -z "$DIETPI_INFLUX" ] && ! grep -rqs "repos.influxdata.com" /etc/apt/sources.list 2>/dev/null; then
  echo "    Lege InfluxData-Repo an ..."
  curl -fsSL https://repos.influxdata.com/influxdata-archive.key \
    | gpg --dearmor -o /etc/apt/keyrings/influxdata.gpg
  echo "deb [signed-by=/etc/apt/keyrings/influxdata.gpg] https://repos.influxdata.com/debian bookworm stable" \
    > /etc/apt/sources.list.d/influxdb.list
fi
if [ -z "$DIETPI_GRAFANA" ] && ! grep -rqs "apt.grafana.com" /etc/apt/sources.list 2>/dev/null; then
  echo "    Lege Grafana-Repo an ..."
  curl -fsSL https://apt.grafana.com/gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
    > /etc/apt/sources.list.d/grafana.list
fi

echo ">>> [2/6] apt update ..."
apt-get update -qq

echo ">>> [3/6] Installiere ALLE Pakete (InfluxDB, Grafana, Python, Tools) ..."
apt-get install -y -qq \
  influxdb \
  grafana \
  python3-serial \
  python3-influxdb \
  curl gnupg wget tar git

# --- Prüfung der Python-Module (Abhängigkeit des LiveLoggers) ------------------
python3 -c "import serial, influxdb" \
  && echo ">>> Python-Module OK (pyserial + influxdb)" \
  || { echo "FEHLER: Python-Module fehlen!"; exit 1; }

echo ""
echo "=============================================================="
echo " SBMS0-Stack Installation - Teil 2: DIENSTE"
echo "=============================================================="

# ------------------------------------------------------------------------------
# InfluxDB: Dienst + Datenbank + Retention + Downsampling
# ------------------------------------------------------------------------------
echo ">>> [4/6] InfluxDB-Dienst starten ..."
systemctl enable --now influxdb
sleep 5

echo ">>> [5/6] Datenbank SBMS + Retention (1 Jahr) + Downsampling (1 min) ..."
influx -database SBMS -execute "CREATE DATABASE SBMS WITH DURATION 365d REPLICATION 1" 2>/dev/null \
  && echo "    DB angelegt" || echo "    DB existiert bereits - ok"
influx -database SBMS -execute "CREATE RETENTION POLICY \"raw_1s\" ON \"SBMS\" DURATION 365d REPLICATION 1 DEFAULT" 2>/dev/null \
  && echo "    Retention raw_1s angelegt" || echo "    Retention raw_1s existiert bereits - ok"
influx -database SBMS -execute "CREATE RETENTION POLICY \"downsampled_1m\" ON \"SBMS\" DURATION 365d REPLICATION 1" 2>/dev/null \
  && echo "    Retention downsampled_1m angelegt" || echo "    Retention downsampled_1m existiert bereits - ok"
influx -database SBMS -execute "CREATE CONTINUOUS QUERY \"cq_1m\" ON \"SBMS\" BEGIN \
  SELECT mean(*) INTO \"downsampled_1m\".\"SBMS_Metrics\" FROM \"SBMS_Metrics\" GROUP BY time(1m), * END" 2>/dev/null \
  && echo "    Continuous Query angelegt" || echo "    Continuous Query existiert bereits - ok"

# ------------------------------------------------------------------------------
# LiveLogger: systemd-Unit (python3-serial/python3-influxdb sind via apt da)
# ------------------------------------------------------------------------------
echo ">>> [6/6] SBMS-LiveLogger-Dienst einrichten ..."
# Service-User braucht Zugriff auf den Serial-Port (/dev/ttyUSB0):
if id "$RUN_USER" &>/dev/null; then
  usermod -aG dialout "$RUN_USER" && echo "    $RUN_USER zur Gruppe dialout hinzugefügt"
fi
# Git: root darf das dem dietpi gehörende Repo verwalten:
git config --global --add safe.directory "$SBMS_DIR" 2>/dev/null || true
# Schreibrechte für den Service-User (CSV-Fallback im Repo-Verzeichnis):
if [ -d "$SBMS_DIR" ]; then
  chown -R "$RUN_USER":"$RUN_USER" "$SBMS_DIR"
fi
if [ ! -f "$SBMS_DIR/sbms0-LiveLogger.py" ]; then
  echo "WARNUNG: $SBMS_DIR/sbms0-LiveLogger.py nicht gefunden!"
  echo "         Repo klonen:  git clone https://github.com/mojomaxmojo/SBMS0.git $SBMS_DIR"
  echo "         (Logger-Dienst wird trotzdem eingerichtet, startet erst mit Datei.)"
fi

cat > /etc/systemd/system/SBMS-LiveLogger.service <<EOF
[Unit]
Description=SBMS0 Serial LiveLogger (1 Hz -> InfluxDB)
After=network.target influxdb.service
Requires=influxdb.service

[Service]
User=${RUN_USER}
ExecStart=/usr/bin/python3 ${SBMS_DIR}/sbms0-LiveLogger.py
Restart=always
RestartSec=10
SyslogIdentifier=SBMS

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable SBMS-LiveLogger
if [ -e /dev/ttyUSB0 ]; then
  systemctl restart SBMS-LiveLogger
  echo "    Logger gestartet (/dev/ttyUSB0 gefunden)"
else
  echo "    Hinweis: /dev/ttyUSB0 nicht da - Logger startet beim nächsten Boot / nach Einstecken:"
  echo "             systemctl start SBMS-LiveLogger"
fi

# ------------------------------------------------------------------------------
# Grafana: 1s-Refresh freischalten + Dienst + Datasource
# ------------------------------------------------------------------------------
echo ">>> Grafana: 1s-Refresh freischalten ..."
if [ ! -f /etc/systemd/system/grafana-server.service.d/override.conf ] || \
   ! grep -q "GF_DASHBOARDS_MIN_REFRESH_INTERVAL" /etc/systemd/system/grafana-server.service.d/override.conf 2>/dev/null; then
  mkdir -p /etc/systemd/system/grafana-server.service.d
  printf '[Service]\nEnvironment="GF_DASHBOARDS_MIN_REFRESH_INTERVAL=1s"\n' \
    > /etc/systemd/system/grafana-server.service.d/override.conf
fi
# Falsche [panels]-Sektion in der INI entfernen (Grafana 13 liest [dashboards]):
sed -i '/^min_refresh_interval = 1s$/d' /etc/grafana/grafana.ini 2>/dev/null || true

systemctl enable --now grafana-server
systemctl restart grafana-server
sleep 10

curl -s --user admin:admin123 "http://localhost:3001/api/datasources" -X POST \
  -H 'Content-Type: application/json;charset=UTF-8' \
  --data-binary '{"name":"SBMS_Data","uid":"dg20jcsde4wlcd","isDefault":true,"type":"influxdb",\
"url":"http://localhost:8086","database":"SBMS","access":"proxy","basicAuth":false}' \
  > /dev/null || echo "    Hinweis: Datasource ggf. manuell im Grafana-UI anlegen."

# ------------------------------------------------------------------------------
# Abschluss + Status
# ------------------------------------------------------------------------------
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=============================================================="
echo " FERTIG! Status der Dienste:"
systemctl is-active influxdb grafana-server SBMS-LiveLogger \
  | paste -d' ' <(echo -e "influxdb:\ngrafana-server:\nSBMS-LiveLogger:") - \
  || true
echo ""
echo "  Grafana  : http://${IP}:3001   (admin/admin123 - ändern!)"
echo "  Dashboards: SBMS-Dash-START / -LIVE / -BERECHNUNGEN / -HISTORIE importieren"
echo "              (Datasource-UID dg20jcsde4wlcd ist bereits angelegt)"
echo "  Updates  : sudo apt update && sudo apt upgrade"
echo "=============================================================="
