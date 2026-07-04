#!/usr/bin/env python3
"""Lazy Pi -> cloud push (the cold path).

Reads new rows from the shared detections SQLite and POSTs them to the cloud
ingest endpoint, so culfinbirds.net mirrors what the wall has heard. The Pi stays
the source of truth; this is a one-way, best-effort, eventually-consistent copy.

  * Offline-tolerant: on any failure the high-water cursor is NOT advanced, so the
    next run re-sends and catches up. Nothing is lost, the listener never blocks.
  * Idempotent: each row carries a dedupe_key (SHA-256 of the same columns the
    cloud's unique index uses), so re-POSTing a batch never double-inserts.

Run by birdlife-push.timer (~15 min). No-ops unless CLOUD_INGEST_URL and
CLOUD_INGEST_TOKEN are set — so it does nothing on a stand-alone (offline) Pi.
"""

import hashlib
import json
import os
import sqlite3
import sys
import urllib.error
import urllib.request
from pathlib import Path

from listen import db_path  # reuse the shared-DB locator

BATCH = 500
# High-water mark: the id of the last detection pushed. Repo-root, gitignored —
# it's device sync state, deliberately NOT in the shared DB.
CURSOR = Path(__file__).resolve().parent.parent / ".sync_cursor"

# Columns sent to the cloud (everything the listener writes). id is the cursor,
# not part of the payload — the cloud assigns its own primary key.
COLUMNS = ['Date', 'Time', 'Sci_Name', 'Com_Name', 'Confidence', 'Lat', 'Lon', 'Week', 'File_Name']
# The subset hashed into the dedupe_key — must match the cloud's expectation
# (Detection dedupe: Date|Time|Sci_Name|Confidence|File_Name).
KEY_COLUMNS = ['Date', 'Time', 'Sci_Name', 'Confidence', 'File_Name']


def dedupe_key(row: dict) -> str:
    raw = '|'.join(str(row[c]) for c in KEY_COLUMNS)
    return hashlib.sha256(raw.encode('utf-8')).hexdigest()


def read_cursor() -> int:
    try:
        return int(CURSOR.read_text().strip())
    except (FileNotFoundError, ValueError):
        return 0


def write_cursor(last_id: int) -> None:
    CURSOR.write_text(str(last_id))


def new_rows(con: sqlite3.Connection, since_id: int) -> list[dict]:
    cols = ','.join(f'"{c}"' for c in COLUMNS)
    cur = con.execute(
        f'SELECT id,{cols} FROM detections WHERE id > ? ORDER BY id LIMIT ?',
        (since_id, BATCH),
    )
    return [dict(r) for r in cur.fetchall()]


def post(url: str, token: str, rows: list[dict]) -> bool:
    body = json.dumps({'detections': rows}).encode('utf-8')
    req = urllib.request.Request(
        url, data=body, method='POST',
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {token}'},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status == 200
    except urllib.error.URLError as err:
        print(f'push failed, will retry next run: {err}', file=sys.stderr)
        return False


def main() -> None:
    url = os.environ.get('CLOUD_INGEST_URL')
    token = os.environ.get('CLOUD_INGEST_TOKEN')
    if not url or not token:
        print('CLOUD_INGEST_URL / CLOUD_INGEST_TOKEN unset — nothing to push')
        return

    dry_run = '--dry-run' in sys.argv
    con = sqlite3.connect(db_path())
    con.row_factory = sqlite3.Row
    since = read_cursor()
    pushed = 0
    try:
        while True:
            rows = new_rows(con, since)
            if not rows:
                break
            last_id = rows[-1]['id']
            payload = [{**{c: r[c] for c in COLUMNS}, 'dedupe_key': dedupe_key(r)} for r in rows]

            if dry_run:
                print(json.dumps(payload[:2], indent=2, ensure_ascii=False))
                print(f'... {len(payload)} rows since id {since} (dry run — not sent)')
                break

            if not post(url, token, payload):
                break  # leave the cursor; next tick retries from here
            since = last_id
            write_cursor(since)
            pushed += len(rows)
            if len(rows) < BATCH:
                break
    finally:
        con.close()
    print(f'pushed {pushed} detections; cursor at id {since}')


if __name__ == '__main__':
    main()
