from dataclasses import dataclass
from datetime import datetime, time
from zoneinfo import ZoneInfo


@dataclass
class HysteresisState:
    is_inside: bool = False
    candidate_inside: bool | None = None
    candidate_count: int = 0
    candidate_since: datetime | None = None


def advance_state(state: HysteresisState,
                  raw_inside: bool,
                  raw_outside: bool,
                  now: datetime,
                  confirm_samples: int,
                  dwell_seconds: int = 0) -> str | None:
    if state.is_inside:
        target, trigger = False, raw_outside
    else:
        target, trigger = True, raw_inside

    if not trigger:
        state.candidate_inside = None
        state.candidate_count = 0
        state.candidate_since = None
        return None

    if state.candidate_inside == target:
        state.candidate_count += 1
    else:
        state.candidate_inside = target
        state.candidate_count = 1
        state.candidate_since = now

    confirmed = state.candidate_count >= confirm_samples
    if confirmed and target and dwell_seconds > 0:
        confirmed = (now - state.candidate_since).total_seconds() >= dwell_seconds

    if not confirmed:
        return None

    state.is_inside = target
    state.candidate_inside = None
    state.candidate_count = 0
    state.candidate_since = None
    return "ENTER" if target else "EXIT"


def in_time_window(t: time, start: time | None, end: time | None) -> bool:
    if start is None or end is None:
        return True
    if start <= end:
        return start <= t <= end
    return t >= start or t <= end


def process_location(db, device, location) -> list:
    from sqlalchemy import cast, func, or_, select
    from geoalchemy2 import Geography

    from .config import settings
    from .models import Geofence, ZoneEvent, ZoneState

    pt = location.geom
    pt_geog = cast(pt, Geography)

    rows = db.execute(
        select(
            Geofence,
            func.ST_Contains(Geofence.geom, pt).label("raw_inside"),
            func.ST_DWithin(cast(Geofence.geom, Geography), pt_geog,
                            settings.hysteresis_buffer_m).label("near"),
        ).where(
            Geofence.user_id == device.user_id,
            Geofence.is_active.is_(True),
            or_(Geofence.device_id.is_(None), Geofence.device_id == device.id),
        )
    ).all()

    now = location.recorded_at
    local_t = now.astimezone(ZoneInfo(settings.timezone)).time()
    events: list[ZoneEvent] = []

    for fence, raw_inside, near in rows:
        raw_outside = not near
        zs = db.get(ZoneState, (device.id, fence.id))
        if zs is None:
            zs = ZoneState(device_id=device.id, geofence_id=fence.id,
                           is_inside=False, candidate_count=0)
            db.add(zs)

        st = HysteresisState(zs.is_inside, zs.candidate_inside,
                             zs.candidate_count, zs.candidate_since)
        transition = advance_state(st, bool(raw_inside), bool(raw_outside), now,
                                   settings.confirm_samples, fence.dwell_seconds)

        zs.is_inside = st.is_inside
        zs.candidate_inside = st.candidate_inside
        zs.candidate_count = st.candidate_count
        zs.candidate_since = st.candidate_since
        zs.updated_at = now

        if transition is None:
            continue
        wanted = fence.alert_on_enter if transition == "ENTER" else fence.alert_on_exit
        if not wanted or not in_time_window(local_t, fence.active_from, fence.active_to):
            continue

        ev = ZoneEvent(device_id=device.id, geofence_id=fence.id,
                       event_type=transition, occurred_at=now,
                       location_id=location.id)
        db.add(ev)
        ev.geofence_name = fence.name
        events.append(ev)

    return events