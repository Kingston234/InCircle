from datetime import date, datetime, time
from typing import Literal
from pydantic import BaseModel, EmailStr, Field


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: int
    email: str
    model_config = {"from_attributes": True}


class DeviceCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class DeviceClaim(BaseModel):
    device_key: str = Field(min_length=6, max_length=64,
                            pattern=r"^[A-Za-z0-9_-]+$")
    name: str = Field(min_length=1, max_length=100)


class DeviceConfigIn(BaseModel):
    report_interval_s: int = Field(ge=5, le=3600)


class DeviceOut(BaseModel):
    id: int
    device_key: str
    name: str
    is_active: bool
    is_online: bool
    battery_pct: int | None = None
    config: dict | None = None
    last_seen_at: datetime | None
    model_config = {"from_attributes": True}


class LocationOut(BaseModel):
    id: int
    recorded_at: datetime
    lat: float
    lon: float
    speed_kmh: float | None
    hdop: float | None
    sats: int | None
    battery_pct: int | None


class GeofenceCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    device_id: int | None = None
    type: Literal["circle", "polygon"]
    center_lat: float | None = None
    center_lon: float | None = None
    radius_m: float | None = Field(default=None, gt=0, le=100_000)
    polygon: list[list[float]] | None = None
    alert_on_enter: bool = True
    alert_on_exit: bool = True
    dwell_seconds: int = Field(default=0, ge=0, le=86_400)
    active_from: time | None = None
    active_to: time | None = None


class GeofenceOut(BaseModel):
    id: int
    name: str
    device_id: int | None
    definition: dict
    alert_on_enter: bool
    alert_on_exit: bool
    dwell_seconds: int
    active_from: time | None
    active_to: time | None
    is_active: bool
    model_config = {"from_attributes": True}


class LocationDayOut(BaseModel):
    day: date
    count: int
    distance_m: float = 0
    duration_s: float = 0
    max_speed_kmh: float | None = None


class ZoneEventOut(BaseModel):
    id: int
    device_id: int
    device_name: str
    geofence_id: int
    geofence_name: str
    event_type: str
    occurred_at: datetime


class NotificationOut(BaseModel):
    id: int
    title: str
    body: str
    zone_event_id: int | None
    created_at: datetime
    model_config = {"from_attributes": True}


class PushTokenIn(BaseModel):
    token: str = Field(min_length=10)
    platform: str | None = None