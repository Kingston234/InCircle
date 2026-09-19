from datetime import datetime
from fastapi import APIRouter, Depends, Query
from geoalchemy2 import Geography
from sqlalchemy import cast, func, select
from sqlalchemy.dialects.postgresql import aggregate_order_by
from sqlalchemy.orm import Session
from ..auth import get_current_user
from ..config import settings
from ..database import get_db
from ..models import Location, User
from ..schemas import LocationDayOut, LocationOut
from .devices import get_own_device

router = APIRouter(prefix="/devices/{device_id}/locations", tags=["locations"])


def _base_query(device_id: int):
    return select(
        Location.id, Location.recorded_at,
        func.ST_Y(Location.geom).label("lat"),
        func.ST_X(Location.geom).label("lon"),
        Location.speed_kmh, Location.hdop, Location.sats, Location.battery_pct,
    ).where(Location.device_id == device_id)


@router.get("", response_model=list[LocationOut])
def history(device_id: int,
            time_from: datetime | None = Query(default=None, alias="from"),
            time_to: datetime | None = Query(default=None, alias="to"),
            limit: int = Query(default=200, ge=1, le=2000),
            offset: int = Query(default=0, ge=0),
            db: Session = Depends(get_db),
            user: User = Depends(get_current_user)):
    get_own_device(device_id, db, user)
    q = _base_query(device_id)
    if time_from:
        q = q.where(Location.recorded_at >= time_from)
    if time_to:
        q = q.where(Location.recorded_at <= time_to)
    rows = db.execute(
        q.order_by(Location.recorded_at.desc()).limit(limit).offset(offset)
    ).all()
    return [LocationOut(**r._mapping) for r in rows]


@router.get("/days", response_model=list[LocationDayOut])
def days_with_history(device_id: int, db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    get_own_device(device_id, db, user)
    day = func.date(func.timezone(settings.timezone, Location.recorded_at)).label("day")
    track = func.ST_MakeLine(
        aggregate_order_by(Location.geom, Location.recorded_at))
    rows = db.execute(
        select(
            day,
            func.count().label("count"),
            func.coalesce(func.ST_Length(cast(track, Geography)), 0.0)
                .label("distance_m"),
            func.extract("epoch", func.max(Location.recorded_at)
                         - func.min(Location.recorded_at)).label("duration_s"),
            func.max(Location.speed_kmh).label("max_speed_kmh"),
        )
        .where(Location.device_id == device_id)
        .group_by(day)
        .order_by(day.desc())
    ).all()
    return [LocationDayOut(day=r.day, count=r.count,
                           distance_m=float(r.distance_m or 0),
                           duration_s=float(r.duration_s or 0),
                           max_speed_kmh=r.max_speed_kmh)
            for r in rows]


@router.get("/latest", response_model=LocationOut | None)
def latest(device_id: int, db: Session = Depends(get_db),
           user: User = Depends(get_current_user)):
    get_own_device(device_id, db, user)
    row = db.execute(
        _base_query(device_id).order_by(Location.recorded_at.desc()).limit(1)
    ).first()
    return LocationOut(**row._mapping) if row else None