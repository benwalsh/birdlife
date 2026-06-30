"""Sample detections for desktop development — no Pi, no mic, no database.

A plausible Connemara morning: a mix of garden, coastal and bog species. The
featured bird (Swallow) has a bundled illustration so the card looks complete;
the rest exercise the bilingual list and the "missing illustration" path.
"""
from __future__ import annotations

from datetime import datetime, timedelta

from .model import Detection, FrameState

# A fixed reference time so previews are deterministic (no Date.now flakiness).
_BASE = datetime(2026, 6, 29, 18, 42)


def _ago(minutes: int) -> datetime:
    return _BASE - timedelta(minutes=minutes)


# (scientific name, minutes-ago last heard, count) — newest first.
_SAMPLE = [
    ("Hirundo rustica", 0, 4),
    ("Erithacus rubecula", 7, 12),
    ("Sturnus vulgaris", 19, 6),
    ("Turdus merula", 26, 9),
    ("Corvus corax", 41, 2),
    ("Fringilla coelebs", 53, 5),
    ("Carduelis carduelis", 68, 3),
    ("Saxicola rubicola", 84, 2),
    ("Anthus pratensis", 96, 7),
    ("Troglodytes troglodytes", 112, 8),
    ("Pyrrhocorax pyrrhocorax", 133, 1),
    ("Numenius arquata", 151, 1),
]


def sample_state() -> FrameState:
    dets = [
        Detection(sci=sci, last_heard=_ago(m), count=c, confidence=0.8)
        for sci, m, c in _SAMPLE
    ]
    return FrameState.from_detections(dets, generated_at=_BASE)


def empty_state() -> FrameState:
    return FrameState(now_showing=None, today=[], generated_at=_BASE)
