#!/usr/bin/env python3
import argparse
import base64
import json
import os
import re
import shlex
import shutil
import struct
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


import zlib

def build_picture_block(img_data: bytes, mime_type: str = "image/jpeg",
                        picture_type: int = 3, description: str = "Cover (front)",
                        width: int = 0, height: int = 0, color_depth: int = 24) -> bytes:
    """Build a FLAC PICTURE metadata block (used as METADATA_BLOCK_PICTURE in Opus)."""
    desc_bytes = description.encode("utf-8")
    mime_bytes = mime_type.encode("ascii")
    header = struct.pack(">I", picture_type)
    header += struct.pack(">I", len(mime_bytes))
    header += mime_bytes
    header += struct.pack(">I", len(desc_bytes))
    header += desc_bytes
    header += struct.pack(">I", width)
    header += struct.pack(">I", height)
    header += struct.pack(">I", color_depth)
    header += struct.pack(">I", 0)  # num_colors (0 for non-indexed)
    header += struct.pack(">I", len(img_data))
    return header + img_data


# Ogg CRC32 table (polynomial 0x04C11DB7, no reflection)
_OGG_CRC32_TABLE = None

def _init_ogg_crc32_table():
    global _OGG_CRC32_TABLE
    if _OGG_CRC32_TABLE is not None:
        return
    _OGG_CRC32_TABLE = [0] * 256
    poly = 0x04C11DB7
    for i in range(256):
        crc = i << 24
        for _ in range(8):
            if crc & 0x80000000:
                crc = (crc << 1) ^ poly
            else:
                crc = crc << 1
        _OGG_CRC32_TABLE[i] = crc & 0xFFFFFFFF

def _ogg_crc32(data: bytes) -> int:
    """Calculate Ogg CRC32 (polynomial 0x04C11DB7, init 0, no reflection)."""
    _init_ogg_crc32_table()
    crc = 0
    for byte in data:
        crc = ((crc << 8) ^ _OGG_CRC32_TABLE[(crc >> 24) ^ byte]) & 0xFFFFFFFF
    return crc


def _parse_ogg_pages(data: bytes):
    """Parse Ogg pages from data. Returns list of (page_start, page_end, header, segments, packet_data)."""
    pages = []
    pos = 0
    while pos < len(data):
        if pos + 27 > len(data):
            break
        if data[pos:pos+4] != b"OggS":
            break
        header = data[pos:pos+27]
        version = header[4]
        header_type = header[5]
        granule_pos = struct.unpack("<Q", header[6:14])[0]
        serial_no = struct.unpack("<I", header[14:18])[0]
        page_seq = struct.unpack("<I", header[18:22])[0]
        checksum = struct.unpack("<I", header[22:26])[0]
        n_segments = header[26]
        if pos + 27 + n_segments > len(data):
            break
        segment_table = data[pos+27:pos+27+n_segments]
        segment_lengths = list(segment_table)
        packet_data_len = sum(segment_lengths)
        packet_data_start = pos + 27 + n_segments
        packet_data_end = packet_data_start + packet_data_len
        if packet_data_end > len(data):
            break
        packet_data = data[packet_data_start:packet_data_end]
        pages.append({
            "start": pos,
            "end": packet_data_end,
            "header": header,
            "version": version,
            "header_type": header_type,
            "granule_pos": granule_pos,
            "serial_no": serial_no,
            "page_seq": page_seq,
            "checksum": checksum,
            "n_segments": n_segments,
            "segment_table": segment_table,
            "segment_lengths": segment_lengths,
            "packet_data": packet_data,
        })
        pos = packet_data_end
    return pages


