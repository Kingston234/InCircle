#!/usr/bin/env python3
"""InCircle tracker."""

import argparse
import csv
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

import serial


PORT = os.getenv("INCIRCLE_SERIAL_PORT", "/dev/serial0")
BAUD = int(os.getenv("INCIRCLE_SERIAL_BAUD", "115200"))
PWRKEY_GPIO = int(os.getenv("INCIRCLE_PWRKEY_GPIO", "4"))

HOST = os.getenv("INCIRCLE_MQTT_HOST", "")
MQTT_PORT = int(os.getenv("INCIRCLE_MQTT_PORT", "1883"))
USER = os.getenv("INCIRCLE_MQTT_USER", "")
PASSWORD = os.getenv("INCIRCLE_MQTT_PASSWORD", "")
DEVICE = os.getenv("INCIRCLE_DEVICE", "")
APN = os.getenv("INCIRCLE_APN", "IoT")

LOGDIR = os.path.expanduser(
    os.getenv("INCIRCLE_LOG_DIR", "~/incircle_log")
)
os.makedirs(LOGDIR, exist_ok=True)

STAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
LOGFILE = os.path.join(LOGDIR, f"{STAMP}.log")
CSVFILE = os.path.join(LOGDIR, f"{STAMP}.csv")

ser = None


def log(message):
    line = f"[{datetime.now():%H:%M:%S}] {message}"
    print(line, flush=True)

    try:
        with open(LOGFILE, "a", encoding="utf-8") as file:
            file.write(line + "\n")
    except OSError:
        pass


def command(at_command, timeout=20, show=False):
    ser.reset_input_buffer()
    ser.write((at_command + "\r\n").encode())

    started = time.time()
    response = ""

    while time.time() - started < timeout:
        time.sleep(0.3)

        if ser.in_waiting:
            response += ser.read(ser.in_waiting).decode(errors="ignore")

        if any(
            marker in response
            for marker in ("OK", "ERROR", "SMSTATE", "ACTIVE", ">")
        ):
            break

    if show:
        log(f"  {at_command} -> {response.strip()[:90] or '(brak)'}")

    return response


def read_battery():
    try:
        import smbus2

        bus = smbus2.SMBus(1)

        voltage_high = bus.read_byte_data(0x10, 0x03)
        voltage_low = bus.read_byte_data(0x10, 0x04)
        soc_high = bus.read_byte_data(0x10, 0x05)
        soc_low = bus.read_byte_data(0x10, 0x06)

        voltage = (voltage_high << 8 | voltage_low) * 1.25
        soc = int((soc_high << 8 | soc_low) * 0.003906)

        bus.close()
        return soc, round(voltage)

    except Exception:
        return 0, 0


def pulse_pwrkey():
    log("  impuls PWRKEY")

    try:
        subprocess.run(
            ["pinctrl", "set", str(PWRKEY_GPIO), "op", "dh"],
            capture_output=True,
            check=True,
        )
        time.sleep(1.2)

        subprocess.run(
            ["pinctrl", "set", str(PWRKEY_GPIO), "op", "dl"],
            capture_output=True,
            check=True,
        )
        time.sleep(14)

        return True

    except (OSError, subprocess.SubprocessError) as error:
        log(f"  PWRKEY nie zadzialal: {error}")
        return False


def modem_alive(attempts=4):
    for _ in range(attempts):
        if "OK" in command("AT", 2):
            return True
        time.sleep(1)

    return False


def wait_for_network(timeout=90):
    started = time.time()

    registered_states = (
        "CEREG: 0,1",
        "CEREG: 0,5",
        "CEREG: 1,1",
        "CEREG: 1,5",
        "CEREG: 2,1",
        "CEREG: 2,5",
    )

    while time.time() - started < timeout:
        response = command("AT+CEREG?", 5)

        if any(state in response for state in registered_states):
            signal = command("AT+CSQ", 3).strip().split("\n")[0]
            log(f"  zarejestrowany w sieci ({signal})")
            return True

        time.sleep(4)

    log("  BRAK rejestracji w sieci")
    return False


