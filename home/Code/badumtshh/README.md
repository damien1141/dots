# badumtshh

A collection of Python tools for organizing an audiophile music library.

## Requirements

- Python 3.7+
- [ffmpeg](https://ffmpeg.org/) (for audio conversion, cover extraction, and re-encoding)
- [ffprobe](https://ffmpeg.org/ffprobe.html) (for reading audio metadata)

## Tools

### `organizer.py` — Sort audio files into a tag-based folder tree

Reads audio tags via `ffprobe` and moves (or copies) files into `Artist/Album/Track.ext` directory structures. Associated `.lrc` lyric files are moved/copied alongside their audio.

**Usage:**

```
python organizer.py <input> [options]
```

| Argument | Description |
|---|---|
| `input` | Folder to scan for audio files |
| `-o`, `--output` | Destination folder (default: `<input>/organized`) |
| `--copy` | Copy files instead of moving |
| `--force` | Overwrite existing destinations |
| `--dry-run` | Preview actions without touching files |
| `--year` | Include year in album folder name (e.g. `Album (2024)`) |
| `--prune` | Remove empty source directories after moving |
| `--ext` | Audio extensions to include (default: all known audio) |

**Output structure:**

```
<output>/
  Artist Name/
    Album Title/
      Disc 01/
        01 - Track Title.flac
      Disc 02/
        01 - Track Title.flac
```

Disc folders are automatically added when disc numbers are present in the tags.

---

### `flac2opus.py` — Convert audio to Opus, sorted by tags

Converts audio files (FLAC, MP3, etc.) to 385kbps VBR Opus, organized by artist/album/disc/track. Embeds cover art into the Opus file as `METADATA_BLOCK_PICTURE`. Optionally copies `.lrc` lyric files alongside the converted output. Its converted to 385kbps VBR to maintain absolute transparency especially in the low end.

**Usage:**

```
python flac2opus.py <input> [options]
```

| Argument | Description |
|---|---|
| `input` | Folder to scan for audio files |
| `-o`, `--output` | Output folder (default: `<input>/processed OPUS`) |
| `--force` | Overwrite existing output |
| `--dry-run` | Print actions without converting |
| `--jobs` | Parallel conversions (default: 1) |
| `--year` | Include year in album folder |
| `--lrc` | Where to write lyric files: `stem`, `opus`, `both`, or `none` (default: `both`) |

**Output structure:**

```
<output>/
  Artist Name/
    Album Title (Year)/
      Disc 01/
        01 - Track Title.opus
        01 - Track Title.opus.lrc
```

Cover art is extracted from attached pictures in the source and embedded into the Opus file. LRC files are co-located with the output Opus files.

---

### `art.py` — Extract cover art from audio files

Extracts embedded album art from each folder's first audio file and saves it as `cover.jpg` (or the matching codec format) in that folder. Folders matching `Unknown Artist/Unknown Album` can receive a custom placeholder cover image.

**Usage:**

```
python art.py <directory> [options]
```

| Argument | Description |
|---|---|
| `directory` | Folder to scan recursively |
| `--name` | Output filename stem (default: `cover`) |
| `--force` | Overwrite existing cover files |
| `--dry-run` | Preview without writing |
| `--jpg` | Always output `.jpg` (converts if needed) |
| `--unknown-cover` | Custom image for Unknown Artist/Unknown Album folders |
| `--ext` | Audio extensions to consider |

**Auto-detection:** If an `unknown-cover.*` image exists next to `art.py`, it will be automatically used for `Unknown Artist/Unknown Album` directories.

---

### `LYRICSSSSS.py` — Fetch synced lyrics from lrclib.net

Scans audio files and downloads synced `.lrc` lyrics from [lrclib.net](https://lrclib.net) for any files missing them. Falls back to plain (unsynced) lyrics if enabled. Uses multiple search strategies with duration-based matching.

**Usage:**

```
python LYRICSSSSS.py <directory> [options]
```

| Argument | Description |
|---|---|
| `directory` | Folder to scan (recursive) |
| `--ext` | Audio extensions to scan (default: wide range including opus, flac, mp3, etc.) |
| `--force` | Refetch even if `.lrc` already exists |
| `--dry-run` | Show what would be fetched |
| `--tolerance` | Max duration diff in seconds for search fallback (default: 2.0) |
| `--allow-plain` | Fall back to unsynced lyrics if no synced version exists |
| `--delay` | Seconds between API requests (default: 0.3) |
| `--lrc` | Where to write: `stem`, `opus`, or `both` (default: `both`) |

**Search strategy:** Tries exact match (with duration), exact match (without duration), structured search (duration-filtered), then free-text search — always preferring synced lyrics over plain.

---

## Typical Workflow

1. **`organizer.py`** — Sort your raw music collection into `Artist/Album/Track` folders
2. **`art.py`** — Extract cover art into each album folder
3. **`flac2opus.py`** — Convert to Opus with embedded covers and lyrics
4. **`LYRICSSSSS.py`** — Fetch lyrics for any tracks that didn't get them

---

## File Layout

```
badumtshh/
  organizer.py      — Tag-based file sorting (move/copy)
  flac2opus.py      — Audio conversion to Opus with cover embedding
  art.py            — Cover art extraction
  LYRICSSSSS.py     — Lyrics fetching from lrclib.net
  unknown-cover.png — Default placeholder for unknown albums
```
