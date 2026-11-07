"""Модели обмена. Имена полей совпадают с Codable-моделями Swift (MealCore): StoreInfo, CatalogProduct, AssistantIntent."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel, Field


def iso(dt: Optional[datetime]) -> Optional[str]:
    """ISO8601 без долей секунды — формат .iso8601 в Swift JSONDecoder."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class StoreInfo(BaseModel):
    id: str
    name: str
    chain: Optional[str] = None
    address: Optional[str] = None
    lat: float
    lon: float
    distanceM: float = 0
    shopType: str = "supermarket"
    openingHours: Optional[str] = None
    delivery: Optional[bool] = None
    catalog: str = "unknown"          # unknown | unavailable | crowdsourced | imported | official
    priceUpdatedAt: Optional[str] = None
    source: str = "osm"


class Nutrition(BaseModel):
    kcal: float = 0
    protein: float = 0
    fat: float = 0
    carbs: float = 0


class CatalogProduct(BaseModel):
    id: str
    storeID: str
    name: str
    brand: Optional[str] = None
    category: Optional[str] = None
    imageURL: Optional[str] = None
    url: Optional[str] = None
    quantityText: Optional[str] = None
    packSize: Optional[float] = None
    packUnit: Optional[str] = None     # g | ml | pcs
    price: int                          # копейки
    promoPrice: Optional[int] = None
    discountText: Optional[str] = None
    inStock: Optional[bool] = None
    ingredientsText: Optional[str] = None
    allergenTags: list[str] = Field(default_factory=list)
    traceTags: list[str] = Field(default_factory=list)
    nutritionPer100: Optional[Nutrition] = None
    priceDate: Optional[str] = None
    quality: str = "imported"          # official | imported | userEntered | crowdsourced | estimate
    source: str = ""
    outletNote: Optional[str] = None
    ingredientHint: Optional[str] = None


class OffersRequest(BaseModel):
    stores: list[StoreInfo]
    country: str = "ru"


class OffersResponse(BaseModel):
    products: list[CatalogProduct]
    notes: list[str] = Field(default_factory=list)


class StoresResponse(BaseModel):
    stores: list[StoreInfo]


class AIContextMeal(BaseModel):
    day: int
    slot: int
    recipeID: str
    name: str


class AIContext(BaseModel):
    days: int
    slots: list[str]
    startDate: str
    allergens: list[str] = Field(default_factory=list)
    meals: list[AIContextMeal] = Field(default_factory=list)


class AIRequest(BaseModel):
    message: str = Field(max_length=1000)
    context: AIContext


class AssistantIntent(BaseModel):
    action: str = "unknown"
    day: Optional[int] = None
    slot: Optional[int] = None
    include: list[str] = Field(default_factory=list)
    avoid: list[str] = Field(default_factory=list)
    recipeID: Optional[str] = None
    reply: Optional[str] = None
