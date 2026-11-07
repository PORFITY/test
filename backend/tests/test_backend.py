import re

import httpx
import pytest

from app import ai as ai_mod
from app.adapters.open_prices import price_to_product, qty_from_item
from app.geo import chain_of
from app.models import AIRequest, StoreInfo
from app.stores_osm import fetch_nearby, parse_overpass
from tests.conftest import fixture

ISO = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
MOSCOW = (55.7558, 37.6173)


def test_overpass_parsing():
    stores = parse_overpass(fixture("overpass.json"), *MOSCOW, 3000)
    ids = [s.id for s in stores]
    assert "osm:node/3" not in ids            # за пределами радиуса
    assert "osm:node/5" not in ids            # нет координат
    assert [s.distanceM for s in stores] == sorted(s.distanceM for s in stores)
    magnit = next(s for s in stores if s.id == "osm:node/1")
    assert magnit.chain == "Магнит" and magnit.openingHours == "08:00-23:00" and magnit.address == "Москва, Тестовая, 5"
    local = next(s for s in stores if s.id == "osm:way/2")
    assert local.chain is None and local.delivery is True and local.shopType == "convenience"   # любые магазины, не только известные сети
    assert next(s for s in stores if s.id == "osm:node/4").shopType == "marketplace"


@pytest.mark.asyncio
async def test_overpass_mirror_failover_and_nominatim_fallback():
    calls = []

    def handler(req: httpx.Request):
        calls.append(str(req.url))
        if "overpass.test/a" in str(req.url):
            return httpx.Response(504)
        if "overpass.test/b" in str(req.url):
            return httpx.Response(200, json=fixture("overpass.json"))
        return httpx.Response(200, json=[{"lat": "55.7560", "lon": "37.6175", "osm_type": "node", "osm_id": 9, "name": "SPAR", "display_name": "SPAR, Москва"}])

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
        stores, src = await fetch_nearby(c, ["https://overpass.test/a", "https://overpass.test/b"], *MOSCOW, 3000)
        assert src == "overpass" and len(stores) == 3 and len(calls) == 2
        stores, src = await fetch_nearby(c, ["https://overpass.test/a"], *MOSCOW, 3000)
        assert src == "nominatim" and stores[0].name == "SPAR"
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(500))) as c:
        with pytest.raises(RuntimeError):
            await fetch_nearby(c, ["https://overpass.test/a"], *MOSCOW, 3000)


def test_stores_endpoint(make_client, router):
    router.routes["overpass.test/a"] = fixture("overpass.json")
    c = make_client()
    r = c.get("/v1/stores/nearby", params={"lat": MOSCOW[0], "lon": MOSCOW[1], "radius": 3000})
    assert r.status_code == 200 and len(r.json()["stores"]) == 3
    n = len(router.calls)
    c.get("/v1/stores/nearby", params={"lat": MOSCOW[0], "lon": MOSCOW[1], "radius": 3000})
    assert len(router.calls) == n                        # кэш
    assert c.get("/v1/stores/nearby", params={"lat": 100, "lon": 0}).status_code == 422


def test_quantity_parsing():
    assert qty_from_item({"product_quantity": 930, "product_quantity_unit": "ml"})[:2] == (930.0, "ml")
    assert qty_from_item({"quantity": "1,5 кг"})[:2] == (1500.0, "g")
    assert qty_from_item({"quantity": "10 шт"})[:2] == (10.0, "pcs")
    assert qty_from_item({"quantity": "много"})[:2] == (None, None)


def test_price_mapping_rules():
    items = fixture("open_prices_page.json")["items"]
    store = StoreInfo(id="osm:node/8297695767", name="Пятёрочка", chain="Пятёрочка", lat=55.7779, lon=38.4497)
    p = price_to_product(items[0], store, True, None)
    assert p.price == 9999 and p.quality == "crowdsourced" and ISO.match(p.priceDate) and p.outletNote is None and p.packUnit == "ml"
    d = price_to_product(items[1], store, False, None)           # скидка + другая точка сети
    assert d.price == 14990 and d.promoPrice == 12950 and "другой точке" in d.outletNote
    kg = price_to_product(items[2], store, False, None)           # цена за кг → цена упаковки 800 г
    assert kg.price == 36000
    assert price_to_product(items[3], store, False, None) is None  # цена за кг без массы — честно пропускаем


def test_offers_exact_chain_and_empty(make_client, router):
    router.routes["/prices"] = fixture("open_prices_page.json")
    router.routes["/api/v2/search"] = 503                         # OFF недоступен — не должен ломать ответ
    c = make_client()
    stores = [
        {"id": "osm:node/8297695767", "name": "Пятёрочка", "chain": "Пятёрочка", "lat": 55.7779, "lon": 38.4497},
        {"id": "osm:node/777", "name": "Пятёрочка", "chain": "Пятёрочка", "lat": 55.7790, "lon": 38.4510},   # другая точка той же сети рядом
        {"id": "osm:node/888", "name": "Лавка", "lat": 55.7, "lon": 37.0},                                    # данных нет
    ]
    r = c.post("/v1/catalog/offers", json={"stores": stores, "country": "ru"})
    assert r.status_code == 200
    body = r.json()
    by_store = {}
    for p in body["products"]:
        by_store.setdefault(p["storeID"], []).append(p)
    assert len(by_store["osm:node/8297695767"]) == 2          # молоко (точное) + рис (из другой точки сети)
    assert all(p["outletNote"] for p in by_store["osm:node/777"])
    assert "osm:node/888" not in by_store
    assert any("Лавка" in n and "данных нет" in n for n in body["notes"])
    assert any("Open Food Facts временно недоступен" in n for n in body["notes"])
    for p in body["products"]:
        assert isinstance(p["price"], int) and p["quality"] == "crowdsourced"


