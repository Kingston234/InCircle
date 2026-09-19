from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session
from ..auth import get_current_user
from ..database import get_db
from ..models import (Device, Geofence, Notification, PushToken, User, ZoneEvent)
from ..schemas import NotificationOut, PushTokenIn, ZoneEventOut

router = APIRouter(tags=["events"])


@router.get("/events", response_model=list[ZoneEventOut])
def list_events(limit: int = Query(default=100, ge=1, le=1000),
                offset: int = Query(default=0, ge=0),
                db: Session = Depends(get_db),
                user: User = Depends(get_current_user)):
    rows = db.execute(
        select(ZoneEvent.id, ZoneEvent.device_id, Device.name.label("device_name"),
               ZoneEvent.geofence_id, Geofence.name.label("geofence_name"),
               ZoneEvent.event_type, ZoneEvent.occurred_at)
        .join(Device, Device.id == ZoneEvent.device_id)
        .join(Geofence, Geofence.id == ZoneEvent.geofence_id)
        .where(Device.user_id == user.id)
        .order_by(ZoneEvent.occurred_at.desc())
        .limit(limit).offset(offset)
    ).all()
    return [ZoneEventOut(**r._mapping) for r in rows]


@router.delete("/events/{event_id}", status_code=204)
def delete_event(event_id: int, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    ev = db.get(ZoneEvent, event_id)
    if ev is None:
        raise HTTPException(404, "Nie znaleziono zdarzenia")
    device = db.get(Device, ev.device_id)
    if device is None or device.user_id != user.id:
        raise HTTPException(404, "Nie znaleziono zdarzenia")
    db.execute(delete(Notification)
               .where(Notification.zone_event_id == event_id))
    db.delete(ev)
    db.commit()


@router.get("/notifications", response_model=list[NotificationOut])
def list_notifications(limit: int = Query(default=100, ge=1, le=1000),
                       db: Session = Depends(get_db),
                       user: User = Depends(get_current_user)):
    return db.execute(
        select(Notification)
        .where(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc())
        .limit(limit)
    ).scalars().all()


@router.delete("/notifications/{notification_id}", status_code=204)
def delete_notification(notification_id: int,
                        db: Session = Depends(get_db),
                        user: User = Depends(get_current_user)):
    notif = db.get(Notification, notification_id)
    if notif is None or notif.user_id != user.id:
        raise HTTPException(404, "Nie znaleziono powiadomienia")
    db.delete(notif)
    db.commit()


@router.post("/push/token", status_code=204)
def register_push_token(data: PushTokenIn, db: Session = Depends(get_db),
                        user: User = Depends(get_current_user)):
    stmt = pg_insert(PushToken).values(
        user_id=user.id, token=data.token, platform=data.platform
    ).on_conflict_do_update(index_elements=[PushToken.token],
                            set_={"user_id": user.id, "platform": data.platform})
    db.execute(stmt)
    db.commit()