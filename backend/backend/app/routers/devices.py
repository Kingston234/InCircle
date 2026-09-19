import secrets
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select
from sqlalchemy.orm import Session
from ..auth import get_current_user
from ..database import get_db
from ..models import Device, Location, Notification, User, ZoneEvent
from ..mqtt_client import publish_retained
from ..schemas import DeviceClaim, DeviceConfigIn, DeviceCreate, DeviceOut

router = APIRouter(prefix="/devices", tags=["devices"])


def get_own_device(device_id: int, db: Session, user: User) -> Device:
    device = db.get(Device, device_id)
    if device is None or device.user_id != user.id:
        raise HTTPException(404, "Nie znaleziono urządzenia")
    return device


@router.get("", response_model=list[DeviceOut])
def list_devices(db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    latest_batt = (
        select(Location.battery_pct)
        .where(Location.device_id == Device.id)
        .order_by(Location.recorded_at.desc())
        .limit(1)
        .scalar_subquery()
    )
    rows = db.execute(
        select(Device, latest_batt.label("battery_pct"))
        .where(Device.user_id == user.id)
        .order_by(Device.id)
    ).all()
    out = []
    for device, batt in rows:
        item = DeviceOut.model_validate(device)
        item.battery_pct = batt
        out.append(item)
    return out


@router.post("", response_model=DeviceOut, status_code=201)
def create_device(data: DeviceCreate, db: Session = Depends(get_db),
                  user: User = Depends(get_current_user)):
    device = Device(user_id=user.id, name=data.name,
                    device_key=secrets.token_hex(8))
    db.add(device)
    db.commit()
    return device


@router.post("/claim", response_model=DeviceOut, status_code=201)
def claim_device(data: DeviceClaim, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    existing = db.execute(
        select(Device).where(Device.device_key == data.device_key)
    ).scalar_one_or_none()
    if existing is not None:
        if existing.user_id == user.id:
            return existing
        raise HTTPException(409, "To urządzenie jest już przypisane do innego konta")
    device = Device(user_id=user.id, name=data.name, device_key=data.device_key)
    db.add(device)
    db.commit()
    return device


@router.put("/{device_id}/config", response_model=DeviceOut)
def update_device_config(device_id: int, data: DeviceConfigIn,
                         db: Session = Depends(get_db),
                         user: User = Depends(get_current_user)):
    device = get_own_device(device_id, db, user)
    device.config = data.model_dump()
    db.commit()
    if not publish_retained(f"devices/{device.device_key}/config",
                            device.config):
        import logging
        logging.getLogger("mqtt").warning(
            "Konfiguracja %s zapisana, publikacja odroczona (urządzenie offline)",
            device.device_key)
    return device


@router.delete("/{device_id}", status_code=204)
def delete_device(device_id: int, db: Session = Depends(get_db),
                  user: User = Depends(get_current_user)):
    device = get_own_device(device_id, db, user)
    event_ids = select(ZoneEvent.id).where(ZoneEvent.device_id == device_id)
    db.execute(
        delete(Notification).where(Notification.zone_event_id.in_(event_ids)))
    db.delete(device)
    db.commit()