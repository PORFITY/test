# Рацион — нативное iOS-приложение для планирования питания, бюджета и закупок

Приложение (Swift, SwiftUI, MapKit, Core Location) находит продуктовые магазины рядом, принимает бюджет / период / число людей /
аллергены / технику / посуду и строит рацион: меню на каждый день, пошаговые рецепты с граммовками, список покупок **целыми упаковками**
с разбивкой по магазинам и честным остатком бюджета.

> Статус и честные ограничения — в [docs/STATUS.md](docs/STATUS.md). Коротко: ядро расчётов, приложение и backend реализованы и
> проверены автотестами; **реальных каталогов крупных сетей (Пятёрочка, Магнит…) в проекте нет** — у них нет открытых официальных API.
> Источники цен: Open Prices (реальные цены с чеков, очень разреженные), загруженные CSV/JSON, ручной ввод; без них — режим «ориентиров» с явной пометкой.

## Состав репозитория

| Путь | Что это |
|---|---|
| `ios/MealCore` | Swift Package: модели, оптимизатор меню и закупок (упаковки, сроки годности, заморозка, этапы), аллергены, техника/посуда, импорт каталогов, ассистент, хранилище. Собирается и тестируется на Linux и macOS. |
| `ios/MealPlanner` | iOS-приложение (SwiftUI, iOS 17+). `project.yml` (XcodeGen) + готовый `MealPlanner.xcodeproj`. |
| `backend/` | FastAPI: магазины из OpenStreetMap, адаптеры каталогов (Open Prices, загруженные прайсы, шаблон для официальных API), AI-посредник (ключ только на сервере). |
| `tools/` | Генератор библиотеки рецептов (`recipes_part*.py` → `recipes.json`). |
| `.github/workflows` | CI: тесты MealCore на macOS, сборка приложения в Xcode, запуск в симуляторе, неподписанный IPA, тесты backend. |
| `docs/` | Архитектура, установка на iPhone, backend, статус. |

## Быстрый старт

```bash
# 1) Ядро и его тесты (Linux/macOS, нужен Swift 5.9+)
cd ios/MealCore && swift test

# 2) Backend (необязателен, но нужен для OpenStreetMap-поиска, Open Prices и AI)
cd backend && pip install -r requirements-dev.txt && python -m pytest -q
cp .env.example .env   # заполните; затем:
uvicorn app.main:get_app --factory --port 8000

# 3) Приложение: откройте ios/MealPlanner/MealPlanner.xcodeproj в Xcode 16+, выберите Team, запустите на iPhone.
```
Подробно: [docs/INSTALL_IPHONE.md](docs/INSTALL_IPHONE.md), [docs/BACKEND.md](docs/BACKEND.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
