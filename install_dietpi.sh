#!/bin/bash
# ==============================================================================
# SBMS0-Stack Installer für DietPi (Debian Trixie) auf Dell Wyse 3040
#
# Installiert ALLES via apt:
#   1. InfluxDB 1.8   (InfluxData-Repo) + Datenbank "SBMS"
#                      inkl. Retention (1 Jahr) + Downsampling (Continuous Query)
#   2. Grafana        (Grafana-Repo, aktuelle Version, z. Zt. 13.x)
#   3. Python-Pakete  (python3-serial, python3-influxdb) via Debian-Repo
#   4. sbms0-LiveLogger.py als systemd-Dienst (Autostart, 1 Hz Logging)
#   5. Grafana-Datasource via API
#
# Aufruf:   sudo ./install_dietpi.sh
# Vorher:   SBMS0-USB-Serial-Adapter einstecken
# ==============================================================================
set -e

SBMS_DIR="/home/SBMS0"
RUN_USER="dietpi"

echo "=============================================================="
echo " SBMS0-Stack Installation (APT) - DietPi / Debian Trixie"
echo "=============================================================="

if [ "$EUID" -ne 0 ]; then
  echo "Bitte mit sudo ausführen:  sudo ./install_dietpi.sh"
  exit 1
fi

# ------------------------------------------------------------------------------
# 0. Aufräumen: Konflikt-Dateien alter Skript-Läufe entfernen (MUSS vor apt!)
# ------------------------------------------------------------------------------
rm -f /etc/apt/sources.list.d/influxdb.list /etc/apt/trusted.gpg.d/influxdata.gpg

# ------------------------------------------------------------------------------
# Basis-Tools
# ------------------------------------------------------------------------------
echo ">>> Installiere Basis-Tools ..."
apt-get update -qq
apt-get install -y -qq curl gnupg wget python3-serial python3-influxdb

python3 -c "import serial, influxdb" && echo ">>> Python-Module OK (pyserial + influxdb)"

# ------------------------------------------------------------------------------
# 1. InfluxDB 1.8 (InfluxData-Repo)
#    DietPi legt das Repo bereits selbst an (/etc/apt/sources.list.d/dietpi-influxdb.list)
#    -> nur anlegen, falls nicht vorhanden (Sonst Signed-By-Konflikt!)
# ------------------------------------------------------------------------------
echo ">>> Prüfe InfluxData-Repository ..."
if ls /etc/apt/sources.list.d/dietpi-influxdb.list >/dev/null 2>&1; then
  echo ">>> DietPi-Repo für InfluxDB existiert bereits - nutze es."
else
  curl -fsSL https://repos.influxdata.com/influxdata-archive.key \
    | gpg --dearmor -o /etc/apt/trusted.gpg.d/influxdata.gpg
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/influxdata.gpg] https://repos.influxdata.com/debian bookworm stable" \
    > /etc/apt/sources.list.d/influxdb.list
fi

apt-get update -qq
echo ">>> Installiere influxdb (1.8.x) ..."
apt-get install -y -qq influxdb

# ------------------------------------------------------------------------------
# 2. Grafana (offizielles Grafana-Repo)
# ------------------------------------------------------------------------------
echo ">>> Richte Grafana-Repository ein ..."
curl -fsSL https://apt.grafana.com/gpg.key \
  | gpg --dearmor -o /etc/apt/trusted.gpg.d/grafana.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/grafana.gpg] https://apt.grafana.com oss main" \
  > /etc/apt/sources.list.d/grafana.list

apt-get update -qq
echo ">>> Installiere grafana (aktuelle Version) ..."
apt-get install -y -qq grafana

# ------------------------------------------------------------------------------
# 3. Datenbank anlegen: SBMS + Retention 1 Jahr + Downsampling
# ------------------------------------------------------------------------------
echo ">>> Starte InfluxDB ..."
systemctl enable influxdb
systemctl start influxdb
sleep 5

