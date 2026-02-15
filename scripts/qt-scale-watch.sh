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
qt_font_dpi=$(awk -v s="$max_scale" 'BEGIN{printf "%d", (s * 96) + 0.5}')
# Ensure decimal separator is a dot regardless of locale
qt_scale_factor=$(LC_NUMERIC=C awk -v s="$max_scale" 'BEGIN{printf "%.2f", s}')

# Exclude certain applications from QT_SCALE_FACTOR.
# By default `flameshot` is excluded to avoid pin-screenshot scaling issues.
excluded_apps=("flameshot")
for app in "${excluded_apps[@]}"; do
  if pgrep -x "$app" > /dev/null; then
    echo "Skipping QT_SCALE_FACTOR for $app"
    # Only set QT_FONT_DPI for excluded apps so their UI fonts remain correct
    content="QT_FONT_DPI=$qt_font_dpi"
    break
  fi
done

existing=""
if [[ -f "$ENV_FILE" ]]; then
  existing="$(cat "$ENV_FILE")"
fi

if [[ -t 0 ]]; then
  # Explain what the script does
  cat << EOF
This script adjusts Qt application scaling based on your current display scale.
It sets the following environment variables:
  - QT_FONT_DPI: Adjusts font DPI for Qt applications.
  - QT_SCALE_FACTOR: Adjusts the scaling factor for Qt applications.

Certain applications (e.g., flameshot) are excluded from QT_SCALE_FACTOR adjustments.
EOF

  # Ask the user for confirmation
  echo -n "Do you want to apply these settings? (y/N): "
  read -r user_input
  if [[ ! "$user_input" =~ ^[Yy]$ ]]; then
    echo "Settings were not applied. Exiting."
    exit 0
  fi
fi

if [[ "$existing" != "QT_FONT_DPI=$qt_font_dpi\nQT_SCALE_FACTOR=$qt_scale_factor" ]]; then
  # Write two separate lines to qt.conf using a here-doc to avoid locale/newline issues
  cat > "$ENV_FILE" <<EOF
QT_FONT_DPI=$qt_font_dpi
QT_SCALE_FACTOR=$qt_scale_factor
EOF
  if [[ -n "$NOTIFY_BIN" ]]; then
    "$NOTIFY_BIN" "Qt scale updated" "QT_FONT_DPI=$qt_font_dpi. Restart Qt apps or log out/in." || true
  fi
fi
