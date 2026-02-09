#!/usr/bin/env bash
set -euo pipefail

MONITORS_XML="${MONITORS_XML:-$HOME/.config/monitors.xml}"
ENV_DIR="${ENV_DIR:-$HOME/.config/environment.d}"
ENV_FILE="${ENV_FILE:-$ENV_DIR/qt.conf}"
NOTIFY_BIN="${NOTIFY_BIN:-$(command -v notify-send || true)}"

if [[ ! -f "$MONITORS_XML" ]]; then
  exit 0
fi

mapfile -t scales < <(awk -F'[<>]' '/<scale>/{print $3}' "$MONITORS_XML")
if [[ ${#scales[@]} -eq 0 ]]; then
  exit 0
fi

max_scale="1"
for s in "${scales[@]}"; do
  if awk -v a="$s" -v b="$max_scale" 'BEGIN{exit !(a>b)}'; then
    max_scale="$s"
  fi
done

mkdir -p "$ENV_DIR"
content="QT_AUTO_SCREEN_SCALE_FACTOR=0
QT_SCALE_FACTOR=$max_scale"

existing=""
if [[ -f "$ENV_FILE" ]]; then
  existing="$(cat "$ENV_FILE")"
fi

if [[ "$existing" != "$content" ]]; then
  printf '%s\n' "$content" > "$ENV_FILE"
  if [[ -n "$NOTIFY_BIN" ]]; then
    "$NOTIFY_BIN" "Qt scale updated" "QT_SCALE_FACTOR=$max_scale. Restart Qt apps or log out/in." || true
  fi
fi
