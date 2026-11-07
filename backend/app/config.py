import os


class Settings:
    """Конфигурация из переменных окружения. Секретов в коде нет."""

    def __init__(self) -> None:
        self.api_token = os.getenv("API_TOKEN") or None            # токен клиента (Bearer); если не задан — открытый доступ (для локальной разработки)
        self.admin_token = os.getenv("ADMIN_TOKEN") or None        # токен для загрузки каталогов
        self.anthropic_key = os.getenv("ANTHROPIC_API_KEY") or None
        self.anthropic_model = os.getenv("ANTHROPIC_MODEL", "claude-sonnet-5-5")
        self.overpass_urls = [u.strip() for u in os.getenv(
            "OVERPASS_URLS",
            "https://overpass-api.de/api/interpreter,https://overpass.kumi.systems/api/interpreter,https://overpass.private.coffee/api/interpreter",
        ).split(",") if u.strip()]
        self.db_path = os.getenv("DB_PATH", "data/backend.db")
        # Nominatim/OFF/Open Prices требуют идентифицирующий User-Agent. Укажите контакт в переменной USER_AGENT.
        self.user_agent = os.getenv("USER_AGENT", "MealPlannerBackend/1.0 (self-hosted; set USER_AGENT with contact)")
        self.open_prices_url = os.getenv("OPEN_PRICES_URL", "https://prices.openfoodfacts.org/api/v1")
        self.off_url = os.getenv("OFF_URL", "https://world.openfoodfacts.org")
        self.cache_ttl_stores = int(os.getenv("CACHE_TTL_STORES", "600"))
        self.cache_ttl_prices = int(os.getenv("CACHE_TTL_PRICES", "3600"))
        self.price_max_age_days = int(os.getenv("PRICE_MAX_AGE_DAYS", "180"))
        self.chain_radius_m = float(os.getenv("CHAIN_RADIUS_M", "15000"))
        self.rate_limit_per_min = int(os.getenv("RATE_LIMIT_PER_MIN", "60"))


def get_settings() -> Settings:
    return Settings()
