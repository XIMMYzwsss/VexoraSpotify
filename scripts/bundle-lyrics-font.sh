#!/usr/bin/env bash
# Copies Mojangles.otf into the built IPA for Vexora lyrics (registered at runtime).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$1"
FONT="$ROOT/tweak/resources/Mojangles.otf"
[ -f "$OUT" ] || { echo "bundle-lyrics-font: no IPA: $OUT" >&2; exit 1; }
[ -f "$FONT" ] || { echo "    no Mojangles.otf in tweak/resources"; exit 0; }
APP_DIR="$(unzip -Z1 "$OUT" | grep -oE '^Payload/[^/]+\.app/' | sort -u | head -1)"
[ -n "$APP_DIR" ] || exit 0
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/$APP_DIR"
cp "$FONT" "$WORK/$APP_DIR/Mojangles.otf"
( cd "$WORK" && zip -q -u "$OUT_ABS" "${APP_DIR}Mojangles.otf" )
echo "    bundled Mojangles.otf"
