import os
import socket

# ==============================================================================
# SBMS0 Raspberry-Pi Installer (LITE/IOT-Variante, Python 3)
# Batterie: 280 Ah / 24 V (8s LiFePO4)
#
# HINWEIS: Fuer DietPi/Dell Wyse 3040 bitte install_dietpi.sh verwenden!
#          Dieses Skript ist nur fuer Raspberry Pi OS (Bookworm+) gedacht.
#
# Aufruf:  sudo python3 SBMS_Pi-IOT_install.py
# ==============================================================================

# --- InfluxDB-Repository (keyring, apt-key ist deprecated) ---
os.system("sudo mkdir -p /etc/apt/keyrings")
os.system("curl -fsSL https://repos.influxdata.com/influxdata-archive.key | "
          "sudo gpg --dearmor -o /etc/apt/keyrings/influxdata.gpg")
os.system("echo 'deb [signed-by=/etc/apt/keyrings/influxdata.gpg] "
          "https://repos.influxdata.com/debian bookworm stable' | "
          "sudo tee /etc/apt/sources.list.d/influxdb.list")

os.system("sudo apt update")

# --- InfluxDB + Datenbank (Retention 1 Jahr + 1-Min-Downsampling) ---
os.system("sudo apt install -y influxdb influxdb-client")
os.system("sudo systemctl unmask influxdb")
os.system("sudo systemctl enable --now influxdb")
os.system("influx -execute 'CREATE DATABASE SBMS WITH DURATION 365d REPLICATION 1'")
os.system("influx -execute 'CREATE RETENTION POLICY \"raw_1s\" ON \"SBMS\" DURATION 365d REPLICATION 1 DEFAULT'")
os.system("influx -execute 'CREATE RETENTION POLICY \"downsampled_1m\" ON \"SBMS\" DURATION 365d REPLICATION 1'")
os.system("influx -execute 'CREATE CONTINUOUS QUERY \"cq_1m\" ON \"SBMS\" BEGIN "
          "SELECT mean(*) INTO \"downsampled_1m\".\"SBMS_Metrics\" FROM \"SBMS_Metrics\" "
          "GROUP BY time(1m), * END'")

# --- Python-Abhängigkeiten (Python 3, PEP 668) ---
os.system("sudo apt install -y python3-serial python3-influxdb")
os.system("sudo pip3 install pyserial influxdb --break-system-packages")

# --- Logger-Skript + systemd-Unit laden ---
os.system("sudo wget --no-check-certificate --content-disposition "
          "'https://raw.githubusercontent.com/Burtond/Electrodacus/master/sbms0-SerialToInfluxDB.py' -P '/home/SBMS0/'")
os.system("sudo wget --no-check-certificate --content-disposition "
          "'https://raw.githubusercontent.com/Burtond/Electrodacus/master/SBMS-Logger.service' -P '/etc/systemd/system/'")
os.system("sudo systemctl daemon-reload")
os.system("sudo systemctl enable SBMS-Logger.service")
os.system("sudo systemctl start SBMS-Logger.service")


# --- Grafana-Datasource ---
def get_ip_address():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("8.8.8.8", 80))
    return s.getsockname()[0]

ipaddress = get_ip_address()
os.system("curl --user admin:admin \"http://" + ipaddress + ":3000/api/datasources\" -X POST "
          "-H 'Content-Type: application/json;charset=UTF-8' --data-binary "
          "'{\"name\":\"SBMS_Data\",\"isDefault\":true ,\"type\":\"influxdb\","
          "\"url\":\"http://localhost:8086\",\"database\":\"SBMS\",\"access\":\"proxy\",\"basicAuth\":false}'")

print("Login to http://" + ipaddress + ":3000")
print("Username = admin, password = admin (sofort aendern!)")