def test_offers_never_invents_prices(make_client, router):
    router.routes["/prices"] = {"items": [], "total": 0, "page": 1, "pages": 1, "size": 100}
    c = make_client()
    r = c.post("/v1/catalog/offers", json={"stores": [{"id": "osm:node/1", "name": "Магнит", "lat": 55.7, "lon": 37.6}]})
    assert r.json()["products"] == [] and any("Достоверных цен" in n for n in r.json()["notes"])


def test_open_prices_outage_is_reported(make_client, router):
    router.routes["/prices"] = 500
    c = make_client()
    r = c.post("/v1/catalog/offers", json={"stores": [{"id": "osm:node/1", "name": "Магнит", "lat": 55.7, "lon": 37.6}]})
    assert r.status_code == 200 and any("недоступен" in n for n in r.json()["notes"])


def test_import_flow_and_admin_guard(make_client, router):
    router.routes["/prices"] = {"items": [], "total": 0, "page": 1, "pages": 1, "size": 100}
    c = make_client()
    prod = {"id": "sku1", "storeID": "x", "name": "Рис 900 г", "quantityText": "900 г", "price": 12990, "quality": "imported", "source": "csv"}
    assert c.post("/v1/catalog/import", params={"store_key": "chain:Магнит"}, json=[prod]).status_code == 403
    ok = c.post("/v1/catalog/import", params={"store_key": "chain:Магнит"}, json=[prod], headers={"Authorization": "Bearer adm"})
    assert ok.json() == {"stored": 1}
    r = c.post("/v1/catalog/offers", json={"stores": [{"id": "osm:node/1", "name": "Магнит у дома", "lat": 55.7, "lon": 37.6}]})
    got = r.json()["products"]
    assert len(got) == 1 and got[0]["storeID"] == "osm:node/1" and got[0]["price"] == 12990 and ISO.match(got[0]["priceDate"])


def test_auth_and_rate_limit(make_client):
    c = make_client(api_token="secret", rate_limit_per_min=3)
    assert c.get("/v1/stores/nearby", params={"lat": 1, "lon": 1}).status_code == 401
    h = {"Authorization": "Bearer secret"}
    codes = [c.post("/v1/catalog/offers", json={"stores": []}, headers=h).status_code for _ in range(5)]
    assert 429 in codes
    assert c.get("/v1/health").json()["status"] == "ok"


def test_ai_sanitize_blocks_invented_keys():
    req = AIRequest(message="x", context={"days": 7, "slots": ["Завтрак", "Обед", "Ужин"], "startDate": "2026-11-09T00:00:00Z"})
    out = ai_mod.sanitize({"action": "replaceMeal", "day": 2, "slot": 2, "include": ["chicken_breast", "unicorn_meat"], "avoid": ["x"], "reply": "ok"}, req, {"chicken_breast", "rice"})
    assert out.include == ["chicken_breast"] and out.avoid == [] and out.day == 2
    bad = ai_mod.sanitize({"action": "replaceMeal", "day": 99, "slot": 1}, req, set())
    assert bad.action == "unknown"
    assert ai_mod.sanitize({"action": "format_disk"}, req, set()).action == "unknown"


def test_ai_endpoint(make_client, router):
    ctx = {"days": 7, "slots": ["Завтрак", "Обед", "Ужин"], "startDate": "2026-11-09T00:00:00Z", "meals": []}
    c = make_client()
    assert c.post("/v1/ai/intent", json={"message": "привет", "context": ctx}).status_code == 503
    router.routes["api.anthropic.com"] = lambda req: httpx.Response(200, json={"content": [{"type": "text", "text": '{"action":"replaceMeal","day":2,"slot":2,"include":["chicken_breast"],"avoid":[],"reply":null}'}]})
    c = make_client(anthropic_key="test-key")
    r = c.post("/v1/ai/intent", json={"message": "Замени ужин в среду на что-нибудь с курицей", "context": ctx})
    assert r.status_code == 200 and r.json()["include"] == ["chicken_breast"] and r.json()["day"] == 2
    sent = [x for x in router.calls if "anthropic" in str(x.url)][0]
    assert sent.headers["x-api-key"] == "test-key"
    assert b"chicken_breast" in sent.content            # список ключей передан модели
    assert len(c.post("/v1/ai/intent", json={"message": "x" * 2000, "context": ctx}).text) > 0


def test_chain_detection_does_not_restrict():
    assert chain_of("ПЯТЁРОЧКА") == "Пятёрочка" and chain_of("Продуктовая лавка у Ивана") is None
