from __future__ import annotations

from ..db import Db
from ..geo import chain_of
from ..models import CatalogProduct, StoreInfo
from .base import AdapterResult


class ImportedAdapter:
    """Каталоги, загруженные администратором (CSV/JSON → /v1/catalog/import). Ключ — id магазина или название сети."""
    name = "imported"

    def __init__(self, db: Db) -> None:
        self.db = db

    async def products_for(self, stores: list[StoreInfo], country: str) -> AdapterResult:
        res = AdapterResult()
        for s in stores:
            keys = [s.id] + ([f"chain:{s.chain or chain_of(s.name)}"] if (s.chain or chain_of(s.name)) else [])
            rows = self.db.imported_for(keys)
            for r in rows:
                r.pop("_store_key", None)
                r["storeID"] = s.id
                r["id"] = f"{s.id}:{r['id']}"
                res.products.append(CatalogProduct(**r))
            if rows:
                res.notes.append(f"{s.name}: загруженный каталог, товаров {len(rows)}.")
        return res
