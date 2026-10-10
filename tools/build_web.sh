#!/usr/bin/env bash
# tools/build_web.sh — headless Web export + artifact size ledger.
#
# Usage:   tools/build_web.sh
# Output:  build/web/ (index.html + wasm/js/pck), size ledger on stdout
#          and in build/size-ledger.txt, export log in build/export.log.
# Exit:    0 PASS, 1 FAIL (with reason).
#
# The ledger (raw / gzip / brotli bytes per artifact) is what Phase 15
# (Vercel) reads to plan transfer sizes and cache/compression headers.
# Preset lives in export_presets.cfg (committed — D5). Build output is
# gitignored (build/).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/web"
PRESET_NAME="Web"
LOG_DIR="$PROJECT_DIR/build"

say()  { printf '%s\n' "$*"; }
fail() { say "FAIL: $*"; exit 1; }

command -v godot >/dev/null 2>&1 || fail "godot not on PATH (brew install godot)"

cd "$PROJECT_DIR"

say "== godot =="
godot --version

say "== export (preset: $PRESET_NAME) =="
mkdir -p "$BUILD_DIR"
rm -f "$BUILD_DIR"/*
if ! godot --headless --export-release "$PRESET_NAME" 2>&1 | tee "$LOG_DIR/export.log"; then
  fail "export command failed — see build/export.log (missing templates? see export_templates/4.7.2.stable.official.ed1daf0bf)"
fi

say "== artifacts =="
[ -f "$BUILD_DIR/index.html" ] || fail "index.html missing from $BUILD_DIR"
ls "$BUILD_DIR"/*.wasm >/dev/null 2>&1 || fail "no .wasm artifact in $BUILD_DIR"
ls "$BUILD_DIR"/*.pck >/dev/null 2>&1 || fail "no .pck artifact in $BUILD_DIR"

size_of() { wc -c < "$1" | tr -d ' '; }

say "== size ledger =="
{
  printf '%-28s %12s %12s %12s\n' "file" "raw-B" "gzip-B" "brotli-B"
  total_raw=0; total_gz=0; total_br=0; br_known=1
  for f in "$BUILD_DIR"/*; do
    [ -f "$f" ] || continue
    raw=$(size_of "$f")
    gz=$(gzip -c "$f" | wc -c | tr -d ' ')
    if command -v brotli >/dev/null 2>&1; then
      br=$(brotli -q 11 -c "$f" | wc -c | tr -d ' ')
      total_br=$((total_br + br))
    else
      br="-"; br_known=0
    fi
    printf '%-28s %12s %12s %12s\n' "$(basename "$f")" "$raw" "$gz" "$br"
    total_raw=$((total_raw + raw))
    total_gz=$((total_gz + gz))
  done
  if [ "$br_known" -eq 1 ]; then
    printf '%-28s %12s %12s %12s\n' "TOTAL" "$total_raw" "$total_gz" "$total_br"
  else
    printf '%-28s %12s %12s %12s\n' "TOTAL" "$total_raw" "$total_gz" "(brotli not installed)"
  fi
} | tee "$LOG_DIR/size-ledger.txt"

if command -v brotli >/dev/null 2>&1; then
  say "PASS — export complete, ledger above (brotli q11 estimates)"
else
  say "PASS — export complete, ledger above (install brotli for brotli estimates: brew install brotli)"
fi
