# CLAUDE.md — AvianVisitors Bird Detector (Connemara build)

## What this project is

A bird-detection-and-display device, built as a birthday present for my brother,
for his **holiday cottage** in Connemara, Ireland (a spot with abundant bird life —
coastal, bog, and moorland species). The cottage is a rental let / guest house, not
his full-time residence, so the device is also a small amenity for visiting guests.

The device listens for birdsong on an outdoor microphone, identifies species
acoustically using Cornell Lab's **BirdNET** model, and displays the results on a
framed e-ink panel indoors. Built on top of the **AvianVisitors** project
(github.com/Twarner491/AvianVisitors).

The frame will be hand-made from Connemara **bog oak or bog pine** — a shadow-box
style enclosure with the panel front and a recessed cavity behind for the Pi.

## Current state (advanced — running end-to-end on macOS)

The project is well past initial setup. It runs end-to-end on macOS, driven all day
off a desk microphone, with:

- **Python detection/display core** working (BirdNET capture → identification →
  Inky rendering via simulator/mock mode).
- **Web layer converted from the upstream PHP to Rails** — the dashboard is now a
  Rails app (chosen deliberately: puts the web layer in Ruby, where I'm fluent,
  and leaves Python only where the BirdNET/Inky ecosystem requires it).
- **Gemini prompting reworked** for the bird illustrations.
- **Irish-language translations** added and working.
- **Makefile** built out for the common tasks.
- Image pipeline (Python/Pillow): clean illustrations on **minimal backgrounds**
  (deliberately distraction-free), background pass + flight-image pass done as a
  build-time step on the desktop; the Pi only ever loads finished rendered assets.

So the active question is **headless Pi deployment of an advanced, working app** —
bring-up and confirmation, not building from scratch. Do as little debugging as
possible on the Pi itself; everything solvable on macOS should be solved first.

## Architecture

**Outdoor-listening, indoor-display.**

- Microphone mounted **outside** in a sheltered spot (under an eave/soffit, lee side
  away from the prevailing south-westerlies), with a fur windscreen against Atlantic
  wind.
- A short cable run (**no more than 2 metres**) through the wall to the Pi.
- **Single Pi indoors** driving the e-ink panel — the 2m distance keeps us within
  USB spec, so no second Pi and no USB-over-Cat5 extender are needed. (The 2m run
  also gives free EMI isolation: never plug the USB sound card straight into the Pi.)
- Wall penetration: drilled at a slight downward angle (sheds water), with a drip
  loop on the outside and exterior silicone/grommet seal.

**Two runtimes on the Pi:** Python core + Rails web app, both running headless on
boot, talking to each other and a shared datastore. This is the main new
deployment surface — see Deployment below.

## Hardware

| Component | Choice | Status |
|---|---|---|
| Compute | Raspberry Pi 4 (4GB), db-tronic bundle kit | **Ordered** |
| — bundle includes | Official 15W USB-C PSU, 64GB microSD, card reader, 4× aluminium heatsinks, official black case, micro-HDMI cable | |
| Display | Pimoroni Inky Impression 7.3" (E Ink Spectra 6, 800×480, 6-colour) | **In hand** |
| Microphone | Clippy EM272 (3.5mm plug-in-power) + USB sound card | To source |
| — mic extras | Fur windscreen ("deadcat"), 2m active USB cable | To source |
| Frame | Connemara bog oak or bog pine, shadow-box style | To source |

### Hardware notes

- **Display rationale:** Inky chosen over the Waveshare 7.3" (same underlying E6
  panel) for its mature Python library, superior dithering, drop-in compatibility,
  fully assembled/solderless on the 40-pin header, and four rear buttons usable for
  cycling display modes. The 13.3" Inky was ruled out on cost (~€300+ all-in).
- **Thermals:** the bundle's official case + stick-on heatsinks (no fan) are fine —
  indoors, cool ambient. NB the Pi now also runs a Rails app alongside BirdNET, so
  keep the Rails side lean (see Deployment) and keep half an eye on temps under the
  heavier two-runtime load. A vent/fan or Flirc swap remains an easy later upgrade.
- **Micro-HDMI cable** is unused in the final headless build; handy for dev only.

### Microphone — decisions locked from market review

- **Capsule:** Primo EM272 — the reference choice for nature/birdsong; far more
  sensitive than a generic USB mic.
- **Get the 3.5mm plug-in-power Clippy, NOT the XLR version.** The XLR needs
  12–48V phantom power a simple USB sound card can't supply; the 3.5mm version works
  precisely because it lacks that circuitry.
- **Plug-match gotcha:** EM272 comes in TRS vs TRRS; the USB sound card dictates
  which. People buy the wrong one and return it. **Pick the sound card first, then
  buy the matching plug variant — ideally from one vendor** so compatibility is
  guaranteed.
