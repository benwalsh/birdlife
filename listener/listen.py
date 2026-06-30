#!/usr/bin/env python3
"""Turn real birdsong into detections the collage reads.

A desktop stand-in for what BirdNET-Pi does on the device: run Cornell's
BirdNET over audio and write each identified bird into the `detections` table
(the same schema as birds.db) that the Rails app reads. Two modes:

    # Analyse a recording (a WAV/MP3/FLAC, e.g. from xeno-canto.org)
    python listener/listen.py recording path/to/song.wav

    # Listen live on the Mac's microphone until you stop it (Ctrl-C)
    python listener/listen.py listen --seconds 15

Location matters: BirdNET weights its predictions by where/when you are, so the
Connemara coordinates make the results local. Override the rough default with
env vars (keep the brother's exact house coords out of git):

    BIRD_LAT, BIRD_LON       location for species weighting
    BIRD_MIN_CONF            confidence floor (default 0.25)
    BIRD_DB                  detections DB (default collage/storage/development.sqlite3)

Run it through the uv env: `uv run python listener/listen.py ...`.
"""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys
import tempfile
from datetime import datetime
from pathlib import Path

def _install_litert_shim():
    """birdnetlib imports `tflite_runtime.interpreter`. Alias it to the
    cross-platform ai-edge-litert runtime (macOS + Pi, Python 3.10-3.14) so the
    same code runs on both without full TensorFlow. Must run before birdnetlib
    is imported. No-ops if litert is absent (falls back to tensorflow.lite)."""
    import types

    try:
        import ai_edge_litert.interpreter as litert
    except ModuleNotFoundError:
        return
    shim = types.ModuleType("tflite_runtime")
    shim.interpreter = litert
    sys.modules.setdefault("tflite_runtime", shim)
    sys.modules.setdefault("tflite_runtime.interpreter", litert)


_install_litert_shim()

REPO = Path(__file__).resolve().parents[1]

# Rough Connemara centroid — fine for desktop testing. The device uses the
# brother's actual house coordinates (set via env / gitignored config).
DEFAULT_LAT = 53.35
DEFAULT_LON = -9.88
SAMPLE_RATE = 48_000  # BirdNET expects 48 kHz mono


def db_path() -> Path:
    return Path(os.environ.get("BIRD_DB", REPO / "collage" / "storage" / "development.sqlite3"))


def insert_detections(detections: list[dict], source: str, lat: float, lon: float) -> int:
    """Write BirdNET detections into the detections table. Returns rows added."""
    path = db_path()
    if not path.exists():
        sys.exit(f"detections DB not found at {path} — run the Rails app's db:prepare first")
    now = datetime.now()
    rows = [
        (
            now.strftime("%Y-%m-%d"), now.strftime("%H:%M:%S"),
            det["scientific_name"], det["common_name"], float(det["confidence"]),
            lat, lon, int(now.isocalendar().week), source,
        )
        for det in detections
    ]
    con = sqlite3.connect(path)
    con.execute("PRAGMA busy_timeout=5000")  # wait, don't fail, if the app is mid-read
    try:
        con.executemany(
            'INSERT INTO detections '
            '("Date","Time","Sci_Name","Com_Name","Confidence","Lat","Lon","Week","File_Name") '
            "VALUES (?,?,?,?,?,?,?,?,?)",
            rows,
        )
        con.commit()
    finally:
        con.close()
    return len(rows)


def analyze_file(analyzer, path: Path, lat: float, lon: float, min_conf: float) -> list[dict]:
    from birdnetlib import Recording

    rec = Recording(analyzer, str(path), lat=lat, lon=lon, date=datetime.now(), min_conf=min_conf)
    rec.analyze()
    return rec.detections


def report(detections: list[dict]) -> None:
    if not detections:
        print("  (nothing identified)")
        return
    seen: dict[str, float] = {}
    for det in detections:
        name = f"{det['common_name']} ({det['scientific_name']})"
        seen[name] = max(seen.get(name, 0), det["confidence"])
    for name, conf in sorted(seen.items(), key=lambda kv: -kv[1]):
        print(f"  {conf:.0%}  {name}")


def cmd_recording(args, analyzer, lat, lon, min_conf):
    path = Path(args.path)
    if not path.exists():
        sys.exit(f"no such file: {path}")
    print(f"analysing {path.name} (Connemara weighting {lat},{lon}, min {min_conf:.0%})...")
    detections = analyze_file(analyzer, path, lat, lon, min_conf)
    report(detections)
    added = insert_detections(detections, path.name, lat, lon)
    print(f"wrote {added} detections -> {db_path().name}")


def resolve_mic():
    """Pick the input device. BIRD_MIC (a name substring, e.g. "USBMIC1")
    selects a specific mic; unset uses the system default."""
    import sounddevice as sd

    want = os.environ.get("BIRD_MIC")
    inputs = [(i, d["name"]) for i, d in enumerate(sd.query_devices()) if d["max_input_channels"] > 0]
    if not want:
        return None, sd.query_devices(kind="input")["name"]
    for i, name in inputs:
        if want.lower() in name.lower():
            return i, name
    sys.exit(f"no input device matching BIRD_MIC={want!r}. Available: " +
             ", ".join(n for _, n in inputs))


def cmd_listen(args, analyzer, lat, lon, min_conf):
    import soundfile as sf
    import sounddevice as sd

    device, mic_name = resolve_mic()
    print(f"listening on '{mic_name}' in {args.seconds}s chunks (Ctrl-C to stop)...")
    try:
        while True:
            audio = sd.rec(int(args.seconds * SAMPLE_RATE), samplerate=SAMPLE_RATE,
                           channels=1, device=device)
            sd.wait()
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                sf.write(tmp.name, audio, SAMPLE_RATE)
                detections = analyze_file(analyzer, Path(tmp.name), lat, lon, min_conf)
            os.unlink(tmp.name)
            stamp = datetime.now().strftime("%H:%M:%S")
            if detections:
                print(f"[{stamp}] heard:")
                report(detections)
                insert_detections(detections, "live-mic", lat, lon)
            else:
                print(f"[{stamp}] quiet")
    except KeyboardInterrupt:
        print("\nstopped.")


def main():
    ap = argparse.ArgumentParser(description="Run BirdNET over audio into the collage's detections table.")
    sub = ap.add_subparsers(dest="mode", required=True)
    rec = sub.add_parser("recording", help="analyse an audio file")
    rec.add_argument("path")
    live = sub.add_parser("listen", help="listen live on the microphone")
    live.add_argument("--seconds", type=int, default=15, help="chunk length (default 15)")
    args = ap.parse_args()

    lat = float(os.environ.get("BIRD_LAT", DEFAULT_LAT))
    lon = float(os.environ.get("BIRD_LON", DEFAULT_LON))
    min_conf = float(os.environ.get("BIRD_MIN_CONF", 0.25))

    print("loading BirdNET (first run downloads the model)...")
    from birdnetlib.analyzer import Analyzer
    analyzer = Analyzer()

    (cmd_recording if args.mode == "recording" else cmd_listen)(args, analyzer, lat, lon, min_conf)


if __name__ == "__main__":
    main()