def startup(skip_reset=False):
    log("--- START MODEMU ---")

    command("AT", 2)

    if modem_alive():
        log("  modem odpowiada")
    else:
        log("  modem milczy")
        pulse_pwrkey()
        command("AT", 2)

        if modem_alive(6):
            log("  modem odpowiada po PWRKEY")
        else:
            log("  MODEM NIE ODPOWIADA")
            return False

    command("ATE0", 2)

    if not skip_reset:
        log("  restart stosu radiowego")
        command("AT+CFUN=1,1", 10)
        time.sleep(45)
        command("AT", 2)

        if not modem_alive(8):
            log("  modem nie wrocil po restarcie")
            pulse_pwrkey()

            if not modem_alive(6):
                log("  MODEM NIE ODPOWIADA")
                return False

        command("ATE0", 2)

    if "READY" not in command("AT+CPIN?", 5):
        log("  karta SIM niegotowa")
        return False

    command("AT+CNMP=2", 4)
    command("AT+CMNB=3", 4)

    if not wait_for_network():
        return False

    log("--- MODEM GOTOWY ---")
    return True


def get_fix(timeout):
    command("AT+CGNSPWR=1", 5)
    time.sleep(3)

    started = time.time()
    position = None

    while time.time() - started < timeout:
        response = command("AT+CGNSINF", 3)
        line = next(
            (
                item
                for item in response.split("\n")
                if "+CGNSINF:" in item
            ),
            None,
        )

        if line:
            fields = [
                field.strip()
                for field in line.split(":", 1)[1].split(",")
            ]

            if len(fields) >= 15 and fields[0] == "1" and fields[1] == "1":
                try:
                    latitude = float(fields[3])
                    longitude = float(fields[4])

                    if latitude or longitude:
                        position = {
                            "lat": latitude,
                            "lon": longitude,
                            "alt": round(float(fields[5] or 0), 1),
                            "spd": float(fields[6] or 0),
                            "hdop": float(fields[11] or 0),
                            "sat": int(fields[14] or 0),
                            "ttff": int(time.time() - started),
                        }
                        break

                except (ValueError, IndexError):
                    pass

        time.sleep(3)

    command("AT+CGNSPWR=0", 5)
    time.sleep(5)

    return position


def mqtt_try():
    command(f'AT+CGDCONT=1,"IP","{APN}"', 5)
    command(f'AT+CNCFG=0,1,"{APN}"', 5)
    command("AT+CNACT=0,1", 30)
    command("AT+SMDISC", 5)
    command(f'AT+SMCONF="URL","{HOST}",{MQTT_PORT}', 5)
    command(f'AT+SMCONF="CLIENTID","inc-{int(time.time())}"', 5)
    command(f'AT+SMCONF="USERNAME","{USER}"', 5)
    command(f'AT+SMCONF="PASSWORD","{PASSWORD}"', 5)
    command('AT+SMCONF="CLEANSS",1', 5)
    command('AT+SMCONF="QOS",0', 5)
    command("AT+SMCONN", 60)

    return "+SMSTATE: 1" in command("AT+SMSTATE?", 8)


def mqtt_connect():
    if mqtt_try():
        return True

    log("  polaczenie nieudane -- restart modemu")
    command("AT+CFUN=1,1", 10)
    time.sleep(45)
    command("AT", 2)

    if not modem_alive(8):
        pulse_pwrkey()

        if not modem_alive(6):
            log("  modem nie wrocil po restarcie")
            return False

    command("ATE0", 2)

    if not wait_for_network(60):
        return False

    log("  druga proba polaczenia")
    return mqtt_try()


def publish(position, soc):
    payload = json.dumps(
        {
            "ts": datetime.now(timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            ),
            "lat": round(position["lat"], 6),
            "lon": round(position["lon"], 6),
            "speed_kmh": round(position["spd"], 1),
            "hdop": position["hdop"],
            "sats": position["sat"],
            "batt": soc,
        },
        separators=(",", ":"),
    )

    payload_size = len(payload.encode("utf-8"))
    response = command(
        f'AT+SMPUB="devices/{DEVICE}/location",'
        f"{payload_size},0,0",
        15,
    )

    if ">" not in response:
        log("  brak znaku zachety")
        ser.write(b"\x1a")
        time.sleep(1)
        ser.reset_input_buffer()
        return False, payload

    ser.write(payload.encode("utf-8"))

    started = time.time()
    response = ""

    while time.time() - started < 20:
        time.sleep(0.3)

        if ser.in_waiting:
            response += ser.read(ser.in_waiting).decode(errors="ignore")

        if "OK" in response or "ERROR" in response:
            break

    if "OK" in response and "ERROR" not in response:
        return True, payload

    log(f"  publikacja nieudana: {response.strip()[:60]}")
    ser.write(b"\x1a")
    time.sleep(1)
    ser.reset_input_buffer()

    return False, payload


