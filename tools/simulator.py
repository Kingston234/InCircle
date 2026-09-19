import argparse
import json
import math
import random
import time
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

M_PER_DEG_LAT = 111_320.0


def offset(lat: float, lon: float, north_m: float, east_m: float) -> tuple[float, float]:
    dlat = north_m / M_PER_DEG_LAT
    dlon = east_m / (M_PER_DEG_LAT * math.cos(math.radians(lat)))
    return lat + dlat, lon + dlon


def build_route(clat: float, clon: float, radius_m: float) -> list[tuple[float, float]]:
    pts: list[tuple[float, float]] = []
    # 1) dojście z 500 m na południe pod granicę strefy
    for d in range(-500, -int(radius_m), 40):
        pts.append(offset(clat, clon, d, 0))
    # 2) trzepotanie na granicy: ±25 m wokół krawędzi (test histerezy)
    for _ in range(12):
        jitter = random.uniform(-25, 25)
        pts.append(offset(clat, clon, -(radius_m + jitter), 0))
    # 3) wejście do środka strefy
    for d in range(-int(radius_m), 0, 40):
        pts.append(offset(clat, clon, d, 0))
    pts.append((clat, clon))
    # 4) wyjście daleko na północ
    for d in range(0, 600, 40):
        pts.append(offset(clat, clon, d, 0))
    return pts


def main() -> None:
    ap = argparse.ArgumentParser(description="Symulator trackera GPS (MQTT)")
    ap.add_argument("--host", default="localhost")
    ap.add_argument("--port", type=int, default=1883)
    ap.add_argument("--user", default="tracker")
    ap.add_argument("--password", required=True)
    ap.add_argument("--device", required=True, help="device_key z POST /devices")
    ap.add_argument("--lat", type=float, default=52.4064, help="środek strefy testowej")
    ap.add_argument("--lon", type=float, default=16.9252)
    ap.add_argument("--radius", type=float, default=200.0)
    ap.add_argument("--interval", type=float, default=2.0, help="sekundy między punktami")
    ap.add_argument("--batt", type=int, default=100,
                    help="startowy poziom baterii (np. 22 = demo alertu niskiej baterii)")
    args = ap.parse_args()

    state = {"interval": args.interval}

    def on_message(cl, userdata, msg):
        try:
            cfg = json.loads(msg.payload)
            s = int(cfg.get("report_interval_s", 0))
            if 5 <= s <= 3600:
                state["interval"] = float(s)
                print(f"[CFG] Nowy interwał raportowania: {s} s")
        except (ValueError, TypeError):
            pass

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"sim-{args.device}")
    client.username_pw_set(args.user, args.password)
    client.on_message = on_message
    client.will_set(f"devices/{args.device}/status", "offline", qos=1, retain=True)
    client.connect(args.host, args.port, keepalive=30)
    client.loop_start()
    client.publish(f"devices/{args.device}/status", "online", qos=1, retain=True)
    client.subscribe(f"devices/{args.device}/config", qos=1)

    topic = f"devices/{args.device}/location"
    route = build_route(args.lat, args.lon, args.radius)
    print(f"Publikuję {len(route)} punktów na {topic} (co {args.interval}s)...")

    for i, (lat, lon) in enumerate(route, 1):
        payload = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "lat": round(lat, 6), "lon": round(lon, 6),
            "speed_kmh": round(random.uniform(3, 6), 1),
            "hdop": round(random.uniform(0.8, 1.8), 1),
            "sats": random.randint(6, 11),
            "batt": max(5, args.batt - i // 3),
        }
        client.publish(topic, json.dumps(payload), qos=1)
        print(f"  [{i}/{len(route)}] {payload['lat']}, {payload['lon']}")
        time.sleep(state["interval"])

    client.publish(f"devices/{args.device}/status", "offline", qos=1, retain=True)
    client.loop_stop()
    client.disconnect()
    print("Koniec trasy.")


if __name__ == "__main__":
    main()
