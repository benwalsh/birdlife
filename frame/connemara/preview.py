"""Render a panel to a PNG for desktop iteration.

    cd frame
    python -m connemara.preview --mode now   --out card.png
    python -m connemara.preview --mode today --out today.png
    python -m connemara.preview --mode now --empty --out empty.png

By default it writes the Spectra-6 dither (what the panel roughly shows). Pass
``--no-dither`` for the clean RGB, useful when tuning type and spacing.
"""
from __future__ import annotations

import argparse

from . import render
from .mockdata import sample_state, empty_state


def main():
    ap = argparse.ArgumentParser(description="Render a Connemara frame to PNG.")
    ap.add_argument("--mode", choices=("now", "today"), default="now")
    ap.add_argument("--out", default="preview.png")
    ap.add_argument("--empty", action="store_true", help="render the no-detections state")
    ap.add_argument("--no-dither", action="store_true", help="write clean RGB, not the 6-ink dither")
    args = ap.parse_args()

    state = empty_state() if args.empty else sample_state()
    img = render.render(state, mode=args.mode)
    if not args.no_dither:
        img = render.dither_spectra6(img)
    img.save(args.out)
    print(f"wrote {args.out} ({args.mode}{', empty' if args.empty else ''},"
          f" {'rgb' if args.no_dither else 'dither'})")


if __name__ == "__main__":
    main()