def validate_configuration():
    required = {
        "INCIRCLE_MQTT_HOST": HOST,
        "INCIRCLE_MQTT_USER": USER,
        "INCIRCLE_MQTT_PASSWORD": PASSWORD,
        "INCIRCLE_DEVICE": DEVICE,
    }

    missing = [
        variable
        for variable, value in required.items()
        if not value
    ]

    if missing:
        names = ", ".join(missing)
        raise RuntimeError(
            f"Brak wymaganych zmiennych środowiskowych: {names}"
        )


def parse_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "-n",
        "--cycles",
        type=int,
        default=6,
        help="liczba cykli; 0 oznacza pracę bez końca",
    )
    parser.add_argument(
        "-i",
        "--interval",
        type=int,
        default=15,
        help="odstęp między cyklami w sekundach",
    )
    parser.add_argument(
        "--fix-timeout",
        type=int,
        default=120,
        help="maksymalny czas oczekiwania na pozycję",
    )
    parser.add_argument(
        "--skip-reset",
        action="store_true",
        help="pomija restart modemu przy uruchomieniu",
    )

    return parser.parse_args()


def main():
    global ser

    arguments = parse_arguments()
    validate_configuration()

    ser = serial.Serial(PORT, BAUD, timeout=1)
    time.sleep(0.5)
    ser.reset_input_buffer()

    log("=" * 54)
    log(
        f" InCircle -- "
        f"{arguments.cycles or 'nieskonczonych'} cykli co "
        f"{arguments.interval} s"
    )
    log(f" log: {LOGFILE}")
    log("=" * 54)

    if not startup(arguments.skip_reset):
        log("start modemu nieudany -- koniec")
        ser.close()
        sys.exit(1)

    csv_file = open(CSVFILE, "w", newline="", encoding="utf-8")
    writer = csv.writer(csv_file)

    writer.writerow(
        [
            "cykl",
            "czas",
            "lat",
            "lon",
            "alt",
            "sat",
            "hdop",
            "ttff_s",
            "bat_proc",
            "bat_mv",
            "czas_cyklu_s",
            "wyslano",
        ]
    )

    cycle = 0
    successful = 0

    try:
        while arguments.cycles == 0 or cycle < arguments.cycles:
            cycle += 1
            cycle_started = time.time()

            log("-" * 54)
            log(f"CYKL {cycle}")

            position = get_fix(arguments.fix_timeout)

            if not position:
                log("  brak fixu -- pomijam cykl")

                writer.writerow(
                    [
                        cycle,
                        datetime.now().isoformat(timespec="seconds"),
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        0,
                    ]
                )
            else:
                log(
                    f"  FIX ({position['ttff']} s): "
                    f"{position['lat']:.6f}, "
                    f"{position['lon']:.6f} | "
                    f"sat {position['sat']} | "
                    f"HDOP {position['hdop']}"
                )

                soc, voltage = read_battery()
                sent = False

                if mqtt_connect():
                    sent, payload = publish(position, soc)
                    status = "WYSLANO" if sent else "NIE WYSLANO"
                    log(f"  {status}: {payload}")
                    command("AT+SMDISC", 8)
                else:
                    log("  nie polaczono z brokerem")

                if sent:
                    successful += 1

                writer.writerow(
                    [
                        cycle,
                        datetime.now().isoformat(timespec="seconds"),
                        position["lat"],
                        position["lon"],
                        position["alt"],
                        position["sat"],
                        position["hdop"],
                        position["ttff"],
                        soc,
                        voltage,
                        round(time.time() - cycle_started, 1),
                        int(sent),
                    ]
                )

            csv_file.flush()

            elapsed = round(time.time() - cycle_started, 1)
            log(
                f"  cykl: {elapsed} s | "
                f"[{successful}/{cycle} udanych]"
            )

            if arguments.cycles == 0 or cycle < arguments.cycles:
                time.sleep(arguments.interval)

    except KeyboardInterrupt:
        log("przerwano")
    except Exception as error:
        log(f"BLAD: {error}")
    finally:
        try:
            command("AT+SMDISC", 8)
            command("AT+CGNSPWR=0", 5)
        except Exception:
            pass

        csv_file.close()
        ser.close()

    log("=" * 54)
    log(f" KONIEC: {successful}/{cycle} udanych")
    log(f" csv: {CSVFILE}")
    log("=" * 54)


if __name__ == "__main__":
    main()