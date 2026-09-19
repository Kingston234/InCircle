from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg2://gps:gps@localhost:5432/gpstracker"

    mqtt_host: str = "localhost"
    mqtt_port: int = 1883
    mqtt_username: str = "backend"
    mqtt_password: str = ""

    jwt_secret: str = "dev-insecure-zmien-mnie"
    jwt_expires_min: int = 60 * 24 * 7

    hysteresis_buffer_m: float = 30.0
    confirm_samples: int = 3
    max_hdop: float = 5.0
    min_sats: int = 4
    max_jump_speed_kmh: float = 200.0
    low_battery_pct: int = 20
    timezone: str = "Europe/Warsaw"

    fcm_credentials_file: str = ""

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()