def _build_ogg_pages_for_packet(version, header_type, granule_pos, serial_no, page_seq, packet_data, is_bos=False, is_eos=False):
    """Split a large packet across multiple Ogg pages. Returns list of page bytes."""
    pages = []
    MAX_SEGMENTS_PER_PAGE = 255
    MAX_SEGMENT_SIZE = 255

    # Split packet_data into chunks of MAX_SEGMENT_SIZE
    segments = []
    for i in range(0, len(packet_data), MAX_SEGMENT_SIZE):
        chunk = packet_data[i:i+MAX_SEGMENT_SIZE]
        segments.append(chunk)

    # Group segments into pages (max MAX_SEGMENTS_PER_PAGE per page)
    for page_idx in range(0, len(segments), MAX_SEGMENTS_PER_PAGE):
        page_segments = segments[page_idx:page_idx + MAX_SEGMENTS_PER_PAGE]
        segment_lengths = [len(s) for s in page_segments]
        page_packet_data = b"".join(page_segments)

        # Determine header_type for this page
        if page_idx == 0:
            # First page of packet
            ht = header_type
            if is_bos:
                ht |= 0x02
        else:
            # Continuation page
            ht = 0x01

        # Check if this is the last page of the packet
        is_last_page = (page_idx + len(page_segments)) >= len(segments)
        if is_last_page and is_eos:
            ht |= 0x04

        # Build page
        n_segments = len(segment_lengths)
        header = bytearray(27 + n_segments + len(page_packet_data))
        header[0:4] = b"OggS"
        header[4] = version
        header[5] = ht
        header[6:14] = struct.pack("<Q", granule_pos)
        header[14:18] = struct.pack("<I", serial_no)
        header[18:22] = struct.pack("<I", page_seq + page_idx // MAX_SEGMENTS_PER_PAGE)
        header[22:26] = b"\x00\x00\x00\x00"
        header[26] = n_segments
        header[27:27+n_segments] = bytes(segment_lengths)
        header[27+n_segments:] = page_packet_data

        crc = _ogg_crc32(header)
        header[22:26] = struct.pack("<I", crc)
        pages.append(bytes(header))

    return pages


def _rebuild_vorbis_comments(packet_data: bytes, new_comment: bytes) -> bytes:
    """Insert a new Vorbis comment into an OpusTags packet."""
    if not packet_data.startswith(b"OpusTags"):
        return packet_data
    pos = 8  # skip "OpusTags"
    if pos + 4 > len(packet_data):
        return packet_data
    vendor_len = struct.unpack("<I", packet_data[pos:pos+4])[0]
    pos += 4 + vendor_len
    if pos + 4 > len(packet_data):
        return packet_data
    comment_count = struct.unpack("<I", packet_data[pos:pos+4])[0]
    pos += 4
    # Skip existing comments
    for _ in range(comment_count):
        if pos + 4 > len(packet_data):
            return packet_data
        comment_len = struct.unpack("<I", packet_data[pos:pos+4])[0]
        pos += 4 + comment_len
    # Insert new comment at pos
    new_comment_len = struct.pack("<I", len(new_comment))
    new_packet = packet_data[:pos] + new_comment_len + new_comment + packet_data[pos:]
    # Update comment count
    count_pos = 8 + 4 + vendor_len
    new_packet = new_packet[:count_pos] + struct.pack("<I", comment_count + 1) + new_packet[count_pos+4:]
    return new_packet


def _parse_ogg_pages_raw(data: bytes):
    """Parse Ogg pages, returning raw page bytes and parsed info."""
    pages = []
    pos = 0
    while pos < len(data):
        if pos + 27 > len(data):
            break
        if data[pos:pos+4] != b"OggS":
            break
        header = data[pos:pos+27]
        version = header[4]
        header_type = header[5]
        granule_pos = struct.unpack("<Q", header[6:14])[0]
        serial_no = struct.unpack("<I", header[14:18])[0]
        page_seq = struct.unpack("<I", header[18:22])[0]
        checksum = struct.unpack("<I", header[22:26])[0]
        n_segments = header[26]
        if pos + 27 + n_segments > len(data):
            break
        segment_table = data[pos+27:pos+27+n_segments]
        segment_lengths = list(segment_table)
        packet_data_len = sum(segment_lengths)
        packet_data_start = pos + 27 + n_segments
        packet_data_end = packet_data_start + packet_data_len
        if packet_data_end > len(data):
            break
        pages.append({
            "start": pos,
            "end": packet_data_end,
            "raw": data[pos:packet_data_end],
            "version": version,
            "header_type": header_type,
            "granule_pos": granule_pos,
            "serial_no": serial_no,
            "page_seq": page_seq,
            "checksum": checksum,
            "n_segments": n_segments,
            "segment_table": segment_table,
            "segment_lengths": segment_lengths,
            "packet_data_len": packet_data_len,
            "is_continuation": bool(header_type & 0x01),
            "is_bos": bool(header_type & 0x02),
            "is_eos": bool(header_type & 0x04),
        })
        pos = packet_data_end
    return pages


def _patch_page_seq_and_crc(page_raw: bytes, new_page_seq: int) -> bytes:
    """Patch page_seq in raw page bytes and recalculate CRC32."""
    page = bytearray(page_raw)
    # Update page_seq at offset 18
    page[18:22] = struct.pack("<I", new_page_seq)
    # Zero out checksum at offset 22
    page[22:26] = b"\x00\x00\x00\x00"
    # Recalculate CRC32
    crc = _ogg_crc32(page)
    page[22:26] = struct.pack("<I", crc)
    return bytes(page)


def embed_cover_in_opus(opus_path: Path, cover_path: Path) -> bool:
    """Embed cover art as METADATA_BLOCK_PICTURE Vorbis comment in Opus file."""
    try:
        with open(cover_path, "rb") as f:
            img_data = f.read()

        suffix = cover_path.suffix.lower()
        mime_map = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}
        mime_type = mime_map.get(suffix, "image/jpeg")

        picture_block = build_picture_block(img_data, mime_type=mime_type)
        picture_b64 = base64.b64encode(picture_block).decode("ascii")
        new_comment = f"METADATA_BLOCK_PICTURE={picture_b64}".encode("utf-8")

        with open(opus_path, "rb") as f:
            data = f.read()

        pages = _parse_ogg_pages_raw(data)
        if len(pages) < 2:
            return False

        # Find page containing OpusTags (usually page 1)
        opus_tags_page_idx = None
        for i, page in enumerate(pages):
            pkt_start = page["start"] + 27 + page["n_segments"]
            pkt_end = pkt_start + page["packet_data_len"]
            if data[pkt_start:pkt_start+8] == b"OpusTags":
                opus_tags_page_idx = i
                break

        if opus_tags_page_idx is None:
            return False

        page = pages[opus_tags_page_idx]
        pkt_start = page["start"] + 27 + page["n_segments"]
        pkt_end = pkt_start + page["packet_data_len"]
        old_packet = data[pkt_start:pkt_end]

        new_packet = _rebuild_vorbis_comments(old_packet, new_comment)

        new_opus_tags_pages = _build_ogg_pages_for_packet(
            page["version"],
            page["header_type"],
            page["granule_pos"],
            page["serial_no"],
            page["page_seq"],
            new_packet,
            is_bos=(opus_tags_page_idx == 0),
            is_eos=False
        )

        extra_pages = len(new_opus_tags_pages) - 1

        new_data = bytearray()

        for i in range(opus_tags_page_idx):
            new_data.extend(pages[i]["raw"])

        new_data.extend(b"".join(new_opus_tags_pages))

        for i in range(opus_tags_page_idx + 1, len(pages)):
            patched = _patch_page_seq_and_crc(pages[i]["raw"], pages[i]["page_seq"] + extra_pages)
            new_data.extend(patched)

        with open(opus_path, "wb") as f:
            f.write(new_data)

        return True
    except Exception as e:
        # Log the error for debugging
        import traceback
        traceback.print_exc()
        return False

