import math

CHAIN_ALIASES = [
    ("Пятёрочка", ["пятерочк", "пятёрочк", "pyaterochka", "5ka"]), ("Магнит", ["магнит", "magnit"]), ("Лента", ["лента", "lenta"]),
    ("Перекрёсток", ["перекресток", "перекрёсток", "perekrestok"]), ("Ашан", ["ашан", "auchan"]), ("Дикси", ["дикси", "dixy"]),
    ("ВкусВилл", ["вкусвилл", "vkusvill"]), ("О’КЕЙ", ["окей", "о’кей", "o'key", "okey"]), ("METRO", ["metro", "метро"]),
    ("Чижик", ["чижик"]), ("Монетка", ["монетка"]), ("Верный", ["верный"]), ("Fix Price", ["fix price", "фикс прайс"]),
]


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def normalize(text: str | None) -> str:
    return (text or "").lower().replace("ё", "е").strip()


def chain_of(name: str | None) -> str | None:
    """Каноническое название сети (только для группировки; неизвестные магазины это не отсекает)."""
    n = normalize(name)
    for canonical, stems in CHAIN_ALIASES:
        if any(normalize(s) in n for s in stems):
            return canonical
    return None
