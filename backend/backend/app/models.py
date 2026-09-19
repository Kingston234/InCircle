from datetime import datetime, time
from geoalchemy2 import Geometry
from sqlalchemy import (BigInteger, Boolean, DateTime, Float, ForeignKey, Integer, SmallInteger, Text, Time, func)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .database import Base


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    email: Mapped[str] = mapped_column(Text, unique=True)
    password_hash: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now())

    devices: Mapped[list["Device"]] = relationship(back_populates="owner")


class Device(Base):
    __tablename__ = "devices"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    device_key: Mapped[str] = mapped_column(Text, unique=True)
    name: Mapped[str] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_online: Mapped[bool] = mapped_column(Boolean, default=False)
    config: Mapped[dict | None] = mapped_column(JSONB)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now())

    owner: Mapped["User"] = relationship(back_populates="devices")


class Location(Base):
    __tablename__ = "locations"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    device_id: Mapped[int] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"))
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    geom = mapped_column(Geometry(geometry_type="POINT", srid=4326))
    speed_kmh: Mapped[float | None] = mapped_column(Float)
    hdop: Mapped[float | None] = mapped_column(Float)
    sats: Mapped[int | None] = mapped_column(SmallInteger)
    battery_pct: Mapped[int | None] = mapped_column(SmallInteger)


class Geofence(Base):
    __tablename__ = "geofences"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    device_id: Mapped[int | None] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(Text)
    geom = mapped_column(Geometry(geometry_type="POLYGON", srid=4326))
    definition: Mapped[dict] = mapped_column(JSONB)
    alert_on_enter: Mapped[bool] = mapped_column(Boolean, default=True)
    alert_on_exit: Mapped[bool] = mapped_column(Boolean, default=True)
    dwell_seconds: Mapped[int] = mapped_column(Integer, default=0)
    active_from: Mapped[time | None] = mapped_column(Time)
    active_to: Mapped[time | None] = mapped_column(Time)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class ZoneState(Base):
    __tablename__ = "zone_states"
    device_id: Mapped[int] = mapped_column(
        ForeignKey("devices.id", ondelete="CASCADE"), primary_key=True)
    geofence_id: Mapped[int] = mapped_column(
        ForeignKey("geofences.id", ondelete="CASCADE"), primary_key=True)
    is_inside: Mapped[bool] = mapped_column(Boolean, default=False)
    candidate_inside: Mapped[bool | None] = mapped_column(Boolean)
    candidate_count: Mapped[int] = mapped_column(SmallInteger, default=0)
    candidate_since: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now())


class ZoneEvent(Base):
    __tablename__ = "zone_events"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    device_id: Mapped[int] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"))
    geofence_id: Mapped[int] = mapped_column(ForeignKey("geofences.id", ondelete="CASCADE"))
    event_type: Mapped[str] = mapped_column(Text)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    location_id: Mapped[int | None] = mapped_column(ForeignKey("locations.id", ondelete="SET NULL"))


class Notification(Base):
    __tablename__ = "notifications"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    zone_event_id: Mapped[int | None] = mapped_column(ForeignKey("zone_events.id", ondelete="SET NULL"))
    title: Mapped[str] = mapped_column(Text)
    body: Mapped[str] = mapped_column(Text)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now())


class PushToken(Base):
    __tablename__ = "push_tokens"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    token: Mapped[str] = mapped_column(Text, unique=True)
    platform: Mapped[str | None] = mapped_column(Text)