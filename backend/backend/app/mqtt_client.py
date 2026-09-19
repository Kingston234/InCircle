import json
import logging
from datetime import datetime, timezone
import paho.mqtt.client as mqtt
from sqlalchemy import cast, func, select
from geoalchemy2 import Geography
from geoalchemy2.elements import WKTElement
from .config import settings
from .database import SessionLocal
from .geofencing import process_location
from .models import Device, Location
from .notifier import notify_low_battery, notify_zone_events

log = logging.getLogger("mqtt")

TOPIC_LOCATION = "devices/+/location"
TOPIC_STATUS = "devices/+/status"

_client: mqtt.Client | None = None


def publish_retained(topic: str, payload: dict) -> bool:
    if _client is None or not _client.is_connected():
        return False
    info = _client.publish(topic, json.dumps(payload), qos=1, retain=True)
    return info.rc == mqtt.MQTT_ERR_SUCCESS


def _sync_device_configs(client: mqtt.Client) -> None:
    db = SessionLocal()
    try:
        rows = db.execute(
            select(Device.device_key, Device.config)
            .where(Device.config.isnot(None))
        ).all()
        for key, cfg in rows:
            client.publish(f"devices/{key}/config", json.dumps(cfg),
                           qos=1, retain=True)
        if rows:
            log.info("Zsynchronizowano konfiguracje %d urządzeń",
                     len(rows))
    except Exception:
        log.exception("Błąd synchronizacji konfiguracji urządzeń")
    finally:
        db.close()


def _parse_ts(value) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except ValueError:
        return datetime.now(timezone.utc)


def _handle_location(db, device: Device, payload: dict) -> None:
    lat, lon = float(payload["lat"]), float(payload["lon"])
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        log.warning("[%s] współrzędne poza zakresem, odrzucono", device.device_key)
        return

    hdop = payload.get("hdop")
    sats = payload.get("sats")
    if hdop is not None and float(hdop) > settings.max_hdop:
        log.info("[%s] fix odrzucony: HDOP=%.1f > %.1f", device.device_key,
                 float(hdop), settings.max_hdop)
        return
    if sats is not None and int(sats) < settings.min_sats:
        log.info("[%s] fix odrzucony: sats=%s < %s", device.device_key,
                 sats, settings.min_sats)
        return

    recorded_at = _parse_ts(payload.get("ts"))
    point = WKTElement(f"POINT({lon} {lat})", srid=4326)

    last = db.execute(
        select(Location.recorded_at, Location.battery_pct,
               func.ST_Distance(cast(Location.geom, Geography),
                                cast(point, Geography)).label("dist_m"))
        .where(Location.device_id == device.id)
        .order_by(Location.recorded_at.desc())
        .limit(1)
    ).first()
    if last is not None:
        dt_s = (recorded_at - last.recorded_at).total_seconds()
        if dt_s > 0:
            implied_kmh = (last.dist_m / dt_s) * 3.6
            if implied_kmh > settings.max_jump_speed_kmh:
                log.info("[%s] fix odrzucony: skok %.0f km/h", device.device_key,
                         implied_kmh)
                return

    loc = Location(device_id=device.id, recorded_at=recorded_at, geom=point,
                   speed_kmh=payload.get("speed_kmh"), hdop=hdop, sats=sats,
                   battery_pct=payload.get("batt"))
    db.add(loc)
    device.last_seen_at = recorded_at
    device.is_online = True
    db.flush()

    events = process_location(db, device, loc)
    notify_zone_events(db, device, events)

    batt = payload.get("batt")
    if batt is not None:
        prev_batt = last.battery_pct if last is not None else None
        crossed_down = int(batt) <= settings.low_battery_pct and (
            prev_batt is None or prev_batt > settings.low_battery_pct)
        if crossed_down:
            notify_low_battery(db, device, int(batt))
    db.commit()
    log.info("[%s] zapisano pozycję (%.5f, %.5f), zdarzeń: %d",
             device.device_key, lat, lon, len(events))


def _on_message(client, userdata, msg) -> None:
    parts = msg.topic.split("/")
    if len(parts) != 3 or parts[0] != "devices":
        return
    device_key, channel = parts[1], parts[2]

    db = SessionLocal()
    try:
        device = db.execute(
            select(Device).where(Device.device_key == device_key,
                                 Device.is_active.is_(True))
        ).scalar_one_or_none()
        if device is None:
            log.warning("Nieznane/nieaktywne urządzenie: %s", device_key)
            return

        if channel == "location":
            _handle_location(db, device, json.loads(msg.payload))
        elif channel == "status":
            device.is_online = msg.payload.decode(errors="ignore").strip() == "online"
            db.commit()
    except Exception:
        db.rollback()
        log.exception("Błąd przetwarzania wiadomości z %s", msg.topic)
    finally:
        db.close()


def _on_connect(client, userdata, flags, reason_code, properties) -> None:
    if reason_code == 0:
        client.subscribe([(TOPIC_LOCATION, 1), (TOPIC_STATUS, 1)])
        log.info("Połączono z brokerem, subskrypcje aktywne")
        _sync_device_configs(client)
    else:
        log.error("Broker odrzucił połączenie: %s", reason_code)


def start_mqtt() -> mqtt.Client:
    """Uruchamia klienta MQTT we własnym wątku (wywoływane przy starcie FastAPI)."""
    global _client
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                         client_id="backend-subscriber")
    _client = client
    client.username_pw_set(settings.mqtt_username, settings.mqtt_password)
    client.on_connect = _on_connect
    client.on_message = _on_message
    client.reconnect_delay_set(min_delay=1, max_delay=30)
    client.connect_async(settings.mqtt_host, settings.mqtt_port, keepalive=60)
    client.loop_start()
    return client