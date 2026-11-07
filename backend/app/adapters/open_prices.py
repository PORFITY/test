"""Адаптер Open Prices (Open Food Facts): реальные цены, загруженные людьми по фото чеков/ценников. Открытые данные (ODbL).

Важно: покрытие неполное и разреженное — в рублях на весь мир сейчас порядка сотен записей. Адаптер честно возвращает только то,
что есть, помечает цены как `crowdsourced` с датой и (если цена взята в другой точке сети) указывает это в `outletNote`.
"""
from __future__ import annotations

import re
import time
from datetime import datetime, timedelta, timezone
from typing import Callable

import httpx

from ..config import Settings
from ..db import Db
from ..geo import chain_of, haversine_m, normalize
from ..models import CatalogProduct, Nutrition, StoreInfo, iso
from .base import AdapterResult

CURRENCY = {"ru": "RUB", "by": "BYN", "kz": "KZT", "ua": "UAH", "us": "USD", "de": "EUR", "fr": "EUR", "gb": "GBP"}
OFF_FIELDS = "code,product_name,brands,quantity,ingredients_text,allergens_tags,traces_tags,nutriments,image_front_small_url,categories_tags"


def parse_osm_id(store_id: str) -> tuple[str, int] | None:
    m = re.match(r"^osm:(node|way|relation)/(\d+)$", store_id)
    return (m.group(1).upper(), int(m.group(2))) if m else None


def qty_from_item(product: dict | None) -> tuple[float | None, str | None, str | None]:
    """(размер, единица g|ml|pcs, текст). Единицы из product_quantity_unit, иначе из текста quantity."""
    if not product:
        return None, None, None
    q, u = product.get("product_quantity"), (product.get("product_quantity_unit") or "").lower()
    text = product.get("quantity")
    if q and u in ("g", "ml"):
        return float(q), u, f"{q:g} {u}"
    if q and u in ("kg", "l"):
        return float(q) * 1000, "g" if u == "kg" else "ml", f"{q:g} {u}"
    if text:
        t = text.lower().replace(",", ".")
        m = re.search(r"(\d+(?:\.\d+)?)\s*(кг|kg|гр|г|g|мл|ml|л|l|шт|pcs)\b", t)
        if m:
            v, un = float(m.group(1)), m.group(2)
            if un in ("кг", "kg"): return v * 1000, "g", text
            if un in ("г", "гр", "g"): return v, "g", text
            if un in ("л", "l"): return v * 1000, "ml", text
            if un in ("мл", "ml"): return v, "ml", text
            return v, "pcs", text
    return None, None, text


def price_to_product(item: dict, store: StoreInfo, exact: bool, off: dict | None) -> CatalogProduct | None:
    product = item.get("product") or {}
    code = item.get("product_code") or product.get("code")
    if not code or item.get("price") is None:
        return None
    size, unit, qtext = qty_from_item(product)
    price = float(item["price"])
    if item.get("price_per") == "KILOGRAM":
        if size is None or unit != "g":
            return None                      # цена за кг без известной массы упаковки — пересчитать честно нельзя
        price = price * size / 1000
    regular, promo = price, None
    if item.get("price_is_discounted") and item.get("price_without_discount"):
        regular, promo = float(item["price_without_discount"]), price
    name = product.get("product_name") or (off or {}).get("product_name")
    if not name:
        return None
    brand = product.get("brands") or (off or {}).get("brands")
    loc = item.get("location") or {}
    note = None
    if not exact:
        note = f"Цена с чека в другой точке сети «{loc.get('osm_brand') or loc.get('osm_name')}»" + (f", {loc['osm_address_city']}" if loc.get("osm_address_city") else "")
    n100 = None
    nm = (off or {}).get("nutriments") or {}
    if "energy-kcal_100g" in nm:
        n100 = Nutrition(kcal=nm.get("energy-kcal_100g", 0), protein=nm.get("proteins_100g", 0), fat=nm.get("fat_100g", 0), carbs=nm.get("carbohydrates_100g", 0))
    date = None
    if item.get("date"):
        try:
            date = datetime.fromisoformat(item["date"]).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return CatalogProduct(
        id=f"openprices:{store.id}:{code}", storeID=store.id, name=f"{name} {qtext or ''}".strip() if qtext and qtext not in name else name, brand=brand,
        category=(product.get("categories_tags") or [None])[0], imageURL=(off or {}).get("image_front_small_url") or product.get("image_url"),
        url=f"https://prices.openfoodfacts.org/products/{code}", quantityText=qtext, packSize=size, packUnit=unit,
        price=int(round(regular * 100)), promoPrice=int(round(promo * 100)) if promo else None, discountText="Скидка по чеку" if promo else None,
        inStock=None, ingredientsText=(off or {}).get("ingredients_text") or None,
        allergenTags=list((off or {}).get("allergens_tags") or []), traceTags=list((off or {}).get("traces_tags") or []),
        nutritionPer100=n100, priceDate=iso(date), quality="crowdsourced", source="open-prices", outletNote=note,
    )


