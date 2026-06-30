"""Panel geometry, the Spectra-6 palette, fonts, and asset lookup.

Fonts resolve from a candidate list so the same code runs on the macOS desktop
(Baskerville) and later on Raspberry Pi OS (a bundled or apt serif), degrading
to Pillow's built-in font if nothing is found. Keep layout code asking for a
*role* ("hero", "sci") rather than a file, so the typeface can change in one
place.
"""
from __future__ import annotations

import os
from functools import lru_cache

from PIL import ImageFont

# --- panel ------------------------------------------------------------------
# Inky Impression 7.3" (E Ink Spectra 6) is 800x480 landscape.
PANEL_W, PANEL_H = 800, 480

# --- Spectra-6 inks ---------------------------------------------------------
# Approximate sRGB for the six inks, used for the desktop dither preview. On
# hardware the Inky library maps to the panel's real palette.
PAPER = (236, 234, 223)
INK = (26, 26, 28)
RED = (165, 60, 56)
YELLOW = (198, 176, 74)
BLUE = (49, 71, 130)
GREEN = (58, 110, 72)
SPECTRA6 = [PAPER, INK, RED, YELLOW, BLUE, GREEN]

MUTED = (110, 110, 108)  # for secondary text; dithers to a grey stipple

# --- fonts ------------------------------------------------------------------
# Each role maps to ordered (path, face-index) candidates. First that loads wins.
_MAC = "/System/Library/Fonts/Supplemental/"
_FONT_CANDIDATES: dict[str, list[tuple[str, int]]] = {
    "serif":        [(_MAC + "Baskerville.ttc", 0),
                     ("/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf", 0)],
    "serif_italic": [(_MAC + "Baskerville.ttc", 2),
                     ("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Italic.ttf", 0)],
    "serif_bold":   [(_MAC + "Baskerville.ttc", 1),
                     ("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 0)],
}


@lru_cache(maxsize=128)
def font(role: str, size: int) -> ImageFont.FreeTypeFont:
    for path, index in _FONT_CANDIDATES.get(role, _FONT_CANDIDATES["serif"]):
        if os.path.exists(path):
            return ImageFont.truetype(path, size, index=index)
    return ImageFont.load_default(size)


# --- assets -----------------------------------------------------------------
_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ILLUSTRATIONS_DIR = os.path.join(_REPO_ROOT, "avian", "assets", "illustrations")


def slug(sci: str) -> str:
    return sci.strip().lower().replace(" ", "-")


def illustration_path(sci: str) -> str | None:
    """Path to the bird's cutout illustration, or None if we don't ship one.

    Note: the bundled set is North American, so most Connemara species miss for
    now; the renderer handles a missing illustration without complaint.
    """
    p = os.path.join(ILLUSTRATIONS_DIR, slug(sci) + ".png")
    return p if os.path.exists(p) else None