echo ">>> Erstelle Datenbank SBMS + Retention + Downsampling ..."
influx -execute "CREATE DATABASE SBMS WITH DURATION 365d REPLICATION 1"
influx -execute "CREATE RETENTION POLICY \"raw_1s\" ON \"SBMS\" DURATION 365d REPLICATION 1 DEFAULT"
influx -execute "CREATE RETENTION POLICY \"downsampled_1m\" ON \"SBMS\" DURATION 365d REPLICATION 1"
influx -execute "CREATE CONTINUOUS QUERY \"cq_1m\" ON \"SBMS\" BEGIN \
  SELECT mean(*) INTO \"downsampled_1m\".\"SBMS_Metrics\" FROM \"SBMS_Metrics\" GROUP BY time(1m), * END" \
  || echo "Hinweis: Continuous Query existiert evtl. schon - ignoriert."

# ------------------------------------------------------------------------------
# 4. LiveLogger als systemd-Dienst
# ------------------------------------------------------------------------------
echo ">>> Richte SBMS-LiveLogger-Dienst ein ..."
if [ ! -f "$SBMS_DIR/sbms0-LiveLogger.py" ]; then
  echo "FEHLER: $SBMS_DIR/sbms0-LiveLogger.py nicht gefunden!"
  echo "Repo korrekt geklont?  (git clone https://github.com/mojomaxmojo/SBMS0.git /home/SBMS0)"
  exit 1
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
StandardOutput=journal
StandardError=journal
SyslogIdentifier=SBMS

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable SBMS-LiveLogger

# ------------------------------------------------------------------------------
# 5. Grafana starten
# ------------------------------------------------------------------------------
echo ">>> Grafana: 1s-Refresh freischalten ..."
# Grafana begrenzt Refresh standardmäßig auf min 5s -> auf 1s lockern:
if ! grep -q "^min_refresh_interval" /etc/grafana/grafana.ini 2>/dev/null; then
  printf '\n[panels]\nmin_refresh_interval = 1s\n' >> /etc/grafana/grafana.ini
fi

echo ">>> Starte Grafana ..."
systemctl enable grafana-server
systemctl restart grafana-server

# ------------------------------------------------------------------------------
# 6. Grafana-Datasource automatisch anlegen
# ------------------------------------------------------------------------------
sleep 10
curl -s --user admin:admin "http://localhost:3000/api/datasources" -X POST \
  -H 'Content-Type: application/json;charset=UTF-8' \
  --data-binary '{"name":"SBMS_Data","isDefault":true,"type":"influxdb",\
"url":"http://localhost:8086","database":"SBMS","access":"proxy","basicAuth":false}' \
  > /dev/null || echo "Hinweis: Datasource ggf. manuell im Grafana-UI anlegen."

# ------------------------------------------------------------------------------
# 7. LiveLogger starten (nur wenn Serial-Port da ist - sonst startet er später)
# ------------------------------------------------------------------------------
if [ -e /dev/ttyUSB0 ]; then
  systemctl start SBMS-LiveLogger
else
  echo "Hinweis: /dev/ttyUSB0 nicht gefunden - LiveLogger startet beim nächsten Boot automatisch."
  echo "         SBMS0-USB-Adapter einstecken und ausführen:  systemctl start SBMS-LiveLogger"
fi

# ------------------------------------------------------------------------------
# Fertig
# ------------------------------------------------------------------------------
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=============================================================="
echo " Installation abgeschlossen!"
echo ""
echo "  Grafana  : http://${IP}:3000   (admin/admin - ändern!)"
echo "  InfluxDB : localhost:8086 (DB: SBMS)"
echo "  Logger   : systemctl status SBMS-LiveLogger"
echo ""
echo "  Nächster Schritt:"
echo "  Grafana-UI -> Dashboards -> Import -> 'SBMS-Grafana Dashboard.json'"
echo ""
echo "  Updates künftig:  sudo apt update && sudo apt upgrade"
echo "=============================================================="