class OpenPricesAdapter:
    name = "open-prices"

    def __init__(self, client: httpx.AsyncClient, db: Db, settings: Settings, clock: Callable[[], float] = time.time) -> None:
        self.client, self.db, self.s, self.clock = client, db, settings, clock
        self._cache: dict[str, tuple[float, list[dict]]] = {}

    async def _all_prices(self, currency: str) -> list[dict]:
        now = self.clock()
        hit = self._cache.get(currency)
        if hit and now - hit[0] < self.s.cache_ttl_prices:
            return hit[1]
        since = (datetime.now(timezone.utc) - timedelta(days=self.s.price_max_age_days)).date().isoformat()
        items: list[dict] = []
        page = 1
        while page <= 30:
            r = await self.client.get(f"{self.s.open_prices_url}/prices", params={"currency": currency, "size": 100, "page": page, "order_by": "-date", "date__gte": since}, timeout=30)
            r.raise_for_status()
            d = r.json()
            items += d.get("items", [])
            if page >= int(d.get("pages", 1)):
                break
            page += 1
        self._cache[currency] = (now, items)
        return items

    async def _enrich(self, codes: list[str]) -> tuple[dict[str, dict], str | None]:
        now = self.clock()
        out: dict[str, dict] = {}
        missing: list[str] = []
        for c in codes:
            cached = self.db.off_get(c, 30 * 86400, now)
            (out.__setitem__(c, cached) if cached is not None else missing.append(c))
        err = None
        for i in range(0, len(missing), 50):
            batch = missing[i:i + 50]
            try:
                r = await self.client.get(f"{self.s.off_url}/api/v2/search", params={"code": ",".join(batch), "fields": OFF_FIELDS, "page_size": 50}, timeout=30)
                r.raise_for_status()
                for p in r.json().get("products", []):
                    out[p["code"]] = p
                    self.db.off_put(p["code"], p, now)
            except (httpx.HTTPError, ValueError, KeyError) as e:
                err = f"Open Food Facts временно недоступен ({type(e).__name__}): состав и пищевая ценность для части товаров неизвестны."
        return out, err

    async def products_for(self, stores: list[StoreInfo], country: str) -> AdapterResult:
        res = AdapterResult()
        currency = CURRENCY.get(country.lower(), "RUB")
        try:
            prices = await self._all_prices(currency)
        except (httpx.HTTPError, ValueError) as e:
            res.notes.append(f"Open Prices недоступен: {type(e).__name__}.")
            return res
        matches: list[tuple[StoreInfo, dict, bool]] = []
        for s in stores:
            ref = parse_osm_id(s.id)
            chain = s.chain or chain_of(s.name)
            seen: dict[str, tuple[dict, bool]] = {}
            for it in prices:
                loc = it.get("location") or {}
                exact = bool(ref) and loc.get("osm_id") == ref[1] and (loc.get("osm_type") or "").upper() == ref[0]
                same_chain = False
                if not exact and chain and loc.get("osm_lat") is not None:
                    lchain = chain_of(loc.get("osm_brand") or loc.get("osm_name"))
                    same_chain = lchain == chain and haversine_m(s.lat, s.lon, loc["osm_lat"], loc["osm_lon"]) <= self.s.chain_radius_m
                if not (exact or same_chain):
                    continue
                code = it.get("product_code")
                prev = seen.get(code)
                if prev is None or (exact and not prev[1]) or ((exact == prev[1]) and (it.get("date") or "") > (prev[0].get("date") or "")):
                    seen[code] = (it, exact)
            for code, (it, exact) in seen.items():
                matches.append((s, it, exact))
            n_exact = sum(1 for _, _, e in [(s, i, e) for (i, e) in seen.values()] if e)
            res.notes.append(f"{s.name}: цен с чеков (Open Prices) — {len(seen)}" + (f", из них в этой точке {n_exact}" if seen else "; для этого магазина данных нет — загрузите прайс или введите цены вручную") + ".")
        codes = sorted({m[1].get("product_code") for m in matches if m[1].get("product_code")})
        off, err = await self._enrich(codes) if codes else ({}, None)
        if err:
            res.notes.append(err)
        for s, it, exact in matches:
            p = price_to_product(it, s, exact, off.get(it.get("product_code")))
            if p:
                res.products.append(p)
        return res
