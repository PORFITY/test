"""Контракт адаптера каталога. Каждая торговая сеть / источник — отдельный адаптер; добавление нового не требует изменений остального кода.

Правила:
  * только официальные API, разрешённые интеграции, партнёрские выгрузки, открытые данные;
  * никакого обхода авторизации, CAPTCHA и технических ограничений;
  * если данных нет — вернуть пустой список и пояснение в notes (ничего не выдумывать).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

from ..models import CatalogProduct, StoreInfo


@dataclass
class AdapterResult:
    products: list[CatalogProduct] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


class CatalogAdapter(Protocol):
    name: str

    async def products_for(self, stores: list[StoreInfo], country: str) -> AdapterResult: ...
