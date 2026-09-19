CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE users (
    id            BIGSERIAL PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE devices (
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_key   TEXT NOT NULL UNIQUE,   -- identyfikator w topicu MQTT: devices/<device_key>/location
    name         TEXT NOT NULL,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    is_online    BOOLEAN NOT NULL DEFAULT FALSE,  -- aktualizowane z topicu statusu (LWT)
    config       JSONB,                           -- zdalna konfiguracja (np. interwał raportowania)
    last_seen_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_devices_user ON devices (user_id);

CREATE TABLE locations (
    id          BIGSERIAL PRIMARY KEY,
    device_id   BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    recorded_at TIMESTAMPTZ NOT NULL,             -- czas pomiaru z GPS
    geom        geometry(Point, 4326) NOT NULL,   -- WGS84: POINT(lon lat)
    speed_kmh   REAL,
    hdop        REAL,
    sats        SMALLINT,
    battery_pct SMALLINT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_locations_device_time ON locations (device_id, recorded_at DESC);
CREATE INDEX idx_locations_geom ON locations USING GIST (geom);

CREATE TABLE geofences (
    id             BIGSERIAL PRIMARY KEY,
    user_id        BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id      BIGINT REFERENCES devices(id) ON DELETE CASCADE,
    name           TEXT NOT NULL,
    geom           geometry(Polygon, 4326) NOT NULL,
    definition     JSONB NOT NULL,
    alert_on_enter BOOLEAN NOT NULL DEFAULT TRUE,
    alert_on_exit  BOOLEAN NOT NULL DEFAULT TRUE,
    dwell_seconds  INT NOT NULL DEFAULT 0,
    active_from    TIME,
    active_to      TIME,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_geofences_user ON geofences (user_id);
CREATE INDEX idx_geofences_geom ON geofences USING GIST (geom);

CREATE TABLE zone_states (
    device_id       BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    geofence_id     BIGINT NOT NULL REFERENCES geofences(id) ON DELETE CASCADE,
    is_inside       BOOLEAN NOT NULL DEFAULT FALSE,
    candidate_inside BOOLEAN,          -- kandydat na nowy stan (potwierdzany kolejnymi próbkami)
    candidate_count SMALLINT NOT NULL DEFAULT 0,
    candidate_since TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (device_id, geofence_id)
);

CREATE TABLE zone_events (
    id          BIGSERIAL PRIMARY KEY,
    device_id   BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    geofence_id BIGINT NOT NULL REFERENCES geofences(id) ON DELETE CASCADE,
    event_type  TEXT NOT NULL CHECK (event_type IN ('ENTER', 'EXIT')),
    occurred_at TIMESTAMPTZ NOT NULL,
    location_id BIGINT REFERENCES locations(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_zone_events_device_time ON zone_events (device_id, occurred_at DESC);

CREATE TABLE notifications (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    zone_event_id BIGINT REFERENCES zone_events(id) ON DELETE SET NULL,
    title         TEXT NOT NULL,
    body          TEXT NOT NULL,
    sent_at       TIMESTAMPTZ,          -- kiedy wysłano push (NULL = nie wysłano)
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user ON notifications (user_id, created_at DESC);

CREATE TABLE push_tokens (
    id         BIGSERIAL PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token      TEXT NOT NULL UNIQUE,
    platform   TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