- **Sound card:** cheap 16-bit USB adapter (UGREEN-type). Don't pay for 24-bit —
  pointless given mic SNR.
- **Wiring:** capsule outside on its thin lead, USB sound card + everything else
  indoors and dry. This is the standard, most weather-robust arrangement.
- **Vendors:** Micbooster (UK) or **Veldshop (Netherlands)** — Veldshop is inside
  the EU, so easier delivery/customs to Ireland (same logic as the Inky).

### Weatherproofing (Connemara = severe; wind is the real enemy)

- **Placement over wrapping.** A genuinely sheltered spot under an eave beats a mic
  strangled in plastic (plastic muffles the sound). The mounting spot is the single
  biggest determinant of detection quality — worth waiting to survey the house.
- **Fur deadcat, not thin foam** — foam is for indoor plosives; fur handles Atlantic
  wind. Mount so the windscreen can be swapped without dismantling (it mats/degrades
  outdoors over a season or two; salt air if coastal).
- **Drip loop** below any overhang; **capsule pointed slightly downward**; seal the
  wall penetration with a cured cable gland / silicone.
- **Never squeeze a wet cover while on the mic** — forces water into the capsule.
  (A maintenance habit to pass to my brother.)

## Software approach

**Two languages, deliberately:**
- **Python** for the BirdNET detection core, the Inky/image pipeline (Pillow), and
  anything the model/display ecosystem forces. Don't fight this — BirdNET is a
  TFLite model with a Python wrapper; the whole detection/display world is Python.
- **Ruby/Rails** for the web dashboard (converted from upstream PHP). This is where
  I'm fluent, so the web layer lives here.
- **The datastore is the contract between them.** Keep schema changes additive so
  neither runtime surprises the other. Locale/encoding for Irish text (fadas) must
  be correct on both sides.

### Develop on macOS, deploy to Pi — and minimise on-Pi work

Treat the Pi as a **deployment/confirmation target**, not a dev environment. Aim for
a Pi session that is *flash → SSH in → run provisioning → run smoke-tests → confirm*,
with no open-ended debugging.

**What macOS can't fully exercise (first real run is on the Pi):**
- **Audio capture device layer.** Capture *logic* is proven on macOS via CoreAudio,
  but the Pi uses **ALSA** with the USB sound card — different device enumeration.
  This is the one seam to expect a small wrestle with (and it's also gated on
  sourcing the mic).
- **Inky real-glass tuning.** The simulator only approximates Spectra 6; real colour
  and refresh differ — always do a final tuning pass on the panel.
- **GPIO/SPI, button handling**, and **thermals under sustained two-runtime load.**

**Isolate platform/hardware seams** behind single clear abstractions (audio device
selection, filesystem paths, subprocess calls, the Inky/GPIO interface) so the
macOS/mock path and the Pi path differ in config in one place — not logic scattered
through the codebase.

**Dependency discipline:** pinned `requirements.txt` (Python) + the Rails
Gemfile.lock, plus a written list of system packages with their **apt/Debian
equivalents** for anything installed via Homebrew on macOS. Rails native extensions
on ARM Debian have their own install quirks, separate from Python's. Resolve these
on macOS / in the ARM container, not on the Pi.

## Pre-Pi validation: ARM Debian container (Docker Desktop)

Docker Desktop is running full-time. Use an **ARM64 `debian:bookworm` container** to
catch the real macOS→Pi gap *before ever touching the Pi*: dependency installs on ARM
Debian, Rails native-extension builds, the two-service setup, and **Irish-text locale
rendering** under a Debian locale config.

**Do NOT bother with a full Pi board emulator (QEMU).** It emulates the Pi's GPIO/SPI
(Inky) and USB-audio peripherals poorly or not at all — exactly the bits that need
real hardware (which the real Pi will do for real). The container is the 80/20.

Bonus: a container that builds and runs both services is most of the way to a
containerised deployment if that's ever wanted.

## Deployment (headless Pi)

- **Flash from macOS** with Raspberry Pi OS Lite (64-bit, Bookworm) via the card
  reader: set hostname, enable SSH, bake in Wi-Fi at flash time so it boots headless
  and SSH-ready first boot.
- **Provisioning script** for a fresh Lite install, end-to-end: system packages,
  SPI enablement, Python venv + deps, Ruby/Rails environment + bundle, **systemd
  units for both runtimes with correct boot ordering/dependencies**, and Tailscale
  join (below). Goal: "flash → SSH → run script → done."
- **Lean Rails for a constrained box:** production mode, asset precompilation at
  build time (not boot), no dev/test gems dragged in, mind the memory footprint —
  it shares a Pi 4 with continuous BirdNET inference.
