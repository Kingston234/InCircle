import logging
import os
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from sqlalchemy import select
from .config import settings
from .models import Notification, PushToken

log = logging.getLogger("notifier")

_fcm_ready = False
try:
    if settings.fcm_credentials_file and os.path.exists(settings.fcm_credentials_file):
        import firebase_admin
        from firebase_admin import credentials, messaging
        firebase_admin.initialize_app(
            credentials.Certificate(settings.fcm_credentials_file))
        _fcm_ready = True
        log.info("Firebase zainicjalizowany")
except Exception as exc:
    log.warning("Firebase wyłączony: %s", exc)


EVENT_LABEL = {"ENTER": "wejście do strefy", "EXIT": "wyjście ze strefy"}


def _send_push(db, user_id: int, title: str, body: str, zone_event_id=None) -> None:
    tokens = db.execute(
        select(PushToken.token).where(PushToken.user_id == user_id)
    ).scalars().all()
    notif = Notification(user_id=user_id, zone_event_id=zone_event_id,
                         title=title, body=body)
    db.add(notif)
    if _fcm_ready and tokens:
        try:
            msg = messaging.MulticastMessage(
                notification=messaging.Notification(title=title, body=body),
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        channel_id="zone_events", priority="high"),
                ),
                tokens=tokens,
            )
            messaging.send_each_for_multicast(msg)
            notif.sent_at = datetime.now(timezone.utc)
        except Exception as exc:
            log.error("Błąd wysyłki Firebase: %s", exc)
    else:
        log.info("POWIADOMIENIE: %s - %s", title, body)


def notify_low_battery(db, device, battery_pct: int) -> None:
    title = f"{device.name}: niska bateria"
    body = f"Zostało {battery_pct}% · naładuj lokalizator"
    _send_push(db, device.user_id, title, body)


def notify_zone_events(db, device, events) -> None:
    if not events:
        return

    db.flush()

    for ev in events:
        title = f"{device.name}: {EVENT_LABEL.get(ev.event_type, ev.event_type)}"
        local_time = ev.occurred_at.astimezone(ZoneInfo(settings.timezone))
        zone = getattr(ev, "geofence_name", ev.geofence_id)
        body = f"Strefa „{zone}” · {local_time:%H:%M}"
        _send_push(db, device.user_id, title, body, zone_event_id=ev.id)