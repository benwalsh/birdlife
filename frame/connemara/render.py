"""Draw the panel. Pure Pillow; no hardware, no network.

``render(state, mode)`` returns an 800x480 RGB image. ``dither_spectra6``
maps it to the six inks for a desktop preview; on the Pi the Inky library does
the real mapping. Layout asks the theme for fonts by role, so the typeface is
swappable in one place.
"""
from __future__ import annotations

from PIL import Image, ImageDraw

from . import theme
from .model import FrameState
from .names import lookup

MARGIN = 56
RIGHT_MARGIN = 48


# --- text helpers -----------------------------------------------------------
def _text_w(draw: ImageDraw.ImageDraw, text: str, font) -> int:
    l, t, r, b = draw.textbbox((0, 0), text, font=font)
    return r - l


def _fit_font(draw, text, role, max_size, max_width, min_size=28):
    """Largest font of `role` at which `text` fits in `max_width`."""
    size = max_size
    while size > min_size:
        f = theme.font(role, size)
        if _text_w(draw, text, f) <= max_width:
            return f
        size -= 2
    return theme.font(role, min_size)


def _draw_tracked(draw, xy, text, font, fill, tracking):
    """Draw `text` with extra letter-spacing (for the small-caps eyebrow)."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += _text_w(draw, ch, font) + tracking
    return x


# --- illustration -----------------------------------------------------------
def _load_illustration(sci: str, max_h: int) -> Image.Image | None:
    path = theme.illustration_path(sci)
    if not path:
        return None
    img = Image.open(path).convert("RGBA")
    if img.height > max_h:
        s = max_h / img.height
        img = img.resize((max(1, round(img.width * s)), max_h), Image.LANCZOS)
    return img


# --- now-showing card -------------------------------------------------------
def render_now_showing(state: FrameState) -> Image.Image:
    canvas = Image.new("RGB", (theme.PANEL_W, theme.PANEL_H), theme.PAPER)
    d = ImageDraw.Draw(canvas)

    if state.now_showing is None:
        return _render_empty(canvas, d)

    det = state.now_showing
    name = lookup(det.sci)

    # Illustration on the left (if we ship one for this species).
    illo = _load_illustration(det.sci, max_h=384)
    if illo is not None:
        iy = (theme.PANEL_H - illo.height) // 2
        canvas.paste(illo, (MARGIN, iy), illo)
        text_x = MARGIN + illo.width + 40
    else:
        text_x = MARGIN

    text_w = theme.PANEL_W - RIGHT_MARGIN - text_x

    # Eyebrow.
    eyebrow = theme.font("serif", 19)
    _draw_tracked(d, (text_x, 62), "HEARD JUST NOW", eyebrow, theme.RED, tracking=6)

    # Hero: the Irish name (or English if Irish not yet curated), auto-fit.
    hero_text = name.ga or name.en
    hero = _fit_font(d, hero_text, "serif", max_size=92, max_width=text_w, min_size=40)
    hero_top = 92
    d.text((text_x - 2, hero_top), hero_text, font=hero, fill=theme.INK)
    hero_bottom = hero_top + (d.textbbox((0, 0), hero_text, font=hero)[3])

    y = hero_bottom + 14
    # English common name (only when the hero was the Irish name).
    if name.ga:
        eng = theme.font("serif", 38)
        d.text((text_x, y), name.en, font=eng, fill=theme.INK)
        y += 50
    # Scientific name, italic.
    sci = theme.font("serif_italic", 24)
    d.text((text_x, y), det.sci, font=sci, fill=theme.MUTED)
    y += 44

    # Rule + count/time line.
    d.line((text_x, y, theme.PANEL_W - RIGHT_MARGIN, y), fill=theme.INK, width=2)
    y += 12
    meta = theme.font("serif", 23)
    calls = "1 call" if det.count == 1 else f"{det.count} calls"
    when = det.last_heard.strftime("%H:%M")
    d.text((text_x, y), f"{calls} heard  ·  last at {when}", font=meta, fill=theme.INK)

    _draw_also_today(d, state)
    return canvas


def _draw_also_today(d: ImageDraw.ImageDraw, state: FrameState):
    """A single-line strip of the other species heard today, Irish names first."""
    others = [det for det in state.today if det is not state.now_showing]
    if not others:
        return
    names = []
    for det in others:
        n = lookup(det.sci)
        names.append(n.ga or n.en)
    label = theme.font("serif_italic", 21)
    d.text((MARGIN, theme.PANEL_H - 66), "also today", font=label, fill=theme.MUTED)
    body = theme.font("serif", 21)
    # Fit as many names as the width allows; trail with an ellipsis if clipped.
    avail = theme.PANEL_W - 2 * MARGIN
    shown, joined = [], ""
    for nm in names:
        cand = "  ·  ".join(shown + [nm])
        if _text_w(d, cand, body) > avail:
            joined = "  ·  ".join(shown) + "  ·  …"
            break
        shown.append(nm)
        joined = cand
    d.text((MARGIN, theme.PANEL_H - 40), joined, font=body, fill=theme.INK)


def _render_empty(canvas, d):
    """No detections yet: a calm centred title rather than a blank panel."""
    title_ga = "Gan éan fós"
    title_en = "No birds heard yet today"
    ga = theme.font("serif", 64)
    en = theme.font("serif_italic", 26)
    gw = _text_w(d, title_ga, ga)
    ew = _text_w(d, title_en, en)
    cx = theme.PANEL_W // 2
    d.text((cx - gw // 2, 188), title_ga, font=ga, fill=theme.INK)
    d.text((cx - ew // 2, 270), title_en, font=en, fill=theme.MUTED)
    return canvas


# --- today list view --------------------------------------------------------
def render_today(state: FrameState) -> Image.Image:
    """A two-column list of every species heard today, bilingual."""
    canvas = Image.new("RGB", (theme.PANEL_W, theme.PANEL_H), theme.PAPER)
    d = ImageDraw.Draw(canvas)

    eyebrow = theme.font("serif", 19)
    _draw_tracked(d, (MARGIN, 40), "HEARD TODAY", eyebrow, theme.RED, tracking=6)
    count = len(state.today)
    head = theme.font("serif", 40)
    d.text((MARGIN, 64), f"{count} species", font=head, fill=theme.INK)
    d.line((MARGIN, 122, theme.PANEL_W - MARGIN, 122), fill=theme.INK, width=2)

    if not state.today:
        return _render_empty(canvas, d)

    ga_font = theme.font("serif", 26)
    en_font = theme.font("serif_italic", 18)
    col_w = (theme.PANEL_W - 2 * MARGIN) // 2
    rows_per_col = 8
    row_h = 42
    top = 144
    for i, det in enumerate(state.today[: rows_per_col * 2]):
        col, row = divmod(i, rows_per_col)
        x = MARGIN + col * col_w
        y = top + row * row_h
        n = lookup(det.sci)
        d.text((x, y), n.ga or n.en, font=ga_font, fill=theme.INK)
        if n.ga:
            gw = _text_w(d, n.ga, ga_font)
            d.text((x + gw + 12, y + 8), n.en, font=en_font, fill=theme.MUTED)
    return canvas


# --- dispatch + dither ------------------------------------------------------
def render(state: FrameState, mode: str = "now") -> Image.Image:
    if mode == "today":
        return render_today(state)
    return render_now_showing(state)


def dither_spectra6(img: Image.Image) -> Image.Image:
    """Approximate the panel: quantize to the six inks with Floyd–Steinberg."""
    pal = Image.new("P", (1, 1))
    flat = [c for ink in theme.SPECTRA6 for c in ink]
    flat += list(theme.PAPER) * ((768 - len(flat)) // 3)
    pal.putpalette(flat[:768])
    return img.convert("RGB").quantize(
        palette=pal, dither=Image.Dither.FLOYDSTEINBERG
    ).convert("RGB")
