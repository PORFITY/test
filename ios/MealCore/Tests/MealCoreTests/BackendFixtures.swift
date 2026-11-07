// Сгенерировано из ответов backend (backend/tests) — контрактный тест формата обмена.
enum BackendFixtures {
    static let stores = #"""
{
 "stores": [
  {
   "id": "osm:way/2",
   "name": "Продуктовая лавка у Ивана",
   "chain": null,
   "address": null,
   "lat": 55.76,
   "lon": 37.62,
   "distanceM": 496.6,
   "shopType": "convenience",
   "openingHours": null,
   "delivery": true,
   "catalog": "unknown",
   "priceUpdatedAt": null,
   "source": "osm"
  },
  {
   "id": "osm:node/4",
   "name": "Рынок",
   "chain": null,
   "address": null,
   "lat": 55.7512,
   "lon": 37.6181,
   "distanceM": 513.9,
   "shopType": "marketplace",
   "openingHours": null,
   "delivery": null,
   "catalog": "unknown",
   "priceUpdatedAt": null,
   "source": "osm"
  },
  {
   "id": "osm:node/1",
   "name": "Магнит",
   "chain": "Магнит",
   "address": "Москва, Тестовая, 5",
   "lat": 55.751,
   "lon": 37.618,
   "distanceM": 535.5,
   "shopType": "supermarket",
   "openingHours": "08:00-23:00",
   "delivery": null,
   "catalog": "unknown",
   "priceUpdatedAt": null,
   "source": "osm"
  }
 ]
}
"""#
    static let offers = #"""
{
 "products": [
  {
   "id": "openprices:osm:node/8297695767:4601025120849",
   "storeID": "osm:node/8297695767",
   "name": "Молоко питьевое пастеризованное 2.5% 930 ml",
   "brand": "Вологжанка",
   "category": "en:milks",
   "imageURL": null,
   "url": "https://prices.openfoodfacts.org/products/4601025120849",
   "quantityText": "930 ml",
   "packSize": 930.0,
   "packUnit": "ml",
   "price": 9999,
   "promoPrice": null,
   "discountText": null,
   "inStock": null,
   "ingredientsText": null,
   "allergenTags": [],
   "traceTags": [],
   "nutritionPer100": null,
   "priceDate": "2026-11-05T00:00:00Z",
   "quality": "crowdsourced",
   "source": "open-prices",
   "outletNote": null,
   "ingredientHint": null
  },
  {
   "id": "openprices:osm:node/8297695767:4600819311999",
   "storeID": "osm:node/8297695767",
   "name": "Рис круглозерный 900 g",
   "brand": "Тест",
   "category": null,
   "imageURL": "https://images.example/x.jpg",
   "url": "https://prices.openfoodfacts.org/products/4600819311999",
   "quantityText": "900 g",
   "packSize": 900.0,
   "packUnit": "g",
   "price": 14990,
   "promoPrice": 12950,
   "discountText": "Скидка по чеку",
   "inStock": null,
   "ingredientsText": "рис",
   "allergenTags": [],
   "traceTags": [
    "en:peanuts"
   ],
   "nutritionPer100": {
    "kcal": 344.0,
    "protein": 7.0,
    "fat": 0.7,
    "carbs": 78.0
   },
   "priceDate": "2026-11-01T00:00:00Z",
   "quality": "crowdsourced",
   "source": "open-prices",
   "outletNote": "Цена с чека в другой точке сети «Пятёрочка», Электросталь",
   "ingredientHint": null
  }
 ],
 "notes": [
  "Пятёрочка: цен с чеков (Open Prices) — 2, из них в этой точке 1."
 ]
}
"""#
    static let intent = #"""
{
 "action": "replaceMeal",
 "day": 2,
 "slot": 2,
 "include": [
  "chicken_breast"
 ],
 "avoid": [],
 "recipeID": null,
 "reply": null
}
"""#
}
