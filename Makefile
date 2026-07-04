# Connemara bird detector — local dev tasks. Run from the repo root.
# `make` or `make help` lists everything. Config lives in .env (gitignored).
.ONESHELL:
SHELL := /bin/bash

PORT ?= 4030
POSES ?= 1

.PHONY: help setup serve listen analyze regen restyle cutout declutter masks build doctor armcheck test lint

help:  ## list the available tasks
	@grep -hE '^[a-z][a-zA-Z-]*:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## / — /' | sort

setup:  ## install all deps (Python, Ruby, JS) and prepare the database
	uv sync
	cd collage && bundle install && bun install && bin/rails stimulus:manifest:update && bin/vite build && bin/rails db:prepare

serve:  ## run the collage web app  (override with: make serve PORT=4030)
	cd collage && bin/rails server -p $(PORT)

# NB: lines are joined with `\` so `source .env` and the command share one shell.
# macOS ships GNU Make 3.81, which ignores .ONESHELL, so each bare line would
# otherwise run in its own shell and lose the sourced env.
listen:  ## listen on the window mic and write detections (Ctrl-C to stop)
	set -a; source .env; set +a; \
	uv run python listener/listen.py listen

push:  ## push new local detections up to the cloud mirror (reads CLOUD_INGEST_* from .env)
	set -a; source .env; set +a; \
	uv run python listener/push.py

analyze:  ## analyse a recording:  make analyze FILE=path/to/song.wav
	set -a; source .env; set +a; \
	uv run python listener/listen.py recording "$(FILE)"

regen:  ## regenerate one bird's art:  make regen SPECIES="Corvus monedula|Eurasian Jackdaw"
	set -a; source .env; set +a; \
	uv run python avian/scripts/pregen.py --species "$(SPECIES)" --poses 1 --force && \
	uv run python avian/scripts/cutout_flood.py

cutout:  ## flood-cut any cream-ground illustrations to transparent
	uv run python avian/scripts/cutout_flood.py

declutter:  ## sweep stray flecks ("smudges") from existing cutouts, then rebuild masks
	uv run python avian/scripts/cutout_flood.py --declutter
	uv run python avian/scripts/build_masks.py --json avian/assets/illustrations/masks.json

masks:  ## rebuild collage silhouette masks (run after changing the illustration set)
	uv run python avian/scripts/build_masks.py --json avian/assets/illustrations/masks.json

restyle:  ## redraw the whole Irish library in the current prompt style, then cut + remask  (POSES="1 2" adds flight)
	set -a; source .env; set +a; \
	uv run python avian/scripts/irish_labels.py > /tmp/irish-labels.txt; \
	echo "restyling $$(grep -c . /tmp/irish-labels.txt) Irish species (poses $(POSES))..."; \
	uv run python avian/scripts/pregen.py --labels /tmp/irish-labels.txt --poses $(POSES) --force && \
	uv run python avian/scripts/cutout_flood.py && \
	uv run python avian/scripts/build_masks.py --json avian/assets/illustrations/masks.json

frame-preview:  ## dither /station to a PNG to inspect the Inky look (no hardware)
	uv run python shooter/shoot.py --url http://localhost:$(PORT)/station --preview $(or $(OUT),frame.png)

frame:  ## push the panel to the Inky  (Pi only)
	uv run python shooter/shoot.py --url http://localhost:$(PORT)/station

purge:  ## clear all detections (reset the collage to empty)
	cd collage && bin/rails runner 'puts "cleared #{Detection.delete_all} detections"'

build:  ## register Stimulus controllers + build the Vite bundle (JS + React SPA)
	cd collage && bin/rails stimulus:manifest:update && bin/vite build

doctor:  ## verify the Python<->Rails<->datastore seams + Irish locale (bring-up check)
	cd collage && bin/rails birdlife:doctor

armcheck:  ## validate the macOS->Pi gap in an arm64 Debian container (deps, native gem builds, Irish locale)
	docker build -f deploy/Dockerfile.armcheck -t birdlife-armcheck .
	docker run --rm birdlife-armcheck

test:  ## run the Rails specs
	cd collage && bin/rspec

lint:  ## run RuboCop
	cd collage && bin/rubocop
