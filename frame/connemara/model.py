"""The data the renderer consumes.

Deliberately decoupled from where detections come from. Today that is
``mockdata`` (desktop dev); later it will be BirdNET-Pi's detection database
or its recent-detections API. The renderer only ever sees a ``FrameState``,
so the data source can change without touching layout code.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


@dataclass(frozen=True)
class Detection:
    """One species heard within the window, with its most recent hit."""

    sci: str                 # scientific name — the key into names/illustrations
    last_heard: datetime     # most recent detection in the window
    count: int = 1           # detections in the window
    confidence: float = 0.0  # confidence of the most recent detection (0..1)


@dataclass
class FrameState:
    """Everything one panel render needs.

    ``now_showing`` is the bird the card features (normally the most recent
    detection). ``today`` is every species in the window, most-recent first,
    for the list view and the "also today" strip.
    """

    now_showing: Detection | None
    today: list[Detection] = field(default_factory=list)
    generated_at: datetime | None = None

    @classmethod
    def from_detections(cls, detections: list[Detection], generated_at: datetime | None = None) -> "FrameState":
        """Build a state from a flat list, newest first by last_heard."""
        ordered = sorted(detections, key=lambda d: d.last_heard, reverse=True)
        return cls(
            now_showing=ordered[0] if ordered else None,
            today=ordered,
            generated_at=generated_at,
        )
