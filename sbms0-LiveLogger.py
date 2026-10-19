#!/usr/bin/env python3
"""
SBMS0 Live-Logger
=================
Liest die Daten des Electrodacus SBMS0 über USB/Serial,
zeigt sie live im Terminal an und loggt sie jede Sekunde
in eine CSV-Datei.

  - Live-Anzeige:  übersichtliche Tabelle im Terminal (SSH-tauglich)
  - Logging:       1 Datensatz pro Sekunde in sbms_log_YYYY-MM-DD.csv
  - Beenden:       STRG+C

Voraussetzung:  pip3 install pyserial
Aufruf:         python3 sbms0-LiveLogger.py [/dev/ttyUSB0]

Basierend auf der Dekompressions-Logik von sbms0-SerialToInfluxDB.py
(David Buron, public domain).
"""

import csv
import datetime
import os
import sys
import time

import serial

# ---------------------------------------------------------------- Konfiguration
SERIAL_PORT = sys.argv[1] if len(sys.argv) > 1 else '/dev/ttyUSB0'
BAUD_RATE = 921600
LOG_INTERVAL = 1.0          # Sekunden zwischen CSV-Einträgen
LOG_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_HEADER = [
    'timestamp',
    'SOC %',
    'Battery Voltage V',
    'Battery Current A',
    'Cell 1 V', 'Cell 2 V', 'Cell 3 V', 'Cell 4 V',
    'Cell 5 V', 'Cell 6 V', 'Cell 7 V', 'Cell 8 V',
    'Cell Delta V',
    'PV Total Current A', 'PV1 A', 'PV2 A',
    'External Load A',
    'Internal Temp C', 'External Temp C',
    'Heat 1', 'Heat 2',
    'ADC2 V', 'ADC3 V', 'ADC4 V',
    'Error Code', 'Error Binary', 'Flags',
]

# ---------------------------------------------------------------- Dekompression
def dcmp(p, s, d):
    """Dekomprimiert einen Wert aus dem SBMS0-Datenstring (wie im Original)."""
    xx = 0
    for z in range(s):
        xx = xx + ((ord(d[(p + s - 1) - z]) - 35) * pow(91, z))
    return xx


def parse_line(line):
    """Parst einen SBMS0-Datenstring in ein dict. Wirft IndexError/ValueError bei kaputten Zeilen."""
    SOC = float(dcmp(6, 2, line))

    cells = [float(dcmp(8 + i * 2, 2, line)) / 1000 for i in range(8)]

    Internal_temp = round(float((dcmp(24, 2, line) - 450) / 10), 3)
    External_temp = round(float((dcmp(26, 2, line) - 450) / 10), 3)

    sign = line[28]
    Batt_current = round(float(dcmp(29, 3, line)) / 1000, 3)
    if sign == '-':
        Batt_current = -Batt_current

    PV1 = float(dcmp(32, 3, line))
    PV2 = float(dcmp(35, 3, line))
    External_load = round(float(dcmp(38, 3, line)) / 1000, 3)
    ADC2 = float(dcmp(41, 3, line)) / 1000
    ADC3 = float(dcmp(44, 3, line)) / 1000
    ADC4 = float(dcmp(47, 3, line)) / 1000
    heat1 = float(dcmp(50, 3, line))
    heat2 = float(dcmp(53, 3, line))
    ERR = dcmp(56, 3, line)

    Battery_voltage = round(sum(cells), 3)

    active = [v for v in cells if v > 0]
    delta = (max(active) - min(active)) if active else 0.0

    # Flags (siehe SBMS0-Dokumentation)
    flag_defs = [
        (16384, 'DFET'), (8192, 'EOC'), (4096, 'CFET'), (2048, 'ECCF'),
        (1024, 'LVC'), (512, 'OPEN'), (256, 'CELF'), (128, 'DSC'),
        (64, 'DOC'), (32, 'COC'), (16, 'IOT'), (8, 'UVLK'),
        (4, 'UV'), (2, 'OVLK'), (1, 'OV'),
    ]
    flags = ', '.join(name for bit, name in flag_defs if ERR & bit)

    return {
        'SOC': SOC,
        'Battery Voltage': Battery_voltage,
        'Battery Current': Batt_current,
        'Cells': cells,
        'Cell Delta': round(delta, 4),
        'PV Total': round((PV1 + PV2) / 1000, 3),
        'PV1': PV1,
        'PV2': PV2,
        'External Load': External_load,
        'Internal Temp': Internal_temp,
        'External Temp': External_temp,
        'Heat 1': heat1,
        'Heat 2': heat2,
        'ADC2': ADC2,
        'ADC3': ADC3,
        'ADC4': ADC4,
        'Error Code': ERR,
        'Error Binary': '{0:016b}'.format(ERR),
        'Flags': flags,
    }

# ---------------------------------------------------------------- Anzeige
CLEAR = '\033[2J\033[H'
RESET = '\033[0m'
BOLD = '\033[1m'

def fmt(value, unit='', width=8, decimals=2):
    if isinstance(value, float):
        return f'{value:>{width}.{decimals}f}{unit}'
    return f'{str(value):>{width}}{unit}'


