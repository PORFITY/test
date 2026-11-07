import json
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.db import Db
from app.main import create_app

FIX = Path(__file__).parent / "fixtures"


def fixture(name: str):
    return json.loads((FIX / name).read_text(encoding="utf-8"))


class Router:
    """Подменяет внешние HTTP-сервисы. routes: подстрока URL → ответ (dict/list/callable/int-код ошибки)."""

    def __init__(self):
        self.routes: dict[str, object] = {}
        self.calls: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.calls.append(request)
        for key, resp in self.routes.items():
            if key in str(request.url):
                if isinstance(resp, int):
                    return httpx.Response(resp, text="error")
                if callable(resp):
                    return resp(request)
                return httpx.Response(200, json=resp)
        return httpx.Response(404, text="no route")


@pytest.fixture
def router():
    return Router()


@pytest.fixture
def settings():
    s = Settings()
    s.api_token = None
    s.admin_token = "adm"
    s.anthropic_key = None
    s.db_path = ":memory:"
    s.overpass_urls = ["https://overpass.test/a", "https://overpass.test/b"]
    s.price_max_age_days = 36500
    return s


@pytest.fixture
def make_client(settings, router):
    def _make(**over):
        for k, v in over.items():
            setattr(settings, k, v)
        http = httpx.AsyncClient(transport=httpx.MockTransport(router))
        return TestClient(create_app(settings, http, Db(":memory:")))
    return _make
