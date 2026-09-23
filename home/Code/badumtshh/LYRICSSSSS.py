#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://lrclib.net"
UA = "lrcfetch v1.0 (personal library script; no homepage)"


def http_get_json(url, retries=2):
    req = urllib.request.Request(
        url, headers={"User-Agent": UA, "Accept": "application/json"}
    )

    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None

            if e.code == 429 and attempt < retries:
                wait = e.headers.get("Retry-After", "5")
                try:
                    wait = float(wait)
                except ValueError:
                    wait = 5.0
                time.sleep(min(wait, 60))
                continue

            return None
        except Exception:
            return None

    return None


def probe(path):
    cmd = [
        "ffprobe", "-v", "error",
        "-print_format", "json",
        "-show_format",
        str(path),
    ]

    try:
        r = subprocess.run(cmd, check=True, text=True, capture_output=True)
        fmt = json.loads(r.stdout).get("format", {})
    except Exception:
        return {}

    raw = fmt.get("tags", {}) or {}
    tags = {}

    for k, v in raw.items():
        nk = re.sub(r"[^a-z0-9]", "", str(k).lower())
        if nk and (nk not in tags or not tags[nk]):
            tags[nk] = str(v)

    def first(*keys):
        for k in keys:
            v = tags.get(k)
            if v and v.strip():
                return v.strip()
        return ""

    try:
        duration = float(fmt.get("duration", 0))
    except (TypeError, ValueError):
        duration = 0.0

    return {
        "title": first("title"),
        "artist": first("artist") or first("albumartist"),
        "album": first("album"),
        "duration": duration,
    }


def guess_from_path(p: Path):
    # fallback for your processed layout: Artist/Album[/Disc NN]/NN - Title.ext
    title = re.sub(r"^\d{1,3}[\s._\-]+", "", p.stem).strip() or p.stem

    parent = p.parent
    if parent.name.lower().startswith("disc"):
        album = parent.parent.name
        artist = parent.parent.parent.name
    else:
        album = parent.name
        artist = parent.parent.name

    return {"title": title, "artist": artist, "album": album}


def best_match(results, duration, tolerance, allow_plain):
    cands = [
        r
        for r in results
        if isinstance(r, dict)
        and (r.get("syncedLyrics") or (allow_plain and r.get("plainLyrics")))
    ]

    if not cands:
        return None

    if duration:
        within = [
            r for r in cands
            if abs(float(r.get("duration") or 0) - duration) <= tolerance
        ]
        if not within:
            return None
        cands = within

    cands.sort(key=lambda r: abs(float(r.get("duration") or 0) - duration) if duration else 0)
    return cands[0]


def lookup(track, artist, album, duration, tolerance, allow_plain):
    q = {"track_name": track, "artist_name": artist}
    if album:
        q["album_name"] = album
    if duration:
        q["duration"] = str(int(round(duration)))

    # 1: exact signature (lrclib matches duration +-2s)
    rec = http_get_json(API + "/api/get?" + urllib.parse.urlencode(q))
    if rec and rec.get("syncedLyrics"):
        return rec, "exact"

    # 2: same but without duration
    if duration:
        q2 = {k: v for k, v in q.items() if k != "duration"}
        rec = http_get_json(API + "/api/get?" + urllib.parse.urlencode(q2))
        if rec and rec.get("syncedLyrics"):
            return rec, "exact-nodur"

    # 3: structured search, duration-filtered
    qs = {"track_name": track, "artist_name": artist}
    results = http_get_json(API + "/api/search?" + urllib.parse.urlencode(qs)) or []
    rec = best_match(results, duration, tolerance, allow_plain)
    if rec:
        return rec, "search"

    # 4: free text
    results = http_get_json(
        API + "/api/search?" + urllib.parse.urlencode({"q": f"{track} {artist}"})
    ) or []
    rec = best_match(results, duration, tolerance, allow_plain)
    if rec:
        return rec, "freetext"

    return None, None


