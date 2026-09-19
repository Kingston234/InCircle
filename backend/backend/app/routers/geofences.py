from fastapi import APIRouter, Depends, HTTPException
from geoalchemy2 import Geography, Geometry
from sqlalchemy import cast, delete, func, select
from sqlalchemy.orm import Session
from ..auth import get_current_user
from ..database import get_db
from ..models import Geofence, Notification, User, ZoneEvent, ZoneState
from ..schemas import GeofenceCreate, GeofenceOut
from .devices import get_own_device

router = APIRouter(prefix="/geofences", tags=["geofences"])


def _build_geom(data: GeofenceCreate):
    if data.type == "circle":
        if data.center_lat is None or data.center_lon is None or data.radius_m is None:
            raise HTTPException(422, "Okrąg wymaga center_lat, center_lon i radius_m")
        center = func.ST_SetSRID(func.ST_MakePoint(data.center_lon, data.center_lat), 4326)
        return cast(func.ST_Buffer(cast(center, Geography), data.radius_m),
                    Geometry(geometry_type="POLYGON", srid=4326))

    if not data.polygon or len(data.polygon) < 3:
        raise HTTPException(422, "Wielokąt wymaga co najmniej 3 wierzchołków [lat, lon]")
    ring = list(data.polygon)
    if ring[0] != ring[-1]:
        ring.append(ring[0])
    coords = ", ".join(f"{lon} {lat}" for lat, lon in ring)
    return func.ST_Buffer(func.ST_GeomFromText(f"POLYGON(({coords}))", 4326), 0)


@router.get("", response_model=list[GeofenceOut])
def list_geofences(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return db.execute(
        select(Geofence).where(Geofence.user_id == user.id).order_by(Geofence.id)
    ).scalars().all()


@router.post("", response_model=GeofenceOut, status_code=201)
def create_geofence(data: GeofenceCreate, db: Session = Depends(get_db),
                    user: User = Depends(get_current_user)):
    if data.device_id is not None:
        get_own_device(data.device_id, db, user)
    fence = Geofence(
        user_id=user.id, device_id=data.device_id, name=data.name,
        geom=_build_geom(data),
        definition=data.model_dump(mode="json", exclude={"name", "device_id"}),
        alert_on_enter=data.alert_on_enter, alert_on_exit=data.alert_on_exit,
        dwell_seconds=data.dwell_seconds,
        active_from=data.active_from, active_to=data.active_to,
    )
    db.add(fence)
    db.commit()
    return fence


@router.put("/{fence_id}", response_model=GeofenceOut)
def update_geofence(fence_id: int, data: GeofenceCreate,
                    db: Session = Depends(get_db),
                    user: User = Depends(get_current_user)):
    fence = db.get(Geofence, fence_id)
    if fence is None or fence.user_id != user.id:
        raise HTTPException(404, "Nie znaleziono strefy")
    if data.device_id is not None:
        get_own_device(data.device_id, db, user)

    fence.name = data.name
    fence.device_id = data.device_id
    fence.geom = _build_geom(data)
    fence.definition = data.model_dump(mode="json", exclude={"name", "device_id"})
    fence.alert_on_enter = data.alert_on_enter
    fence.alert_on_exit = data.alert_on_exit
    fence.dwell_seconds = data.dwell_seconds
    fence.active_from = data.active_from
    fence.active_to = data.active_to

    db.execute(delete(ZoneState).where(ZoneState.geofence_id == fence_id))
    db.commit()
    return fence


@router.delete("/{fence_id}", status_code=204)
def delete_geofence(fence_id: int, db: Session = Depends(get_db),
                    user: User = Depends(get_current_user)):
    fence = db.get(Geofence, fence_id)
    if fence is None or fence.user_id != user.id:
        raise HTTPException(404, "Nie znaleziono strefy")
    event_ids = select(ZoneEvent.id).where(ZoneEvent.geofence_id == fence_id)
    db.execute(
        delete(Notification).where(Notification.zone_event_id.in_(event_ids)))
    db.delete(fence)
    db.commit()