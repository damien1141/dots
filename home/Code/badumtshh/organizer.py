#!/usr/bin/env python3
import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


AUDIO_EXTS = {
    "aac", "aif", "aiff", "alac", "ape", "dff", "dsf", "flac",
    "m4a", "m4b", "m4p", "mp3", "mpc", "ofr", "ofs", "ogg",
    "opus", "spx", "tak", "tta", "wav", "wma", "wv",
}


def truncate_bytes(s, max_bytes):
    b = s.encode("utf-8")
    if len(b) <= max_bytes:
        return s
    return b[:max_bytes].decode("utf-8", "ignore").rstrip(" .")


def norm_key(k):
    return re.sub(r"[^a-z0-9]", "", str(k).lower())


def clean_component(s, max_len=150, max_bytes=180):
    if s is None:
        return ""
    s = str(s)
    s = re.sub(r'[\x00-\x1f\x7f<>:"/\\|?*]+', " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    s = s.strip(" .")

    if len(s) > max_len:
        s = s[:max_len].rstrip(" .")

    s = truncate_bytes(s, max_bytes)
    return s.strip(" .")


def get_tag(tags, keys):
    for k in keys:
        v = tags.get(k)
        if v is not None:
            v = str(v).strip()
            if v:
                return v
    return ""


def probe_tags(path):
    cmd = [
        "ffprobe", "-v", "error",
        "-print_format", "json",
        "-show_format",
        str(path),
    ]

    try:
        r = subprocess.run(cmd, check=True, text=True, capture_output=True)
        import json
        data = json.loads(r.stdout)
    except Exception:
        return {}

    raw = data.get("format", {}).get("tags", {}) or {}
    tags = {}

    for k, v in raw.items():
        nk = norm_key(k)
        if nk and (nk not in tags or not tags[nk]):
            tags[nk] = str(v)

    return tags


def parse_first_int(s):
    if not s:
        return None
    s = str(s)
    if "/" in s:
        s = s.split("/", 1)[0]
    m = re.search(r"\d+", s)
    return int(m.group(0)) if m else None


def parse_track_number(s):
    if not s:
        return None
    s = str(s)
    if "/" in s:
        s = s.split("/", 1)[0]
    m = re.fullmatch(r"\s*\d+\s*[-–]\s*(\d+)\s*", s)
    if m:
        return int(m.group(1))
    m = re.search(r"\d+", s)
    return int(m.group(0)) if m else None


def parse_total_int(s):
    if not s:
        return None
    s = str(s)
    if "/" in s:
        s = s.split("/", 1)[1]
    m = re.search(r"\d+", s)
    return int(m.group(0)) if m else None


def parse_year(tags):
    date = get_tag(tags, ["date", "year", "originaldate"])
    m = re.search(r"\b(\d{4})\b", date)
    return m.group(1) if m else ""


def filename_guess(stem):
    s = str(stem).strip()

    m = re.match(r"^(\d{1,3})[\s._\-]+(.+)$", s)
    if m:
        return int(m.group(1)), clean_component(m.group(2), 160, 200)

    m = re.match(r"^(\d{1,3})$", s)
    if m:
        return int(m.group(1)), ""

    return None, clean_component(s, 160, 200)


def make_file_name(track_num, track_total, title, original_stem):
    title = clean_component(title or original_stem, 160, 200)
    if not title:
        title = "track"

    if track_num is not None:
        pad = 2
        if track_total is not None and track_total > 0:
            pad = max(2, len(str(track_total)))

        num = str(track_num).zfill(pad)
        return clean_component(f"{num} - {title}", 200, 220)

    return clean_component(title, 200, 220)


def unique_path(rel: Path, taken):
    key = str(rel).casefold()
    if key not in taken:
        return rel

    parent = rel.parent
    stem = rel.stem
    suffix = rel.suffix
    i = 1

    while True:
        cand = parent / f"{stem} [{i}]{suffix}"
        cand_key = str(cand).casefold()
        if cand_key not in taken:
            return cand
        i += 1


def unique_lrc_path(path):
    if not path.exists():
        return path
    parent = path.parent
    stem = path.stem
    suffix = path.suffix
    i = 1
    while True:
        cand = parent / f"{stem} [{i}]{suffix}"
        if not cand.exists():
            return cand
        i += 1


def under(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def find_associated_lrcs(audio_path):
    """Return list of (lrc_path, type) where type is 'stem' or 'full'."""
    stem = audio_path.stem.lower()
    full = audio_path.name.lower()
    results = []

    try:
        for p in audio_path.parent.iterdir():
            if not p.is_file() or p.suffix.lower() != ".lrc":
                continue
            if p.stem.lower() == stem:
                results.append((p, "stem"))
            elif p.stem.lower() == full:
                results.append((p, "full"))
    except OSError:
        pass

    return results


def read_items(files, args):
    items = []

    for src in files:
        tags = probe_tags(src)

        albumartist = get_tag(tags, ["albumartist", "albumartists"])
        artist = get_tag(tags, ["artist"])
        album = get_tag(tags, ["album"])
        title = get_tag(tags, ["title"])

        track_tag = get_tag(tags, ["tracknumber", "track"])
        tracktotal_tag = get_tag(tags, ["tracktotal", "totaltracks"])

        disc_tag = get_tag(tags, ["discnumber", "disc"])
        disctotal_tag = get_tag(tags, ["disctotal", "totaldiscs"])

        year = parse_year(tags)

        track_num = parse_track_number(track_tag)
        track_total = parse_total_int(tracktotal_tag) or parse_total_int(track_tag)

        disc_num = parse_first_int(disc_tag)
        disc_total = parse_total_int(disctotal_tag) or parse_total_int(disc_tag)

        fn_num, fn_title = filename_guess(src.stem)

        if track_num is None:
            track_num = fn_num

        if not title:
            title = fn_title

        if not title:
            title = clean_component(src.stem, 160, 200)

        artist_folder = clean_component(albumartist or artist or "Unknown Artist", 120, 150)
        if not artist_folder:
            artist_folder = "Unknown Artist"

        album_name = album or "Unknown Album"

        if args.year and year:
            album_folder = clean_component(f"{album_name} ({year})", 140, 180)
        else:
            album_folder = clean_component(album_name, 140, 180)

        if not album_folder:
            album_folder = "Unknown Album"

        album_key = (artist_folder.lower(), album_folder.lower())

        items.append(
            {
                "src": src,
                "ext": src.suffix,
                "artist_folder": artist_folder,
                "album_folder": album_folder,
                "album_key": album_key,
                "disc_num": disc_num,
                "disc_total": disc_total,
                "track_num": track_num,
                "track_total": track_total,
                "title": title,
            }
        )

    return items


def assign_dests(items):
    album_discs = {}

    for item in items:
        key = item["album_key"]
        d = album_discs.setdefault(key, {"nums": set(), "totals": set()})

        if item["disc_num"] is not None:
            d["nums"].add(item["disc_num"])

        if item["disc_total"] is not None:
            d["totals"].add(item["disc_total"])

    use_disc = set()

    for key, d in album_discs.items():
        nums = d["nums"]
        totals = d["totals"]

        if (
            any(t > 1 for t in totals if t is not None)
            or len(nums) > 1
            or any(n > 1 for n in nums if n is not None)
        ):
            use_disc.add(key)

    taken = set()

    for item in items:
        parts = [item["artist_folder"], item["album_folder"]]

        if item["album_key"] in use_disc and item["disc_num"] is not None:
            parts.append(f"Disc {item['disc_num']:02d}")

        fname = make_file_name(
            item["track_num"],
            item["track_total"],
            item["title"],
            item["src"].stem,
        )

        rel = Path(*parts) / (fname + item["ext"])
        rel = unique_path(rel, taken)
        taken.add(str(rel).casefold())

        item["dest_rel"] = rel


def process_one(item, args, output_root, moved_lrcs):
    src = item["src"]
    dest = output_root / item["dest_rel"]
    action = "copy" if args.copy else "move"
    msgs = []

    if dest.exists() and dest.is_dir():
        return [f"fail {dest}: destination is a directory"], 1

    # capture lrc paths before moving the audio
    lrcs = find_associated_lrcs(src)

    if dest.exists() and not args.force:
        msgs.append(f"skip {dest.relative_to(output_root)}")
        return msgs, 0

    if src.resolve() == dest.resolve():
        msgs.append(f"skip (same file) {src.name}")
        return msgs, 0

    if args.dry_run:
        msgs.append(f"would {action}: {src} -> {dest}")
        for lrc_src, lrc_type in lrcs:
            msgs.append(f"would {action} lrc: {lrc_src.name}")
        return msgs, 0

    dest.parent.mkdir(parents=True, exist_ok=True)

    try:
        if args.copy:
            shutil.copy2(src, dest)
        else:
            shutil.move(str(src), str(dest))
        msgs.append(f"{action} {dest.relative_to(output_root)}")
    except Exception as e:
        msgs.append(f"fail {src}: {e}")
        return msgs, 1

    for lrc_src, lrc_type in lrcs:
        if lrc_src in moved_lrcs:
            continue

        if lrc_type == "stem":
            lrc_dest = dest.parent / (dest.stem + ".lrc")
        else:
            lrc_dest = dest.parent / (dest.name + ".lrc")

        lrc_dest = unique_lrc_path(lrc_dest)

        try:
            if args.copy:
                shutil.copy2(lrc_src, lrc_dest)
            else:
                shutil.move(str(lrc_src), str(lrc_dest))
            moved_lrcs.add(lrc_src)
            msgs.append(f"lrc {lrc_dest.name}")
        except Exception as e:
            msgs.append(f"fail lrc {lrc_src}: {e}")

    return msgs, 0


def prune_empty_dirs(root):
    removed = 0
    dirs = sorted(
        (p for p in root.rglob("*") if p.is_dir()),
        key=lambda p: len(p.parts),
        reverse=True,
    )
    for d in dirs:
        try:
            os.rmdir(d)
            removed += 1
        except OSError:
            pass
    return removed


def main():
    ap = argparse.ArgumentParser(
        description="move audio files into a tag-sorted folder tree",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("input", type=Path, help="folder to scan for audio files")
    ap.add_argument("-o", "--output", type=Path, help="destination folder")
    ap.add_argument("--copy", action="store_true", help="copy instead of move")
    ap.add_argument("--force", action="store_true", help="overwrite existing destinations")
    ap.add_argument("--dry-run", action="store_true", help="preview without touching files")
    ap.add_argument("--year", action="store_true", help="include year in album folder")
    ap.add_argument("--prune", action="store_true", help="remove empty source dirs after moving")
    ap.add_argument("--ext", nargs="+", default=None, help="extensions to include (default: all known audio)")
    args = ap.parse_args()

    input_dir = args.input.expanduser().resolve()
    if not input_dir.is_dir():
        sys.exit(f"input is not a directory: {input_dir}")

    output_dir = (args.output or input_dir / "organized").expanduser().resolve()

    if output_dir.exists() and not output_dir.is_dir():
        sys.exit(f"output exists and is not a directory: {output_dir}")

    if output_dir == input_dir:
        sys.exit("output directory cannot be the same as input directory")

    if shutil.which("ffprobe") is None:
        sys.exit("ffprobe not found in path")

    if args.ext:
        exts = {e.lower().lstrip(".") for e in args.ext}
    else:
        exts = AUDIO_EXTS

    files = sorted(
        p
        for p in input_dir.rglob("*")
        if p.is_file()
        and p.suffix.lower().lstrip(".") in exts
        and not under(p, output_dir)
    )

    if not files:
        sys.exit(f"no audio files found in {input_dir}")

    print(f"reading tags for {len(files)} files...", file=sys.stderr)

    items = read_items(files, args)
    assign_dests(items)
    items.sort(key=lambda x: str(x["dest_rel"]).casefold())

    moved_lrcs = set()
    done = 0
    fails = 0

    for item in items:
        msgs, rc = process_one(item, args, output_dir, moved_lrcs)
        for m in msgs:
            print(m)
        done += 1
        fails += rc

    if args.prune and not args.copy and not args.dry_run:
        removed = prune_empty_dirs(input_dir)
        print(f"pruned {removed} empty directories")

    print(f"done: {done} files, {fails} failures")

    if fails:
        sys.exit(1)


if __name__ == "__main__":
    main()
