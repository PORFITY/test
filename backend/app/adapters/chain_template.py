"""Шаблон адаптера торговой сети с официальным API (партнёрский доступ).

Как подключить новую сеть:
  1. Получите официальный доступ (партнёрский API / выгрузка прайса) и ключ — храните ключ в переменной окружения, не в коде и не в приложении.
  2. Скопируйте этот класс, реализуйте `products_for`, верните товары в едином формате CatalogProduct
     (quality="official", priceDate, quantityText/packSize, состав и аллергены, если источник их отдаёт).
  3. Добавьте экземпляр в `build_adapters` (app/main.py).

Готовых адаптеров к закрытым API сетей (Пятёрочка, Магнит и др.) в проекте НЕТ: у них нет открытых официальных API,
а обход защиты запрещён правилами проекта.
"""
from __future__ import annotations

import os

from ..models import StoreInfo
from .base import AdapterResult


class ChainAdapterTemplate:
    name = "chain-template"

    def __init__(self) -> None:
        self.api_key = os.getenv("CHAIN_TEMPLATE_API_KEY")

    async def products_for(self, stores: list[StoreInfo], country: str) -> AdapterResult:
        if not self.api_key:
            return AdapterResult(notes=["Адаптер сети не настроен (нет ключа партнёрского API)."])
        # здесь — запрос к официальному API и преобразование в CatalogProduct
        return AdapterResult()
