#!/bin/bash
# ==============================================================================
# SBMS0-Dashboards automatisch nach Grafana importieren
#
# Importiert alle 4 SBMS0-Dashboards (START, LIVE, BERECHNUNGEN, HISTORIE)
# via Grafana HTTP-API. Idempotent: wiederholte Laeufe aktualisieren die
# bestehenden Dashboards (overwrite, gleiche UIDs).
#
# Aufruf:   ./import_dashboards.sh
# Optional: ./import_dashboards.sh "user:passwort"   (Default: admin:admin123)
# ==============================================================================

AUTH="${1:-admin:admin123}"
GRAFANA_URL="http://localhost:3001"
DIR="$(cd "$(dirname "$0")" && pwd)"

DASHBOARDS=(
  "SBMS-Dash-START.json"
  "SBMS-Dash-LIVE.json"
  "SBMS-Dash-BERECHNUNGEN.json"
  "SBMS-Dash-HISTORIE.json"
)

# Grafana erreichbar? (grep toleriert beliebige Leerzeichen im JSON)
HEALTH=$(curl -s -u "$AUTH" "$GRAFANA_URL/api/health")
echo "$HEALTH" | grep -q '"database"[[:space:]]*:[[:space:]]*"ok"' \
  || { echo "FEHLER: Grafana nicht erreichbar unter $GRAFANA_URL (oder Login falsch).";
       echo "Laeuft Grafana?  systemctl status grafana-server";
       exit 1; }

echo ">>> Importiere ${#DASHBOARDS[@]} Dashboards nach Grafana ($GRAFANA_URL) ..."
echo ""

OK=0
FAIL=0
for f in "${DASHBOARDS[@]}"; do
  [ -f "$DIR/$f" ] || { echo "FEHLER: $f nicht gefunden in $DIR"; FAIL=$((FAIL+1)); continue; }
  RES=$(jq '{dashboard: (. + {id: null}), overwrite: true, message: "SBMS0-Import"}' "$DIR/$f" \
    | curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
        -u "$AUTH" -H 'Content-Type: application/json' -d @-)
  STATUS=$(echo "$RES" | jq -r '.status // .message // "unbekannt"')
  UID=$(echo "$RES" | jq -r '.uid // "?"')
  if [ "$STATUS" = "success" ]; then
    echo "  OK    $f  (uid=$UID)"
    OK=$((OK+1))
  else
    echo "  FAIL  $f  -> $STATUS"
    FAIL=$((FAIL+1))
  fi
done

echo ""
echo "=============================================================="
echo " Fertig: $OK erfolgreich, $FAIL fehlgeschlagen"
echo " Grafana: http://$(hostname -I | awk '{print $1}'):3001"
echo "=============================================================="
[ $FAIL -eq 0 ] && exit 0 || exit 1
