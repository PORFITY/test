import json
import sqlite3
import threading
from pathlib import Path


class Db:
    """Простое SQLite-хранилище: импортированные каталоги и кэш Open Food Facts."""

    def __init__(self, path: str) -> None:
        if path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(path, check_same_thread=False)
        self.lock = threading.Lock()
        with self.lock:
            self.conn.executescript("""
            CREATE TABLE IF NOT EXISTS imported_products (store_key TEXT NOT NULL, id TEXT NOT NULL, json TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY (store_key, id));
            CREATE INDEX IF NOT EXISTS ix_imp_store ON imported_products(store_key);
            CREATE TABLE IF NOT EXISTS off_cache (code TEXT PRIMARY KEY, json TEXT NOT NULL, fetched_at REAL NOT NULL);
            """)

    def replace_import(self, store_key: str, products: list[dict], updated_at: str) -> int:
        with self.lock:
            self.conn.execute("DELETE FROM imported_products WHERE store_key=?", (store_key,))
            self.conn.executemany("INSERT OR REPLACE INTO imported_products VALUES (?,?,?,?)",
                                  [(store_key, p["id"], json.dumps(p, ensure_ascii=False), updated_at) for p in products])
            self.conn.commit()
        return len(products)

    def imported_for(self, keys: list[str]) -> list[dict]:
        if not keys:
            return []
        q = ",".join("?" * len(keys))
        with self.lock:
            rows = self.conn.execute(f"SELECT store_key, json FROM imported_products WHERE store_key IN ({q})", keys).fetchall()
        return [{**json.loads(j), "_store_key": k} for k, j in rows]

    def off_get(self, code: str, max_age_s: float, now: float) -> dict | None:
        with self.lock:
            row = self.conn.execute("SELECT json, fetched_at FROM off_cache WHERE code=?", (code,)).fetchone()
        if row and now - row[1] < max_age_s:
            return json.loads(row[0])
        return None

    def off_put(self, code: str, data: dict, now: float) -> None:
        with self.lock:
            self.conn.execute("INSERT OR REPLACE INTO off_cache VALUES (?,?,?)", (code, json.dumps(data, ensure_ascii=False), now))
            self.conn.commit()
