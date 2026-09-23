#!/usr/bin/env bash
# parse-templates.sh — split a markdown skill file into per-template .md files.
#
# Each H3 (### ) section that contains a fenced code block (``` ) becomes one
# file under <out>/, named by slugifying the heading text.
#
# Usage:
#   ./parse-templates.sh <input.md> [more.md ...] [--out <dir>]
#
# Examples:
#   ./parse-templates.sh high-end-visual-design.md --out high-end-visual-design/templates
#   ./parse-templates.sh old-skill.md buttons.md --out high-end-visual-design/templates
#
# Idempotent: re-running overwrites existing template files with the same slug.
# Sections without a fenced code block are skipped.

set -euo pipefail

OUT=""
INPUTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) INPUTS+=("$1"); shift ;;
  esac
done

[[ -n "$OUT" ]] || OUT="high-end-visual-design/templates"
[[ ${#INPUTS[@]} -gt 0 ]] || { echo "No input files. See --help." >&2; exit 1; }

mkdir -p "$OUT"

for f in "${INPUTS[@]}"; do
  [[ -f "$f" ]] || { echo "skip (missing): $f" >&2; continue; }
  echo "→ parsing $f"
  awk -v outdir="$OUT" '
    BEGIN { in_sec=0; in_fence=0; head=""; body=""; has_code=0 }

    # H3 heading — only when NOT inside a code fence
    /^### / && !in_fence {
      if (in_sec && has_code) write_file(head, body)
      in_sec=1; head=$0; body=""; has_code=0; next
    }

    # Every other line
    {
      if ($0 ~ /^```/) {
        in_fence = !in_fence
        if (in_sec) has_code=1
      }
      if (in_sec) body = body $0 "\n"
    }

    END { if (in_sec && has_code) write_file(head, body) }

    function write_file(h, b,   slug, path) {
      slug = tolower(h)
      sub(/^### +/, "", slug)
      gsub(/[^a-z0-9]+/, "-", slug)
      sub(/^-+/, "", slug)
      sub(/-+$/, "", slug)
      if (slug == "") return
      path = outdir "/" slug ".md"
      printf "%s\n\n%s", h, b > path
      close(path)
      print "  wrote " path
    }
  ' "$f"
done

count=$(find "$OUT" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
echo "✓ $count template files in $OUT"