- **Inky smoke-test:** a minimal standalone script that pushes one finished bird
  image to the real panel and exits — separates "is the hardware/wiring good" from
  "does the app work" on day one.

### Multiple Wi-Fi networks + handover

The unit is built here but lives at the cottage. **Pre-load both networks** (here +
the cottage) in NetworkManager so it associates with whichever it sees. Get the
cottage SSID/password in advance if possible. As a safety net for a headless box at
a location I don't control, consider an **AP-fallback** (Pi raises its own hotspot if
no known network is found, with a small web page to enter local creds), so nothing
needs dismantling on the day. **Keep Wi-Fi creds out of git.**

### Remote access — Tailscale (NOT cloud deployment)

Guests just look at the Inky on the wall — no web surface needed for them. But my
brother (or I) may want to keep a remote eye on it. Use **Tailscale**:

- No inbound config at the cottage — no port-forwarding, static IP, or router
  fiddling; works behind rural broadband / CGNAT. Critical for a box at a location
  I don't control.
- **Private by default** — only authorised devices on the tailnet reach it; nothing
  exposed publicly.
- Free at this scale, fit-and-forget.
- **Gives remote SSH** to the Pi — the real long-term win for an unattended cottage
  box: restart a wedged service, check logs, push updates, all from Dublin without a
  drive to Connemara.
- **Join Tailscale as part of the provisioning script** so the Pi comes up already
  on the tailnet.

Cloudflare Tunnel is the alternative *if* a public URL for wider family is ever
wanted ("birds.thecottage.ie"); Tailscale is simpler/more private for "just us + SSH"
and is the default. **None of this is cloud deployment** — the Pi keeps running
everything; this is only a private, outbound-only remote-access layer.

## Customisation goals

1. **Connemara-weighted species** — location/coordinates set so BirdNET weights
   toward local birds (chough, stonechat, meadow pipit, waders, etc.). *(Working.)*
2. **Bilingual display — Irish + English names** (e.g. *Cág cosdearg* for chough).
   Centrepiece feature. *(Working.)*
3. **Alerts & daily report — themed for the rental-cottage context.** Stays on the
   Pi (no cloud): rarity/vagrant alerts ("a scarlet tanager!"), seasonal-first alerts
   ("first cuckoo of the year!"), and a daily digest. Email/Telegram/Pushover.
4. **Durability concern (not a dashboard concern):** the cottage Pi is unattended for
   long stretches on flaky rural broadband with nobody to power-cycle it. Make sure
   detections aren't *only* on the SD card — an offsite push (e.g. BirdWeather, or a
   periodic backup) means a card failure doesn't lose the cottage's bird history.

## Repo strategy

Private copy with upstream remote (not a plain GitHub fork, which can't be private):
clone upstream → new **private** repo as `origin` → keep original as `upstream` for
pulling fixes. Single source of truth; deploy to the Pi from it.

**Check the LICENSE** of AvianVisitors / BirdNET before assuming distribution rights
— copyleft and/or non-commercial terms are likely. A private personal copy is fine;
distribution is where obligations bite. *(Record what the LICENSE actually says here
once checked, so it's answered once.)*

**Keep environment-specific values out of committed code** — cottage coordinates,
Wi-Fi creds, notification tokens, Tailscale keys. Config files / env vars,
`.gitignore`d.

## Build sequence (updated)

No fixed deadline — a relaxed build, done right rather than fast; the components
arrive whenever they arrive.

1. **Done:** end-to-end on macOS — Python core, Rails dashboard, Gemini prompting,
   Irish translations, image pipeline, Makefile.
2. **On macOS / in the ARM Debian container (the prep phase):** pin deps + apt
   equivalents; isolate platform/hardware seams; validate on the ARM Debian container
   (deps, Rails native builds, Irish locale); write the provisioning script, the
   Wi-Fi/Tailscale config, and the Inky smoke-test; flash the SD card (Lite 64-bit,
   SSH, Wi-Fi).
3. **Once the Pi's set up:** flash done → SSH in → run provisioning → Inky smoke-test →
   run app against WAV files to confirm the move. Confirmation, not building.
4. **With the mic (after surveying the cottage mounting spot):** wire up the ALSA /
   USB-sound-card capture seam; outdoor install + wall run.
5. **Finally:** build/finish the bog oak frame; real-glass render tuning; mount.

### Frame notes (for later)
Bog oak is hard and can be brittle/chip-prone — pre-drill everything, light passes
when routing the panel rebate. Leave a ventilation gap; don't fully seal the Pi in
(more relevant now it runs two services). Finish with oil or wax (not heavy varnish)
to show off the dark grain. Irish suppliers (Connemara and the midland bogs) sell
offcuts suited to small frames.
