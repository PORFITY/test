from __future__ import annotations

import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Request

from . import ai as ai_mod
from .adapters.base import CatalogAdapter
from .adapters.imported import ImportedAdapter
from .adapters.open_prices import OpenPricesAdapter
from .config import Settings, get_settings
from .db import Db
from .models import AIRequest, AssistantIntent, CatalogProduct, OffersRequest, OffersResponse, StoreInfo, StoresResponse
from .stores_osm import fetch_nearby

INGREDIENTS_PATH = Path(__file__).resolve().parents[2] / "ios/MealCore/Sources/MealCore/Resources/ingredients.json"


def build_adapters(client: httpx.AsyncClient, db: Db, s: Settings) -> list[CatalogAdapter]:
    # Порядок = приоритет. Чтобы подключить новую сеть, добавьте её адаптер сюда (см. adapters/chain_template.py).
    return [ImportedAdapter(db), OpenPricesAdapter(client, db, s)]


def create_app(settings: Settings | None = None, client: httpx.AsyncClient | None = None, db: Db | None = None) -> FastAPI:
    s = settings or get_settings()
    _db = db or Db(s.db_path)
    state: dict = {"client": client, "stores_cache": {}, "hits": defaultdict(deque)}

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if state["client"] is None:
            state["client"] = httpx.AsyncClient(headers={"User-Agent": s.user_agent}, follow_redirects=True)
        state["adapters"] = build_adapters(state["client"], _db, s)
        yield
        if client is None:
            await state["client"].aclose()

    app = FastAPI(title="MealPlanner backend", version="1.0.0", lifespan=lifespan)
    if client is not None:        # тесты: адаптеры создаются сразу
        state["adapters"] = build_adapters(client, _db, s)

    def auth(request: Request, authorization: str | None = Header(default=None)) -> None:
        if s.api_token and authorization != f"Bearer {s.api_token}":
            raise HTTPException(401, "invalid token")
        key = request.client.host if request.client else "anon"
        q = state["hits"][key]
        now = time.time()
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) >= s.rate_limit_per_min:
            raise HTTPException(429, "rate limit")
        q.append(now)

    def admin(authorization: str | None = Header(default=None)) -> None:
        if not s.admin_token or authorization != f"Bearer {s.admin_token}":
            raise HTTPException(403, "admin token required")

    @app.get("/v1/health")
    async def health():
        return {"status": "ok", "adapters": [a.name for a in state["adapters"]], "ai": bool(s.anthropic_key), "auth": bool(s.api_token)}

    @app.get("/v1/stores/nearby", response_model=StoresResponse, dependencies=[Depends(auth)])
    async def nearby(lat: float, lon: float, radius: int = 3000):
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise HTTPException(422, "bad coordinates")
        radius = max(100, min(radius, 50_000))
        ck = (round(lat, 3), round(lon, 3), radius)
        hit = state["stores_cache"].get(ck)
        if hit and time.time() - hit[0] < s.cache_ttl_stores:
            return StoresResponse(stores=hit[1])
        try:
            stores, _src = await fetch_nearby(state["client"], s.overpass_urls, lat, lon, radius)
        except RuntimeError as e:
            raise HTTPException(502, str(e))
        # отметим магазины, для которых есть загруженный каталог
        for st in stores:
            keys = [st.id] + ([f"chain:{st.chain}"] if st.chain else [])
            if _db.imported_for(keys):
                st.catalog = "imported"
        state["stores_cache"][ck] = (time.time(), stores)
        return StoresResponse(stores=stores)

    @app.post("/v1/catalog/offers", response_model=OffersResponse, dependencies=[Depends(auth)])
    async def offers(req: OffersRequest):
        if len(req.stores) > 200:
            raise HTTPException(422, "too many stores")
        out = OffersResponse(products=[])
        for adapter in state["adapters"]:
            try:
                r = await adapter.products_for(req.stores, req.country)
            except Exception as e:           # один источник не должен ронять остальные
                out.notes.append(f"Источник «{adapter.name}» недоступен: {type(e).__name__}")
                continue
            out.products += r.products
            out.notes += r.notes
        if not out.products:
            out.notes.append("Достоверных цен по выбранным магазинам нет. Загрузите прайс магазина (CSV/JSON), введите цены вручную или включите расчёт по ориентирам (с пометкой).")
        return out

    @app.post("/v1/catalog/import", dependencies=[Depends(admin)])
    async def import_catalog(store_key: str, products: list[CatalogProduct]):
        """store_key: id магазина (например osm:node/123) или `chain:Название сети`."""
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        rows = []
        for p in products:
            d = p.model_dump()
            d["quality"] = d.get("quality") or "imported"
            d["priceDate"] = d.get("priceDate") or now
            rows.append(d)
        return {"stored": _db.replace_import(store_key, rows, now)}

    @app.post("/v1/ai/intent", response_model=AssistantIntent, dependencies=[Depends(auth)])
    async def ai_intent(req: AIRequest):
        if not s.anthropic_key:
            raise HTTPException(503, "ai_disabled")
        try:
            keys = ai_mod.load_ingredient_keys(str(INGREDIENTS_PATH))
            return await ai_mod.ask(state["client"], s, req, keys)
        except (httpx.HTTPError, ValueError) as e:
            raise HTTPException(502, f"ai_unavailable: {type(e).__name__}")

    return app


def get_app() -> FastAPI:     # uvicorn app.main:get_app --factory
    return create_app()
