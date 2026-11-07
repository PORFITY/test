# -*- coding: utf-8 -*-
"""Собирает recipes.json из recipes_part*.py и проверяет ссылки на ингредиенты."""
import json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import recipes_part2  # noqa  (тянет part1)
from recipes_part1 import R
root = os.path.join(os.path.dirname(__file__), "..", "ios", "MealCore", "Sources", "MealCore", "Resources")
ings = {i["key"] for i in json.load(open(os.path.join(root, "ingredients.json"), encoding="utf-8"))["items"]}
ids = set()
for r in R:
    assert r["id"] not in ids, r["id"]; ids.add(r["id"])
    for k, a in r["ing"]:
        assert k in ings, (r["id"], k)
        assert a > 0, (r["id"], k)
json.dump({"items": R}, open(os.path.join(root, "recipes.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(R), "recipes")