def render(data, ts, status):
    """Baut die Terminal-Anzeige als String."""
    lines = []
    lines.append(CLEAR + BOLD + '=' * 62)
    lines.append('  SBMS0 LIVE-MONITOR   ' + ts.strftime('%Y-%m-%d %H:%M:%S'))
    lines.append('  ' + status)
    lines.append('=' * 62 + RESET)
    lines.append('')
    lines.append(f'  SOC          : {fmt(data["SOC"], " %")}')
    lines.append(f'  Akku-Spannung: {fmt(data["Battery Voltage"], " V")}')
    cur = data['Battery Current']
    arrow = ' (+ Laden)' if cur > 0 else (' (- Entladen)' if cur < 0 else '')
    lines.append(f'  Akku-Strom   : {fmt(cur, " A")}{arrow}')
    lines.append('')
    lines.append(BOLD + '  Zellspannungen:' + RESET)
    for i, v in enumerate(data['Cells'], 1):
        bar_len = int(max(0.0, min(v / 4.2, 1.0)) * 20) if v > 0 else 0
        bar = '#' * bar_len
        lines.append(f'  Zelle {i}       : {fmt(v, " V"):<14} {bar}')
    lines.append(f'  Zell-Delta   : {fmt(data["Cell Delta"], " V")}')
    lines.append('')
    lines.append(BOLD + '  PV & Last:' + RESET)
    lines.append(f'  PV gesamt    : {fmt(data["PV Total"], " A")}')
    lines.append(f'  PV1 / PV2    : {fmt(data["PV1"], " A")} / {fmt(data["PV2"], " A")}')
    lines.append(f'  Externe Last : {fmt(data["External Load"], " A")}')
    lines.append('')
    lines.append(BOLD + '  Temperatur & Sonstiges:' + RESET)
    lines.append(f'  Temp intern  : {fmt(data["Internal Temp"], " C")}')
    lines.append(f'  Temp extern  : {fmt(data["External Temp"], " C")}')
    lines.append(f'  Heat1/Heat2  : {fmt(data["Heat 1"])} / {fmt(data["Heat 2"])}')
    lines.append(f'  ADC2/3/4     : {fmt(data["ADC2"])} / {fmt(data["ADC3"])} / {fmt(data["ADC4"])}')
    lines.append('')
    lines.append(BOLD + '  Status:' + RESET)
    lines.append(f'  Error-Code   : {data["Error Code"]}  ({data["Error Binary"]})')
    lines.append(f'  Flags        : {data["Flags"] or "(keine)"}')
    lines.append('')
    lines.append('  Logging: ' + log_file.name + '   (Beenden: STRG+C)')
    return '\n'.join(lines)

# ---------------------------------------------------------------- CSV-Logging
today = datetime.date.today().isoformat()
log_file = open(os.path.join(LOG_DIR, f'sbms_log_{today}.csv'), 'a', newline='')
writer = csv.writer(log_file)
# Kopfzeile nur schreiben, wenn Datei neu/leer ist
if os.path.getsize(log_file.name) == 0:
    writer.writerow(CSV_HEADER)
    log_file.flush()

# ---------------------------------------------------------------- Hauptschleife
def main():
    status = 'Warte auf Daten von ' + SERIAL_PORT + ' ...'
    data = None
    last_log = 0.0

    ser = None
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2)
    except (serial.SerialException, OSError) as e:
        print(f'FEHLER: Serial-Port {SERIAL_PORT} nicht verfuegbar: {e}')
        print('SBMS0 angeschlossen? Richtiger Port? (z.B. python3 sbms0-LiveLogger.py /dev/ttyUSB1)')
        sys.exit(1)

    try:
        while True:
            now = time.time()

            # --- Neue Serial-Daten lesen und parsen (nicht blockierend Dank timeout) ---
            try:
                line = ser.readline().decode('ascii', errors='ignore').strip()
                if line and len(line) >= 59:
                    data = parse_line(line)
                    status = 'Daten OK - letztes Update: ' + datetime.datetime.now().strftime('%H:%M:%S')
            except (serial.SerialException, OSError):
                # USB weggefallen -> neu verbinden
                status = 'WARNUNG: Serial-Port verloren - warte auf Geraet ...'
                try:
                    ser.close()
                except Exception:
                    pass
                time.sleep(5)
                try:
                    ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2)
                except (serial.SerialException, OSError):
                    continue
            except (IndexError, ValueError):
                # Kaputte Zeile -> ignorieren, weiterlesen
                pass

            # --- Alle LOG_INTERVAL Sekunden: anzeigen + CSV schreiben ---
            if now - last_log >= LOG_INTERVAL:
                last_log = now
                ts = datetime.datetime.now()

                if data is None:
                    # Noch keine gueltigen Daten: Platzhalter
                    data = {k: (0.0 if not isinstance(v, str) else '') for k, v in
                            [(k, CSV_HEADER[i]) for i, k in enumerate(CSV_HEADER[1:])]}
                    data['Cells'] = [0.0] * 8

                # Terminal-Anzeige
                print(render(data, ts, status))

                # CSV-Zeile schreiben
                row = [ts.isoformat(timespec='seconds'),
                       data['SOC'], data['Battery Voltage'], data['Battery Current']]
                row += data['Cells']
                row += [data['Cell Delta'], data['PV Total'], data['PV1'], data['PV2'],
                        data['External Load'], data['Internal Temp'], data['External Temp'],
                        data['Heat 1'], data['Heat 2'], data['ADC2'], data['ADC3'], data['ADC4'],
                        data['Error Code'], data['Error Binary'], data['Flags']]
                writer.writerow(row)
                log_file.flush()

    except KeyboardInterrupt:
        pass
    finally:
        print(CLEAR + 'Beendet. Log-Datei: ' + log_file.name)
        log_file.close()
        if ser:
            ser.close()


if __name__ == '__main__':
    main()