def lrc_targets(dest: Path, mode: str):
    if mode == "none":
        return []

    out = []

    if mode in ("stem", "both"):
        out.append(dest.with_suffix(".lrc"))

    if mode in ("opus", "both"):
        out.append(dest.parent / (dest.name + ".lrc"))

    return out


def has_lrc(dest: Path):
    return any(t.exists() for t in lrc_targets(dest, "both"))


def main():
    ap = argparse.ArgumentParser(description="fetch synced .lrc from lrclib for files missing them")
    ap.add_argument("directory", type=Path, help="folder to scan (recursive)")
    ap.add_argument(
        "--ext",
        nargs="+",
        default=[
            "opus", "ogg", "oga",
            "mp3", "mp2", "mpga",
            "flac", "wv", "ape", "tta", "tak", "ofr", "ofs",
            "wav", "aiff", "aif", "aifc",
            "m4a", "m4b", "mp4", "mka", "webm",
            "aac", "wma", "ra", "ram", "rm",
            "dsf", "dff",
        ],
        help="audio extensions to scan (without the dot)",
    )
    ap.add_argument("--force", action="store_true", help="refetch even if .lrc exists")
    ap.add_argument("--dry-run", action="store_true", help="show what would be fetched")
    ap.add_argument("--tolerance", type=float, default=2.0, help="max duration diff in seconds for search fallback")
    ap.add_argument("--allow-plain", action="store_true", help="fall back to unsynced lyrics if no synced exists")
    ap.add_argument("--delay", type=float, default=0.3, help="seconds between api requests")
    ap.add_argument(
        "--lrc",
        choices=["stem", "opus", "both"],
        default="both",
        help=(
            "where to write .lrc relative to the source: "
            "stem=replace source extension with .lrc, "
            "opus=append .lrc to the source filename, both=write both"
        ),
    )
    args = ap.parse_args()

    root = args.directory.expanduser().resolve()
    if not root.is_dir():
        sys.exit(f"not a directory: {root}")

    exts = {e.lower().lstrip(".") for e in args.ext}

    files = sorted(
        p
        for p in root.rglob("*")
        if p.is_file() and p.suffix.lower().lstrip(".") in exts
    )

    if not files:
        sys.exit(f"no audio files found in {root}")

    counts = {"written": 0, "skipped": 0, "miss": 0, "instrumental": 0, "fail": 0}

    for p in files:
        if has_lrc(p) and not args.force:
            counts["skipped"] += 1
            continue

        meta = probe(p)
        guess = guess_from_path(p)

        title = meta.get("title") or guess["title"]
        artist = meta.get("artist") or guess["artist"]
        album = meta.get("album") or guess["album"]
        duration = meta.get("duration") or 0.0

        if not title or not artist:
            print(f"fail {p}: no title/artist in tags or path")
            counts["fail"] += 1
            continue

        if args.dry_run:
            print(f"would fetch: {artist} - {title} (album={album or '?'}, dur={duration or '?'})")
            continue

        rec, how = lookup(title, artist, album, duration, args.tolerance, args.allow_plain)

        if rec is None:
            print(f"miss {p}: {artist} - {title}")
            counts["miss"] += 1
        elif rec.get("instrumental") or not (rec.get("syncedLyrics") or (args.allow_plain and rec.get("plainLyrics"))):
            print(f"instrumental {p}: {artist} - {title}")
            counts["instrumental"] += 1
        else:
            content = rec.get("syncedLyrics") or rec.get("plainLyrics") or ""
            if not content.endswith("\n"):
                content += "\n"

            for t in lrc_targets(p, args.lrc):
                t.parent.mkdir(parents=True, exist_ok=True)
                t.write_text(content, encoding="utf-8")

            print(f"lrc {p} [{how}]")
            counts["written"] += 1

        time.sleep(args.delay)

    print(
        f"done: written={counts['written']} skipped={counts['skipped']} "
        f"miss={counts['miss']} instrumental={counts['instrumental']} fail={counts['fail']}"
    )


if __name__ == "__main__":
    main()
