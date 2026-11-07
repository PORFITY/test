"""Поиск продуктовых магазинов вокруг точки через OpenStreetMap (Overpass API) с запасным вариантом Nominatim."""
from __future__ import annotations

import httpx

from .geo import chain_of, haversine_m
from .models import StoreInfo

SHOP_TYPES = "supermarket|convenience|greengrocer|butcher|bakery|general|farm|deli|seafood|health_food|wholesale|grocery|food"


def build_query(lat: float, lon: float, radius_m: int, limit: int = 600) -> str:
    return (
        "[out:json][timeout:25];("
        f'nwr["shop"~"^({SHOP_TYPES})$"](around:{radius_m},{lat},{lon});'
        f'nwr["amenity"="marketplace"](around:{radius_m},{lat},{lon});'
        f");out center tags {limit};"
    )


def _shop_type(tags: dict) -> str:
    shop = tags.get("shop")
    if tags.get("amenity") == "marketplace":
        return "marketplace"
    return {"supermarket": "supermarket", "wholesale": "supermarket", "convenience": "convenience", "general": "convenience", "grocery": "convenience",
            "greengrocer": "greengrocer", "farm": "greengrocer", "butcher": "butcher", "seafood": "butcher", "bakery": "bakery"}.get(shop or "", "convenience")


def _address(tags: dict) -> str | None:
    parts = [tags.get("addr:street"), tags.get("addr:housenumber")]
    street = ", ".join(p for p in parts if p)
    city = tags.get("addr:city")
    full = ", ".join(p for p in [city, street] if p)
    return full or tags.get("addr:full")


def parse_overpass(data: dict, lat: float, lon: float, radius_m: float) -> list[StoreInfo]:
    out: dict[str, StoreInfo] = {}
    for el in data.get("elements", []):
        tags = el.get("tags") or {}
        clat = el.get("lat") if el.get("lat") is not None else (el.get("center") or {}).get("lat")
        clon = el.get("lon") if el.get("lon") is not None else (el.get("center") or {}).get("lon")
        if clat is None or clon is None:
            continue
        dist = haversine_m(lat, lon, clat, clon)
        if dist > radius_m * 1.05:
            continue
        name = tags.get("name") or tags.get("brand") or tags.get("operator") or "Магазин"
        sid = f"osm:{el.get('type')}/{el.get('id')}"
        delivery = tags.get("delivery")
        out[sid] = StoreInfo(
            id=sid, name=name, chain=chain_of(tags.get("brand") or name), address=_address(tags), lat=clat, lon=clon, distanceM=round(dist, 1),
            shopType=_shop_type(tags), openingHours=tags.get("opening_hours"),
            delivery=True if delivery == "yes" else (False if delivery == "no" else None), source="osm",
        )
    return sorted(out.values(), key=lambda s: s.distanceM)


def parse_nominatim(data: list, lat: float, lon: float, radius_m: float) -> list[StoreInfo]:
    out = []
    for r in data:
        try:
            clat, clon = float(r["lat"]), float(r["lon"])
        except (KeyError, ValueError):
            continue
        d = haversine_m(lat, lon, clat, clon)
        if d > radius_m * 1.05:
            continue
        name = r.get("name") or (r.get("display_name") or "Магазин").split(",")[0]
        out.append(StoreInfo(id=f"osm:{r.get('osm_type')}/{r.get('osm_id')}", name=name, chain=chain_of(name), address=r.get("display_name"),
                             lat=clat, lon=clon, distanceM=round(d, 1), shopType="supermarket", source="osm"))
    return sorted(out, key=lambda s: s.distanceM)


async def fetch_nearby(client: httpx.AsyncClient, urls: list[str], lat: float, lon: float, radius_m: int, nominatim_url: str = "https://nominatim.openstreetmap.org") -> tuple[list[StoreInfo], str]:
    """Пробует зеркала Overpass по очереди; при отказе всех — Nominatim (до 40 результатов). Возвращает (магазины, источник)."""
    q = build_query(lat, lon, radius_m)
    last_err: Exception | None = None
    for url in urls:
        try:
            r = await client.post(url, data={"data": q}, timeout=30)
            r.raise_for_status()
            return parse_overpass(r.json(), lat, lon, radius_m), "overpass"
        except (httpx.HTTPError, ValueError) as e:
            last_err = e
    # запасной вариант: Nominatim с ограничением по рамке
    dlat = radius_m / 111_320
    dlon = radius_m / (111_320 * max(0.1, abs(__import__("math").cos(__import__("math").radians(lat)))))
    try:
        r = await client.get(f"{nominatim_url}/search", params={
            "q": "supermarket", "format": "jsonv2", "limit": 40, "bounded": 1,
            "viewbox": f"{lon - dlon},{lat + dlat},{lon + dlon},{lat - dlat}"}, timeout=20)
        r.raise_for_status()
        return parse_nominatim(r.json(), lat, lon, radius_m), "nominatim"
    except (httpx.HTTPError, ValueError) as e:
        raise RuntimeError(f"Источники карт недоступны: {last_err or e}") from e
