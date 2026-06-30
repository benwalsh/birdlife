# AvianVisitors — Connemara build

*A bird-detection wall display: it listens for birdsong, identifies species
acoustically, and renders a live bilingual (Irish + English) collage on a framed
e-ink panel.*

Built for a house in Connemara — coastal, bog and moorland birds, weighted to the
West of Ireland, with Irish names alongside English. A microphone listens
outside; a framed Inky panel shows the flock indoors.

---

## How it works

```
outdoor mic ─▶ BirdNET (birdnetlib, Python) ─▶ birds.db (SQLite)
                                                    │
                                       ActiveRecord │ read-only
                                                    ▼
                          Rails collage  ──▶  /panel (bare 800×480 SVG)
                       (mask-packed, bilingual,        │
                        credibility-filtered)          │ Playwright screenshot
                                                       ▼
                                          dither to Spectra-6 ─▶ Inky e-ink panel
```

The split is deliberate (see [`CLAUDE.md`](CLAUDE.md)): **detection stays
Python** (BirdNET is a TensorFlow-Lite model — reimplementing it buys nothing),
the **collage is Rails** (the part worth owning and enjoying), and the **Inky
push is a thin Python shooter** (Pimoroni's `inky` library is Python-only).

## Hardware

Raspberry Pi 4 (4 GB) · Pimoroni Inky Impression 7.3" (Spectra-6, 800×480) ·
Clippy EM272 USB mic with a fur windscreen, mounted outside under an eave with a
short cable run indoors. Frame: Connemara bog oak / bog pine, shadow-box style.
Full bill of materials and rationale in [`CLAUDE.md`](CLAUDE.md).

## Repo layout

```
listener/      BirdNET listener — analyse a recording or the live mic into birds.db
collage/       Rails collage web app — the display
avian/scripts/ illustration pipeline: pregen → cutout_flood → build_masks
avian/assets/  generated illustrations + masks.json (collage silhouettes)
shooter/       Playwright screenshot of /panel → dither → push to the Inky
deploy/        systemd units + DEPLOY.md runbook
model/l18n/    bilingual labels: labels_en.json, labels_ga.json
```

## Develop on desktop, deploy to the Pi

Iterating on a Pi is slow; treat it as a deployment target. Everything below the
final on-glass tuning is built and tested on a desktop. Python is managed with
[uv](https://docs.astral.sh/uv/) (it pins its own Python 3.12); the web app is
Rails 8 + Hotwire + HAML, bundled with [bun](https://bun.sh).

Config lives in a gitignored `.env` (`BIRD_LAT`/`BIRD_LON`, `BIRD_MIC`,
`BIRD_MIN_CONF`, and `GEMINI_API_KEY` for illustration generation). Copy
`.env.example` to start.

```bash
make setup          # install Python, Ruby, JS deps and prepare the database
make serve          # run the collage at http://localhost:4030
make listen         # listen on the mic and write detections (Ctrl-C to stop)
make analyze FILE=song.wav   # analyse a recorded clip instead of the mic
make frame-preview  # dither /panel to a PNG to preview the Inky look (no hardware)
make test           # RSpec        ·   make lint   # RuboCop
make help           # list every task
```

`make purge` resets the collage to empty. See `make help` for the rest.

## The collage

The Rails app reads `birds.db` and renders the flock at
[`/`](http://localhost:4030/), with `stats` and `atlas` views and a per-species
detail modal. Highlights:

- **Silhouette packing.** `MaskPacker` nestles birds by their actual outline
  (1-bit masks in `masks.json`) — no overlap, no rectangles touching. `/panel` is
  the bare 800×480 SVG the shooter screenshots.
- **Bilingual.** Every species shows its Irish and English name; the detail modal
  even toggles between English and Irish Wikipedia prose where an Irish article
  exists.
- **Credibility filter.** A species only appears once it's trustworthy — one
  confident hit (≥0.6) or enough repeats — so a lone low-confidence false
  positive (a 27 % "Gadwall") stays off the wall. Nothing is deleted; it's a
  display gate (see `Detection.credible_species`).

House conventions mirror the sibling work repo: RSpec + FactoryBot, HAML, bun
(not yarn), RuboCop. See [`collage/README.md`](collage/README.md).

## Illustrations

The collage art is generated, not hand-drawn — kachō-e–style birds on a flat
cream ground, cut to transparency and reduced to packing masks. The pipeline and
the prompt live in [`avian/scripts/README.md`](avian/scripts/README.md). Common
tasks:

```bash
make regen SPECIES="Pyrrhocorax pyrrhocorax|Red-billed Chough"  # one bird
make cutout      # flood-cut any new cream-ground illustrations
make declutter   # sweep stray flecks from existing cutouts, rebuild masks
make masks       # rebuild masks.json after changing the illustration set
```

## Deploy to the Pi

`deploy/` holds the systemd units (listener, web, frame timer) and
[`deploy/DEPLOY.md`](deploy/DEPLOY.md), the runbook for moving desktop → Pi:
WAL + Litestream backup of `birds.db`, the Inky-only `inky` install, and the
final on-glass colour/dither tuning.

## Lineage & license

Detection is Cornell's [BirdNET](https://birdnet.cornell.edu/); the project began
as a fork of [AvianVisitors](https://github.com/Twarner491/AvianVisitors) (built
on BirdNET-Pi). Licensed CC-BY-NC-SA-4.0 — non-commercial only. A private personal
build (a birthday gift), not for distribution.
