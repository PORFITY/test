# Backend

FastAPI, Python 3.12+. Нужен для: поиска магазинов через OpenStreetMap (полнее, чем Apple Карты), цен Open Prices, общих загруженных каталогов и AI.
Приложение работает и без него (Apple Карты, локальные CSV/JSON, ручной ввод, локальный ассистент).

## Запуск

```bash
cd backend
pip install -r requirements.txt
cp .env.example .env      # и экспортируйте переменные (или используйте docker --env-file)
uvicorn app.main:get_app --factory --host 0.0.0.0 --port 8000
# Docker (из корня репозитория):
docker build -f backend/Dockerfile -t mealplanner-backend . && docker run --env-file backend/.env -p 8000:8000 -v mealdata:/data mealplanner-backend
```
Для телефона нужен публичный **HTTPS**-адрес (reverse proxy: Caddy/nginx/Cloudflare Tunnel). Его вписывают в `BACKEND_URL` (см. INSTALL_IPHONE.md).

## Переменные окружения

| Переменная | Назначение |
|---|---|
| `API_TOKEN` | Bearer-токен клиента. Пусто = без авторизации (только локальная разработка). |
| `ADMIN_TOKEN` | Токен для `/v1/catalog/import`. |
| `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` | AI-помощник. Без ключа `/v1/ai/intent` отвечает 503, приложение использует локальные команды. |
| `USER_AGENT` | Идентификация перед OSM/Nominatim/Open Food Facts (укажите контакт). |
| `OVERPASS_URLS` | Список зеркал Overpass через запятую. |
| `DB_PATH` | SQLite (загруженные прайсы, кэш Open Food Facts). |
| `PRICE_MAX_AGE_DAYS`, `CHAIN_RADIUS_M`, `RATE_LIMIT_PER_MIN`, `CACHE_TTL_*` | Тонкая настройка. |

## Эндпоинты

* `GET /v1/health`
* `GET /v1/stores/nearby?lat&lon&radius` — любые продуктовые магазины (Overpass `shop=supermarket|convenience|greengrocer|butcher|bakery|…`,
  `amenity=marketplace`) → `StoreInfo`; запасной вариант Nominatim; кэш 10 мин.
* `POST /v1/catalog/offers` `{stores:[StoreInfo], country}` → `{products:[CatalogProduct], notes:[…]}`. Notes честно описывают, где данных нет.
* `POST /v1/catalog/import?store_key=<id магазина | chain:Название сети>` (admin) — загрузка прайса в едином формате.
* `POST /v1/ai/intent` — фраза → `AssistantIntent` (ответ проходит строгую санитизацию).

## Источники цен (адаптеры)

| Адаптер | Что даёт | Ограничения |
|---|---|---|
| `open-prices` | Реальные цены с чеков/ценников (Open Food Facts, ODbL) + состав/аллергены/КБЖУ из Open Food Facts. Совпадение по точной точке OSM или по сети в радиусе `CHAIN_RADIUS_M` (помечается в `outletNote`). | Покрытие очень разреженное (в RUB на момент разработки — порядка сотен записей на весь мир). Open Food Facts временами недоступен — цены отдаются без состава (товар получает пометку «состав не подтверждён»). |
| `imported` | Прайсы, загруженные администратором (JSON). | Нужны данные от магазина/партнёра. |
| `chain_template.py` | Шаблон под официальный партнёрский API сети. | Не подключён ни к одной сети. |

### Как добавить новую сеть
1. Получите **официальный** доступ (партнёрский API, выгрузка прайса). Не обходите авторизацию/CAPTCHA/защиту.
2. Реализуйте адаптер по контракту `adapters/base.py` (`products_for(stores, country) -> AdapterResult`), верните `CatalogProduct` (`quality="official"`, дата, размер упаковки, состав).
3. Добавьте его в `build_adapters` (`app/main.py`). Приложение и ядро менять не нужно.

## Тесты

`cd backend && python -m pytest -q` — парсинг Overpass, отказоустойчивость зеркал, сопоставление цен Open Prices (скидки, цена за кг, чужие точки сети),
сквозной `/offers`, импорт, авторизация и лимиты, санитизация AI. Формат ответов дополнительно сверяется Swift-тестом (`BackendContractTests`).
