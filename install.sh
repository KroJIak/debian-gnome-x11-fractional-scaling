#!/usr/bin/env bash
set -euo pipefail

AUTO_YES=0
DEBUG=0
ONLY_QT=0

usage() {
  cat <<'EOF'
Usage: install.sh [--debug] [-y|--yes]
                  [--only-qt]

  --debug   Show full command output.
  -y,--yes  Accept all prompts automatically.
  --only-qt Install only qt-scale-watch and units.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
    -y|--yes) AUTO_YES=1 ;;
    --only-qt) ONLY_QT=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage; exit 1 ;;
  esac
done

if command -v tput >/dev/null 2>&1; then
  COLOR_OK=$(tput setaf 2)
  COLOR_WARN=$(tput setaf 3)
  COLOR_ERR=$(tput setaf 1)
  COLOR_INFO=$(tput setaf 6)
  COLOR_DIM=$(tput setaf 7)
  COLOR_RESET=$(tput sgr0)
else
  COLOR_OK=""
  COLOR_WARN=""
  COLOR_ERR=""
  COLOR_INFO=""
  COLOR_DIM=""
  COLOR_RESET=""
fi

fail() {
  echo "${COLOR_ERR}[error]${COLOR_RESET} $*" >&2
  exit 1
}

info() {
  echo "${COLOR_INFO}[info]${COLOR_RESET} $*"
}

warn() {
  echo "${COLOR_WARN}[warn]${COLOR_RESET} $*" >&2
}

ok() {
  echo "${COLOR_OK}[ok]${COLOR_RESET} $*"
}

prompt_confirm() {
  local message="$1"
  if [[ "$AUTO_YES" -eq 1 ]]; then
    echo "${COLOR_DIM}[auto-yes]${COLOR_RESET} $message"
    return 0
  fi
  read -r -p "$message [y/N]: " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_DIR="${LOG_DIR:-$HOME/.cache/debian-fix-install/logs}"

run_cmd() {
  local label="$1"
  shift
  mkdir -p "$LOG_DIR"
  if [[ "$DEBUG" -eq 1 ]]; then
    info "$label"
    "$@"
  else
    local log_file
    log_file="$LOG_DIR/$(date +%Y%m%d-%H%M%S)-${label// /_}.log"
    info "$label (log: $log_file)"
    if ! "$@" >"$log_file" 2>&1; then
      warn "$label failed; see $log_file"
      tail -n 40 "$log_file" >&2 || true
      return 1
    fi
  fi
}

FIX_SRC="$SCRIPT_DIR/scripts/fix-scale.sh"
QT_SRC="$SCRIPT_DIR/scripts/qt-scale-watch.sh"
UNIT_PATH_SRC="$SCRIPT_DIR/systemd/user/qt-scale-update.path"
UNIT_SERVICE_SRC="$SCRIPT_DIR/systemd/user/qt-scale-update.service"

[[ -f "$FIX_SRC" ]] || fail "Missing: $FIX_SRC"
[[ -f "$QT_SRC" ]] || fail "Missing: $QT_SRC"
[[ -f "$UNIT_PATH_SRC" ]] || fail "Missing: $UNIT_PATH_SRC"
[[ -f "$UNIT_SERVICE_SRC" ]] || fail "Missing: $UNIT_SERVICE_SRC"

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SYSTEMD_USER_DIR="${SYSTEMD_USER_DIR:-$HOME/.config/systemd/user}"

info "Installing fix script"
if [[ "$ONLY_QT" -eq 0 ]]; then
  run_cmd "mkdir bin dir" mkdir -p "$BIN_DIR"
  run_cmd "install fix-scale" install -m 0755 "$FIX_SRC" "$BIN_DIR/fix-scale"
  ok "Installed: $BIN_DIR/fix-scale"

  if ! echo ":$PATH:" | grep -q ":$BIN_DIR:"; then
    warn "$BIN_DIR is not in PATH; add it to use 'fix-scale' easily"
  fi
fi

if prompt_confirm "Install qt-scale-watch? This keeps Qt apps in sync with GNOME scaling changes and avoids blurry or wrong-sized Qt UI after you change scale."; then
  info "Installing qt-scale-watch"
  run_cmd "install qt-scale-watch" install -m 0755 "$QT_SRC" "$BIN_DIR/qt-scale-watch"
  run_cmd "mkdir systemd user dir" mkdir -p "$SYSTEMD_USER_DIR"
  run_cmd "install qt-scale-update.path" install -m 0644 "$UNIT_PATH_SRC" "$SYSTEMD_USER_DIR/qt-scale-update.path"
  run_cmd "install qt-scale-update.service" install -m 0644 "$UNIT_SERVICE_SRC" "$SYSTEMD_USER_DIR/qt-scale-update.service"

  if command -v systemctl >/dev/null 2>&1; then
    run_cmd "systemctl --user daemon-reload" systemctl --user daemon-reload
    run_cmd "enable qt-scale-update.path" systemctl --user enable --now qt-scale-update.path
    ok "qt-scale-watch enabled"
  else
    warn "systemctl not found; enable qt-scale-update.path manually"
  fi
else
  info "Skipping qt-scale-watch installation"
fi

ok "done"
warn "Re-login or reboot is required for changes to fully apply"
