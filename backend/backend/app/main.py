import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from .database import engine
from .mqtt_client import start_mqtt
from .routers import auth_router, devices, events, geofences, locations

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s [%(name)s] %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    with engine.begin() as conn:
        conn.execute(text(
            "ALTER TABLE devices ADD COLUMN IF NOT EXISTS config JSONB"))
        conn.execute(text(
            "DELETE FROM notifications "
            "WHERE zone_event_id IS NULL AND title LIKE '%strefy%'"))
    mqtt_client = start_mqtt()
    yield
    mqtt_client.loop_stop()
    mqtt_client.disconnect()


app = FastAPI(title="GPS Tracker API", version="1.0.0", lifespan=lifespan)

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"],
                   allow_headers=["*"])

app.include_router(auth_router.router)
app.include_router(devices.router)
app.include_router(locations.router)
app.include_router(geofences.router)
app.include_router(events.router)


@app.get("/health", tags=["misc"])
def health():
    return {"status": "ok"}