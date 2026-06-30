# Connemara bilingual renderer

A bespoke e-ink display for the Connemara AvianVisitors build: bilingual
**Irish + English** bird cards drawn directly with Pillow for the **7.3" Inky
Impression** (E Ink Spectra 6, 800×480). Unlike the upstream `frame/display.py`
(which screenshots the web collage and targets the 13.3" panel), this renders
each detection as a typeset card with the Irish name as the hero.

Everything here is **desktop-testable** — no Pi or Inky hardware needed until
the final on-glass tuning pass.

## Preview on the desktop

From the `frame/` directory, against the repo's `.venv`:

```bash
cd frame
../.venv/bin/python -m connemara.preview --mode now              # "now showing" card
../.venv/bin/python -m connemara.preview --mode today            # today's species list
../.venv/bin/python -m connemara.preview --mode now --empty      # no-detections state
../.venv/bin/python -m connemara.preview --mode now --no-dither  # clean RGB (type tuning)
```

By default it writes the Spectra-6 dither (roughly what the panel shows). On
hardware the Inky library does the real colour mapping.

## Layout of the package

| File | Role |
|------|------|
| `model.py` | `Detection` / `FrameState` — the data the renderer consumes |
| `names.json` + `names.py` | bilingual name map (sci → English + Irish) |
| `theme.py` | panel size, Spectra-6 palette, fonts (with Pi fallbacks), asset lookup |
| `render.py` | the card / today / empty layouts + the dither |
| `mockdata.py` | a sample Connemara morning, for desktop dev |
| `preview.py` | the `python -m connemara.preview` CLI |
| `test_smoke.py` | hardware-free checks (`python -m pytest connemara/test_smoke.py`) |

The data source is deliberately decoupled: the renderer only sees a
`FrameState`, so swapping `mockdata` for BirdNET-Pi's real detections later
touches no layout code.

## Known gaps (tracked for later milestones)

- **Irish names** are a curated *seed* in `names.json` (common Connemara
  species). No `labels_ga.json` exists upstream — expand and verify this.
- **Illustrations**: the bundled set under `avian/assets/illustrations/` is
  North American, so most Connemara species have no artwork yet and render
  text-only. A European/Irish set can be generated via the Gemini pipeline in
  `avian/scripts/`.
- **Fonts**: desktop uses macOS Baskerville. The Pi needs a serif bundled or
  apt-installed — `theme.py` already falls back to DejaVu Serif, then Pillow's
  default. Pick a final display serif before the on-glass pass.
