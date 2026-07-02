# Deploying to the Raspberry Pi

The wall device: a Pi 4 driving a Pimoroni Inky Impression 7.3" (Spectra 6,
800×480), with the USB bird mic. Three services run on boot:

| Service | What it does |
|---|---|
| `birdlife-listener` | reads the USB mic → BirdNET → writes `birds.db` |
| `birdlife-web` | the Rails app on `:4030` (serves `/station` for the wall, plus the web UI) |
| `birdlife-frame` (timer) | screenshots `/station`, advances the slow gallery on the Inky |

The whole stack runs **bare-metal** (no Docker — the mic and the SPI/GPIO panel
make container hardware passthrough more trouble than it's worth). Reproducibility
comes from the lockfiles: `uv.lock`, `Gemfile.lock`, `.python-version`,
`.ruby-version`.

## 1. OS + interfaces

Flash Raspberry Pi OS Lite (64-bit). Then on the Pi:

```bash
sudo raspi-config        # Interface Options → enable SPI and I2C (the Inky HAT)
sudo apt update && sudo apt install -y git build-essential libsndfile1 \
     portaudio19-dev fonts-ebgaramond chromium-browser \
     libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev libsqlite3-dev
     # ^ the last line: ruby-build needs these to compile Ruby 4.0.5, + sqlite3 gem
sudo usermod -aG audio,spi,i2c,gpio "$USER"   # mic + panel access; re-login after
```

`fonts-ebgaramond` matters: the panel's SVG falls back to **EB Garamond** for the
serif when Baskerville (a macOS font) is absent, so the type renders the same on
the glass as on the Mac.

## 2. Toolchains (the same managers as the Mac)

```bash
curl https://mise.run | sh            # or rbenv, for Ruby 4.0.5 from .ruby-version
curl -LsSf https://astral.sh/uv/install.sh | sh   # uv (installs its own Python 3.12)
curl -fsSL https://bun.sh/install | bash          # bun (JS)
```

## 3. The app

```bash
git clone <this-repo> ~/birdlife && cd ~/birdlife
cp .env.example .env    # then edit (see below)
make setup              # uv sync, bundle, bun install + build

# Production assets (digested JS/CSS into public/assets) — needs SECRET_KEY_BASE
# set in .env first, since it boots the production env:
cd collage && RAILS_ENV=production bin/rails assets:precompile && cd ..

# Pi-only extras (kept out of the cross-platform lock):
uv pip install inky                       # the Spectra-6 panel driver (SPI/GPIO)
uv run playwright install --with-deps chromium   # headless browser for the shooter
```

`.env` on the device — the brother's house, not Glasnevin, plus the two
production-only keys:

```
BIRD_LAT=53.49      # Connemara coords (his house)
BIRD_LON=-9.88
BIRD_MIN_CONF=0.6
BIRD_MIC=<usb mic name, see: uv run python -c "import sounddevice;print(sounddevice.query_devices())">
BIRD_DB=/home/pi/birdlife/collage/storage/production.sqlite3   # ABSOLUTE; shared by listener + Rails
SECRET_KEY_BASE=<cd collage && RAILS_ENV=production bin/rails secret>
```

There is **one shared SQLite** (`BIRD_DB`): the listener writes the `detections`
table, the web app reads them and owns `species_infos`. The web service's
`db:prepare` creates the file and its tables (in WAL mode) on first boot; the
listener is ordered after it so the DB exists before it writes. No second DB, no
read-only split — `BIRD_DB` is the single source of truth both runtimes point at.

**Confirm the seams before wiring services** (creates the DB, checks the
datastore/locale end to end — should print `all seams good ✓`):

```bash
cd collage && RAILS_ENV=production bin/rails db:prepare && RAILS_ENV=production bin/rails birdlife:doctor && cd ..
```

## 4. Services

```bash
sed -i "s/\bpi\b/$USER/g; s#/home/pi#$HOME#g" deploy/birdlife-*.service   # fix user/paths
sudo cp deploy/birdlife-*.service deploy/birdlife-*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now birdlife-listener birdlife-web birdlife-frame.timer
journalctl -u birdlife-frame -f      # watch panel pushes
```

## 5. First light

- `uv run python shooter/shoot.py --preview /tmp/f.png` then `eog /tmp/f.png` — check the `/station` look before pushing to glass.
- Drop the preview and run `shooter/shoot.py` for real; tune `--rotate` (how the frame hangs) and `--saturation` on the actual panel — colours and dithering differ from the preview, so do a final pass on the glass.

## Offsite backup (Litestream → S3/B2)

The cottage Pi is unattended on flaky broadband, so the detection history is backed
up offsite. WAL is on (`database.yml`); `deploy/birdlife-litestream.service` +
`deploy/litestream.yml` replicate the DB to object storage. `provision.sh` installs
Litestream and enables the service automatically **once the `LITESTREAM_*` keys are
set in `.env`** (bucket, region, access key/secret; `LITESTREAM_ENDPOINT` for B2).
Restore after an SD-card death:

```bash
litestream restore -config deploy/litestream.yml "$BIRD_DB"
```

## Still to wire (deferred)

- **Headless Chromium on ARM** — if `playwright install` is unhappy on the Pi, point
  the shooter at the apt `chromium` instead.
