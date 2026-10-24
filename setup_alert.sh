#!/bin/bash
# ==============================================================================
# SBMS0-Alert-Regel nach Grafana importieren (Unified Alerting)
#
# Meldet bei echten Fehler-Flags (UVLK/OVLK/COC/DOC/DSC/OPEN/CELF/LVC)
# den deutschen Flag-Text an den Kontakt-Punkt "ntfy-sbms".
#
# Voraussetzung: Kontakt-Punkt "ntfy-sbms" ist in Grafana angelegt
#                (Alerting -> Contact points -> ntfy, Topic z. B. sbms0-alert)
#
# Aufruf:   bash setup_alert.sh
# Optional: bash setup_alert.sh "user:passwort"   (Default: admin:admin123)
# ==============================================================================

AUTH="${1:-admin:admin123}"
GRAFANA_URL="http://localhost:3001"
DIR="$(cd "$(dirname "$0")" && pwd)"
RULE_FILE="$DIR/SBMS-Alert-Error.json"

# --- 1. Grafana erreichbar? ---
if ! curl -s -u "$AUTH" "$GRAFANA_URL/api/health" | grep -q '"database"[[:space:]]*:[[:space:]]*"ok"'; then
  echo "FEHLER: Grafana nicht erreichbar unter $GRAFANA_URL (oder Login falsch)."
  exit 1
fi

# --- 2. Kontakt-Punkt "ntfy-sbms" vorhanden? ---
CP_LIST=$(curl -s -u "$AUTH" "$GRAFANA_URL/api/v1/provisioning/contact-points")
if ! echo "$CP_LIST" | grep -q '"ntfy-sbms"'; then
  echo "WARNUNG: Kontakt-Punkt 'ntfy-sbms' nicht gefunden!"
  echo "  -> Grafana-UI: Alerting -> Contact points -> Add contact point"
  echo "     Typ: ntfy, URL: https://ntfy.sh, Topic: dein-topic, Name: ntfy-sbms"
  echo "  Die Alert-Regel wird trotzdem angelegt (ohne Benachrichtigung aktiv)."
fi

# --- 3. Alert-Ordner sicherstellen (folderUID ist Pflicht) ---
FOLDER_UID="sbms0-folder"
if ! curl -s -u "$AUTH" "$GRAFANA_URL/api/folders/$FOLDER_UID" | grep -q '"uid"'; then
  curl -s -u "$AUTH" "$GRAFANA_URL/api/folders" -X POST \
    -H 'Content-Type: application/json' \
    -d "{\"uid\":\"$FOLDER_UID\",\"title\":\"SBMS0\"}" > /dev/null \
    && echo "Alert-Ordner 'SBMS0' angelegt." \
    || echo "Hinweis: Alert-Ordner konnte nicht angelegt werden (evtl. vorhanden)."
fi

# --- 4. Alert-Regel importieren (idempotent via UID) ---
RES=$(jq -c . "$RULE_FILE" | curl -s -X PUT \
  "$GRAFANA_URL/api/v1/provisioning/alert-rules/sbms0-error-alert" \
  -u "$AUTH" -H 'Content-Type: application/json' -d @-)

if echo "$RES" | grep -qi "error\|invalid\|404"; then
  # PUT scheitert wenn Regel nicht existiert -> POST versuchen
  RES=$(jq -c . "$RULE_FILE" | curl -s -X POST \
    "$GRAFANA_URL/api/v1/provisioning/alert-rules" \
    -u "$AUTH" -H 'Content-Type: application/json' -d @-)
fi

echo ""
echo "=== Ergebnis ==="
echo "$RES" | jq -r '.title // .message // "unbekannte Antwort"' 2>/dev/null || echo "$RES"
echo ""
echo "Pruefen im Grafana-UI: Alerting -> Alert rules -> SBMS0"
echo "Test-Benachrichtigung: Alerting -> Contact points -> ntfy-sbms -> Test"
