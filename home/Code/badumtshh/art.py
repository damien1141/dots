#!/usr/bin/env python3
import argparse
import json
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

IMAGE_EXTS = {"png", "jpg", "jpeg", "webp", "gif", "bmp"}

# codec name -> output extension
CODEC_EXT = {
    "mjpeg": ".jpg",
    "jpeg": ".jpg",
    "jpg": ".jpg",
    "png": ".png",
    "gif": ".gif",
    "bmp": ".bmp",
    "webp": ".webp",
}

# the folder organizer.py v1 dumps untagged files into
UNKNOWN_PARTS = ("unknown artist", "unknown album")

# directory this script lives in - where unknown-cover.* is auto-detected
SCRIPT_DIR = Path(__file__).resolve().parent


def run(cmd):
    return subprocess.run(cmd, text=True, capture_output=True)


def is_unknown_dir(d, root):
    try:
        rel = d.relative_to(root)
    except ValueError:
        return False
    return tuple(p.lower() for p in rel.parts) == UNKNOWN_PARTS


def find_default_unknown_cover(script_dir):
    """Auto-detect an unknown-cover.* image sitting next to this script."""
    for p in sorted(script_dir.glob("unknown-cover.*")):
        if p.is_file() and p.suffix.lower().lstrip(".") in IMAGE_EXTS:
            return p
    return None


def find_art_stream(path):
    """Return (stream_index, codec_name) for the first embedded image, or None."""
    cmd = [
        "ffprobe", "-v", "error",
        "-print_format", "json",
        "-show_streams",
        str(path),
    ]
    r = run(cmd)
    if r.returncode != 0:
        return None

    try:
        streams = json.loads(r.stdout).get("streams", [])
    except Exception:
        return None

    for s in streams:
        if s.get("codec_type") == "video":
            return (s.get("index"), (s.get("codec_name") or "").lower())

    return None


def extract_art(src, dest_stem, force, dry_run):
    """Extract embedded art from src to dest_stem.<ext>. Returns (path, status)."""
    info = find_art_stream(src)
    if info is None:
        return None, "noart"

    _idx, codec = info
    ext = CODEC_EXT.get(codec, ".jpg")
    dest = dest_stem.with_suffix(ext)

    if dest.exists() and not force:
        return dest, "exists"

    if dry_run:
        return dest, "would"

    # copy the video stream verbatim, no re-encode
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-i", str(src),
        "-map", "0:v:0",
        "-c:v", "copy",
        "-frames:v", "1",
        "-f", "image2",
        str(dest),
    ]
    r = run(cmd)

    if r.returncode != 0:
        if dest.exists():
            dest.unlink()
        return None, "fail"

    if not dest.exists():
        return None, "fail"

    return dest, "written"


def apply_custom_cover(custom_src, dest_stem, force, dry_run, to_jpg):
    """Place a user-provided image as the cover. Returns (path, status)."""
    if to_jpg:
        dest = dest_stem.with_suffix(".jpg")

        if dest.exists() and not force:
            return dest, "exists"
        if dry_run:
            return dest, "would"

        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-i", str(custom_src),
            "-frames:v", "1",
            "-q:v", "2",
            "-f", "image2",
            str(dest),
        ]
        r = run(cmd)
        if r.returncode != 0:
            if dest.exists():
                dest.unlink()
            return None, "fail"
        if not dest.exists():
            return None, "fail"
        return dest, "written"

    # keep the source format, just copy it in
    ext = custom_src.suffix.lower() or ".jpg"
    dest = dest_stem.with_suffix(ext)

    if dest.exists() and not force:
        return dest, "exists"
    if dry_run:
        return dest, "would"

    try:
        shutil.copy2(custom_src, dest)
    except Exception:
        return None, "fail"

    return dest, "written"


