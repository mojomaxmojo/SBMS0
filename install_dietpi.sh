#!/bin/bash
# ==============================================================================
# SBMS0-Stack Installer für DietPi (Debian-basiert) auf Dell Wyse 3040
#
# Installiert:
#   1. InfluxDB 1.8.10 (Tarball, /opt/influxdb) + Datenbank "SBMS"
#      inkl. Retention Policy (1 Jahr) + Downsampling (Continuous Query)
#   2. Grafana (Tarball, /opt/grafana)
#   3. Python-Abhängigkeiten (pyserial, influxdb)
#   4. sbms0-LiveLogger.py als systemd-Dienst (Autostart, 1 Hz Logging)
#   5. systemdataource für Grafana via API
#
# Aufruf:   sudo ./install_dietpi.sh
# Vorher:   sbms0-LiveLogger.py in /home/SBMS0/ ablegen
# ==============================================================================
set -e

SBMS_DIR="/home/SBMS0"
INFLUX_DIR="/opt/influxdb"
GRAFANA_DIR="/opt/grafana"
INFLUX_VERSION="1.8.10"
GRAFANA_VERSION="10.4.2"
RUN_USER="dietpi"

echo "=============================================================="
echo " SBMS0-Stack Installation auf DietPi (Wyse 3040)"
echo "=============================================================="

# Prüfen ob root
if [ "$EUID" -ne 0 ]; then
  echo "Bitte mit sudo ausführen:  sudo ./install_dietpi.sh"
  exit 1
fi

# ------------------------------------------------------------------------------
# 1. Abhängigkeiten (DietPi-Tools nutzen, da apt-Quellen durch DietPi verwaltet)
# ------------------------------------------------------------------------------
echo ">>> Installiere Basis-Pakete ..."
dietpi-software install 200 2>/dev/null || true   # Python 3 pip (DietPi-Software-ID)
pip3 install --quiet pyserial influxdb || {
  apt-get update -qq && apt-get install -y -qq python3-pip
  pip3 install --quiet pyserial influxdb
}

# ------------------------------------------------------------------------------
# 2. InfluxDB 1.8 (Tarball - kein apt nötig, Debian-Version-g robust)
# ------------------------------------------------------------------------------
if [ ! -f "$INFLUX_DIR/influxd" ]; then
  echo ">>> Lade InfluxDB ${INFLUX_VERSION} ..."
  cd /tmp
  wget -q "https://dl.influxdata.com/influxdb/releases/influxdb-${INFLUX_VERSION}_linux_amd64.tar.gz"
  tar -xzf "influxdb-${INFLUX_VERSION}_linux_amd64.tar.gz"
  cp "influxdb-${INFLUX_VERSION}_linux_amd64/influxd"  "$INFLUX_DIR/" 2>/dev/null || {
    mkdir -p "$INFLUX_DIR"
    cp "influxdb-${INFLUX_VERSION}_linux_amd64/influxd"  "$INFLUX_DIR/"
    cp "influxdb-${INFLUX_VERSION}_linux_amd64/influx"   "$INFLUX_DIR/"
  }
  rm -rf "influxdb-${INFLUX_VERSION}_linux_amd64" "influxdb-${INFLUX_VERSION}_linux_amd64.tar.gz"
else
  echo ">>> InfluxDB bereits installiert - überspringe Download."
fi

# InfluxDB-Datenverzeichnis auf interne SSD (Standard: /var/lib/influxdb)
mkdir -p /var/lib/influxdb
chown -R "$RUN_USER":"$RUN_USER" "$INFLUX_DIR" /var/lib/influxdb

# ------------------------------------------------------------------------------
# 3. Grafana (Tarball)
# ------------------------------------------------------------------------------
if [ ! -f "$GRAFANA_DIR/bin/grafana-server" ]; then
  echo ">>> Lade Grafana ${GRAFANA_VERSION} ..."
  cd /tmp
  wget -q "https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz"
  tar -xzf "grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz"
  mv "grafana-v${GRAFANA_VERSION}" "$GRAFANA_DIR"
  rm -f "grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz"
else
  echo ">>> Grafana bereits installiert - überspringe Download."
fi
chown -R "$RUN_USER":"$RUN_USER" "$GRAFANA_DIR"

# ------------------------------------------------------------------------------
# 4. systemd-Dienste (InfluxDB, Grafana, LiveLogger)
# ------------------------------------------------------------------------------
echo ">>> Richte systemd-Dienste ein ..."