AUDIO_EXTS = {".flac", ".mp3", ".ogg", ".oga", ".opus", ".m4a", ".aac", ".wav", ".wv", ".ape", ".wma", ".aiff", ".aif"}

BAD_CHARS = re.compile(r'[\x00-\x1f\x7f<>:"/\\|?*]+')


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
    s = BAD_CHARS.sub(" ", s)
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
        "ffprobe",
        "-v", "error",
        "-print_format", "json",
        "-show_format",
        str(path),
    ]

    try:
        r = subprocess.run(cmd, check=True, text=True, capture_output=True)
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

    # handles weird "1-05" style disc-track numbers
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


def under(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def find_lrc(src: Path):
    exact = src.with_suffix(".lrc")
    if exact.is_file():
        return exact

    # case-insensitive fallback
    try:
        for p in src.parent.iterdir():
            if (
                p.is_file()
                and p.suffix.lower() == ".lrc"
                and p.stem.lower() == src.stem.lower()
            ):
                return p
    except OSError:
        pass

    return None


def lrc_targets(dest: Path, mode: str):
    if mode == "none":
        return []

    out = []

    # track.opus -> track.lrc
    if mode in ("stem", "both"):
        out.append(dest.with_suffix(".lrc"))

    # track.opus -> track.opus.lrc
    if mode in ("opus", "both"):
        out.append(dest.parent / (dest.name + ".lrc"))

    return out


def _read_one(src: Path, args) -> dict:
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

    return {
        "src": src,
        "artist_folder": artist_folder,
        "album_folder": album_folder,
        "album_key": album_key,
        "disc_num": disc_num,
        "disc_total": disc_total,
        "track_num": track_num,
        "track_total": track_total,
        "title": title,
    }


def read_items(audios, args):
    # Tag probing is a per-file ffprobe subprocess; parallelize it.
    # subprocess.run releases the GIL while the child runs, so threads scale.
    if len(audios) < 2 or args.jobs <= 1:
        return [_read_one(src, args) for src in audios]

    print(f"probing tags for {len(audios)} files...", file=sys.stderr)

    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        return list(ex.map(_read_one, audios, [args] * len(audios)))


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

        rel = Path(*parts) / (fname + ".opus")
        rel = unique_path(rel, taken)
        taken.add(str(rel).casefold())

        item["dest_rel"] = rel


def process_one(item, args, output_root):
    src = item["src"]
    dest = output_root / item["dest_rel"]
    msgs = []

    if dest.exists() and dest.is_dir():
        return [f"fail {dest}: destination is a directory"], 1

    tmp = dest.parent / (dest.name + ".part")

    if dest.exists() and not args.force:
        msgs.append(f"skip audio {dest.relative_to(output_root)}")
    else:
        dest.parent.mkdir(parents=True, exist_ok=True)

        if tmp.exists():
            tmp.unlink()

        # Check for attached picture (video stream with disposition:attached_pic)
        probe_cmd = [
            "ffprobe", "-v", "error", "-select_streams", "v",
            "-show_entries", "stream",
            "-of", "json", str(src)
        ]
        has_cover = False
        cover_stream = None
        try:
            r = subprocess.run(probe_cmd, check=True, text=True, capture_output=True)
            probe_data = json.loads(r.stdout)
            for stream in probe_data.get("streams", []):
                disp = stream.get("disposition", {})
                if disp.get("attached_pic") == 1:
                    cover_stream = str(stream.get("index"))
                    has_cover = True
                    break
        except Exception:
            pass

        if args.dry_run:
            if has_cover:
                msgs.append(f"would extract cover from stream {cover_stream} and embed in opus")
            msgs.append("would run: ffmpeg -i <src> -map 0:a:0 -map_metadata 0 -c:a libopus -b:a 425k -vbr on -compression_level 6 -frame_duration 60 -application audio -bandwidth fullband -ar 48000 -f ogg <dest>")
        else:
            try:
                # Convert audio to Opus
                cmd = [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel", "error",
                    "-nostdin",
                    "-y",
                    "-i", str(src),
                    "-map", "0:a:0",
                    "-map_metadata", "0",
                    "-c:a", "libopus",
                    "-b:a", "385k",
                    "-vbr", "on",
                    "-compression_level", "6",
                    "-frame_duration", "60",
                    "-application", "audio",
                    "-bandwidth", "fullband",
                    "-ar", "48000",
                    "-f", "ogg",
                    str(tmp),
                ]
                subprocess.run(cmd, check=True, text=True, capture_output=True)

                # If source has cover, extract and embed it
                if has_cover:
                    cover_tmp = dest.parent / (dest.stem + ".cover.jpg")
                    extract_cmd = [
                        "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                        "-i", str(src),
                        "-map", f"0:{cover_stream}",
                        "-c:v", "copy",
                        str(cover_tmp),
                    ]
                    subprocess.run(extract_cmd, check=True, text=True, capture_output=True)

                    # Embed cover in Opus file
                    if not embed_cover_in_opus(tmp, cover_tmp):
                        msgs.append(f"warning: failed to embed cover for {dest.relative_to(output_root)}")

                    if cover_tmp.exists():
                        cover_tmp.unlink()

                tmp.replace(dest)
                msgs.append(f"opus {dest.relative_to(output_root)}")
            except subprocess.CalledProcessError as e:
                for f in (tmp, dest.parent / (dest.stem + ".cover.jpg")):
                    if f.exists():
                        f.unlink()
                err = (e.stderr or "").strip() or str(e)
                msgs.append(f"fail audio {src}: {err}")
                return msgs, 1

    if args.lrc != "none":
        lsrc = find_lrc(src)
        if lsrc:
            for t in lrc_targets(dest, args.lrc):
                if t.exists() and not args.force:
                    label = "would skip lrc" if args.dry_run else "skip lrc"
                    msgs.append(f"{label} {t.relative_to(output_root)}")
                    continue

                if args.dry_run:
                    msgs.append(f"would lrc {lsrc} -> {t}")
                else:
                    t.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(lsrc, t)
                    msgs.append(f"lrc {t.relative_to(output_root)}")

    return msgs, 0


def safe_process(item, args, output_root):
    try:
        return process_one(item, args, output_root)
    except Exception as e:
        return [f"fail {item['src']}: {e}"], 1


def main():
    ap = argparse.ArgumentParser(
        description="recursive audio -> opus with ffmpeg, sorted by tags",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("input", type=Path, help="folder to scan for audio files")
    ap.add_argument("-o", "--output", type=Path, help="output folder")
    ap.add_argument("--force", action="store_true", help="overwrite existing output")
    ap.add_argument("--dry-run", action="store_true", help="print actions without converting")
    ap.add_argument("--jobs", type=int, default=1, help="parallel conversions; <=1 is 1")
    ap.add_argument("--year", action="store_true", help="include year in album folder")
    ap.add_argument(
        "--lrc",
        choices=["stem", "opus", "both", "none"],
        default="both",
        help="stem=track.lrc, opus=track.opus.lrc",
    )
    args = ap.parse_args()

    input_dir = args.input.expanduser().resolve()
    if not input_dir.is_dir():
        sys.exit(f"input is not a directory: {input_dir}")

    output_dir = (args.output or input_dir / "processed OPUS").expanduser().resolve()

    if output_dir.exists() and not output_dir.is_dir():
        sys.exit(f"output exists and is not a directory: {output_dir}")

    if output_dir == input_dir:
        sys.exit("output directory cannot be the same as input directory")

    if shutil.which("ffprobe") is None:
        sys.exit("ffprobe not found in path")

    if not args.dry_run and shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found in path")

    if args.jobs <= 0:
        args.jobs = os.cpu_count() or 1

    audios = sorted(
        p
        for p in input_dir.rglob("*")
        if p.is_file() and p.suffix.lower() in AUDIO_EXTS and not under(p, output_dir)
    )

    if not audios:
        sys.exit(f"no audio files found in {input_dir}")

    print(f"reading tags for {len(audios)} files...", file=sys.stderr)

    items = read_items(audios, args)
    assign_dests(items)

    items.sort(key=lambda x: str(x["dest_rel"]).casefold())

    total = len(items)
    done = 0
    fails = 0

    if args.jobs == 1:
        for item in items:
            msgs, rc = safe_process(item, args, output_dir)
            for m in msgs:
                print(m)
            done += 1
            fails += rc
    else:
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            futures = {
                ex.submit(safe_process, item, args, output_dir): item
                for item in items
            }

            for fut in as_completed(futures):
                msgs, rc = fut.result()
                for m in msgs:
                    print(m)
                done += 1
                fails += rc

    print(f"done: {done}/{total}, fails: {fails}")

    if fails:
        sys.exit(1)


if __name__ == "__main__":
    main()