def main():
    ap = argparse.ArgumentParser(
        description="write cover art from each folder's first track's embedded image",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("directory", type=Path, help="folder to scan recursively")
    ap.add_argument("--name", default="cover", help="output filename stem")
    ap.add_argument("--force", action="store_true", help="overwrite existing cover files")
    ap.add_argument("--dry-run", action="store_true", help="preview without writing")
    ap.add_argument("--jpg", action="store_true", help="always output .jpg (converts source if needed)")
    ap.add_argument(
        "--unknown-cover", type=Path, default=None,
        help="override the auto-detected unknown-cover.* image for the Unknown folder",
    )
    ap.add_argument("--ext", nargs="+", default=None, help="audio extensions to consider")
    args = ap.parse_args()

    root = args.directory.expanduser().resolve()
    if not root.is_dir():
        sys.exit(f"not a directory: {root}")

    if not args.dry_run and shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found in path")
    if shutil.which("ffprobe") is None:
        sys.exit("ffprobe not found in path")

    # explicit flag wins, otherwise auto-detect unknown-cover.* next to this script
    unknown_cover = None
    if args.unknown_cover:
        unknown_cover = args.unknown_cover.expanduser().resolve()
        if not unknown_cover.is_file():
            sys.exit(f"unknown cover not found: {unknown_cover}")
    else:
        unknown_cover = find_default_unknown_cover(SCRIPT_DIR)
        if unknown_cover:
            print(f"using unknown cover: {unknown_cover}", file=sys.stderr)

    exts = (
        {e.lower().lstrip(".") for e in args.ext}
        if args.ext
        else AUDIO_EXTS
    )

    # group audio files by their containing directory
    by_dir = {}
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if p.suffix.lower().lstrip(".") not in exts:
            continue
        by_dir.setdefault(p.parent, []).append(p)

    if not by_dir:
        sys.exit(f"no audio files found in {root}")

    counts = {"written": 0, "would": 0, "exists": 0, "noart": 0, "fail": 0}

    for d in sorted(by_dir.keys()):
        tracks = sorted(by_dir[d])
        first = tracks[0]
        dest_stem = d / args.name
        rel = d.relative_to(root)

        # special case: Unknown Artist/Unknown Album gets the custom cover
        if unknown_cover and is_unknown_dir(d, root):
            path, status = apply_custom_cover(
                unknown_cover, dest_stem, args.force, args.dry_run, args.jpg
            )

            if status == "written":
                print(f"custom {rel} -> {path.name}")
                counts["written"] += 1
            elif status == "would":
                print(f"would custom {rel} -> {path.name}")
                counts["would"] += 1
            elif status == "exists":
                print(f"exists {rel}")
                counts["exists"] += 1
            elif status == "fail":
                print(f"fail {rel}: custom cover")
                counts["fail"] += 1
            continue

        if args.jpg:
            info = find_art_stream(first)
            if info is None:
                print(f"noart {rel}: {first.name}")
                counts["noart"] += 1
                continue

            path, status = extract_art(first, dest_stem, args.force, args.dry_run)

            if status == "written" and path and path.suffix != ".jpg":
                final = dest_stem.with_suffix(".jpg")
                if final.exists() and not args.force:
                    counts["exists"] += 1
                    path.unlink()
                    print(f"exists {rel}")
                    continue
                if not args.dry_run:
                    path.rename(final)
                path = final

            if status == "written":
                print(f"jpg {rel} -> {path.name}")
                counts["written"] += 1
            elif status == "would":
                print(f"would jpg {rel} -> {path.name}")
                counts["would"] += 1
            elif status == "exists":
                print(f"exists {rel}")
                counts["exists"] += 1
            elif status == "fail":
                print(f"fail {rel}: {first.name}")
                counts["fail"] += 1
            continue

        path, status = extract_art(first, dest_stem, args.force, args.dry_run)

        if status == "written":
            print(f"art {rel} -> {path.name}")
            counts["written"] += 1
        elif status == "would":
            print(f"would {rel} -> {path.name}")
            counts["would"] += 1
        elif status == "exists":
            print(f"exists {rel}")
            counts["exists"] += 1
        elif status == "noart":
            print(f"noart {rel}: {first.name}")
            counts["noart"] += 1
        elif status == "fail":
            print(f"fail {rel}: {first.name}")
            counts["fail"] += 1

    print(
        f"done: written={counts['written']} would={counts['would']} "
        f"exists={counts['exists']} noart={counts['noart']} fail={counts['fail']}"
    )

    if counts["fail"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