cat > /etc/systemd/system/influxdb.service <<EOF
[Unit]
Description=InfluxDB 1.8 time-series database
After=network.target

[Service]
User=${RUN_USER}
ExecStart=${INFLUX_DIR}/influxd -config /etc/influxdb/influxdb.conf
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /etc/influxdb
if [ ! -f /etc/influxdb/influxdb.conf ]; then
  "$INFLUX_DIR/influxd" config > /etc/influxdb/influxdb.conf
fi
chown -R "$RUN_USER":"$RUN_USER" /etc/influxdb

cat > /etc/systemd/system/grafana-server.service <<EOF
[Unit]
Description=Grafana Dashboard Server
After=network.target influxdb.service
Requires=influxdb.service

[Service]
User=${RUN_USER}
ExecStart=${GRAFANA_DIR}/bin/grafana-server \\
  --homepath ${GRAFANA_DIR} \\
  --config ${GRAFANA_DIR}/conf/defaults.ini \\
  cfg:default.paths.data=/var/lib/grafana \\
  cfg:default.paths.logs=/var/log/grafana
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /var/lib/grafana /var/log/grafana
chown -R "$RUN_USER":"$RUN_USER" /var/lib/grafana /var/log/grafana

# LiveLogger-Dienst (Serial-Logger, 1 Hz -> InfluxDB)
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
systemctl enable influxdb grafana-server SBMS-LiveLogger

# ------------------------------------------------------------------------------
# 5. Dienste starten + Datenbank/Retention/Downsampling anlegen
# ------------------------------------------------------------------------------
echo ">>> Starte InfluxDB ..."
systemctl start influxdb
sleep 5

echo ">>> Erstelle Datenbank SBMS + Retention (1 Jahr) + Downsampling ..."
"$INFLUX_DIR/influx" -execute "CREATE DATABASE SBMS WITH DURATION 365d REPLICATION 1"
"$INFLUX_DIR/influx" -execute "CREATE RETENTION POLICY \"raw_1s\" ON \"SBMS\" DURATION 365d REPLICATION 1 DEFAULT"
"$INFLUX_DIR/influx" -execute "CREATE RETENTION POLICY \"downsampled_1m\" ON \"SBMS\" DURATION 365d REPLICATION 1"
"$INFLUX_DIR/influx" -execute "CREATE CONTINUOUS QUERY \"cq_1m\" ON \"SBMS\" BEGIN \
  SELECT mean(*) INTO \"downsampled_1m\".\"SBMS_Metrics\" FROM \"SBMS_Metrics\" GROUP BY time(1m), * END"

echo ">>> Starte Grafana ..."
systemctl start grafana-server

echo ">>> Starte SBMS-LiveLogger ..."
systemctl start SBMS-LiveLogger

# ------------------------------------------------------------------------------
# 6. Grafana-Datasource automatisch anlegen
# ------------------------------------------------------------------------------
sleep 10
IP=$(hostname -I | awk '{print $1}')
curl -s --user admin:admin "http://localhost:3000/api/datasources" -X POST \
  -H 'Content-Type: application/json;charset=UTF-8' \
  --data-binary '{"name":"SBMS_Data","isDefault":true,"type":"influxdb",\
"url":"http://localhost:8086","database":"SBMS","access":"proxy","basicAuth":false}' \
  > /dev/null || echo "Hinweis: Datasource ggf. manuell anlegen (Grafana-UI)."

# ------------------------------------------------------------------------------
# Fertig
# ------------------------------------------------------------------------------
systemctl --no-pager status SBMS-LiveLogger | head -3
echo ""
echo "=============================================================="
echo " Installation abgeschlossen!"
echo ""
echo "  Grafana  : http://${IP}:3000   (admin/admin - ändern!)"
echo "  InfluxDB : localhost:8086 (DB: SBMS)"
echo "  Logger   : systemctl status SBMS-LiveLogger"
echo ""
echo "  Nächster Schritt:"
echo "  Dashboard-JSON (SBMS-Grafana Dashboard.json) importieren:"
echo "  Grafana-UI -> Dashboards -> Import"
echo ""
echo "  Retention: Rohdaten 1s = 365 Tage (hoffe, das passt!)"
echo "  Downsampling: 1-Minuten-Mittelwerte für Jahresauswertung"
echo "=============================================================="
