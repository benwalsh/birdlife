"""Bilingual name lookup, keyed by BirdNET scientific name.

The Irish (Gaeilge) names are the centrepiece of this build. They live in
``model/l18n/labels_ga.json`` — a standard BirdNET locale file we generated
from BirdWatch Ireland's "List of Ireland's Birds", in the same format as the
upstream ``labels_*.json``. English comes from ``labels_en.json``.

A locale file carries all ~7058 BirdNET keys; species with no Irish name fall
back to the English string. We treat that fallback as "no Irish" so the
renderer shows English only, rather than repeating the English name twice.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from functools import lru_cache

_L18N = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "model", "l18n")
)


@dataclass(frozen=True)
class Name:
    sci: str
    en: str          # English common name (falls back to sci if unknown)
    ga: str | None   # Irish name, or None if not curated for this species


def _load(locale: str) -> dict[str, str]:
    path = os.path.join(_L18N, f"labels_{locale}.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


@lru_cache(maxsize=1)
def _tables() -> tuple[dict[str, str], dict[str, str]]:
    return _load("en"), _load("ga")


def lookup(sci: str) -> Name:
    """Resolve a scientific name to its English + Irish names.

    Unknown species degrade gracefully: English falls back to the scientific
    name, Irish to ``None``. A ``ga`` value equal to the English string means
    the species has no curated Irish name (locale-file fallback), so we return
    ``None`` there too.
    """
    en, ga = _tables()
    en_name = en.get(sci, sci)
    ga_name = ga.get(sci)
    irish = ga_name if (ga_name and ga_name != en_name) else None
    return Name(sci=sci, en=en_name, ga=irish)


def has_irish(sci: str) -> bool:
    return lookup(sci).ga is not None
