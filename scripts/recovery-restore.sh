#!/usr/bin/env bash
set -euo pipefail

# Recovery script to rollback patched packages to original Debian versions

AUTO_YES=0

usage() {
  cat <<'EOF'
Usage: recovery-restore.sh [--list] [--backup TIMESTAMP] [-y|--yes]

  --list                Show available backups.
  --backup TIMESTAMP    Restore from specific backup (default: latest).
  -y,--yes              Skip confirmation prompts.
  -h,--help             Show this help.

Example:
  ./recovery-restore.sh --list
  ./recovery-restore.sh --backup 20250212-164200 -y
EOF
}

for arg in "$@"; do
  case "$arg" in
    --list) LIST=1 ;;
    --backup) shift; BACKUP_TS="$1" ;;
    -y|--yes) AUTO_YES=1 ;;
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

BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/share/debian-fix-backup}"

if [[ ! -d "$BACKUP_DIR" ]]; then
  fail "Backup directory not found: $BACKUP_DIR"
fi

if [[ "${LIST:-0}" -eq 1 ]]; then
  info "Available backups:"
  ls -1d "$BACKUP_DIR"/*/ 2>/dev/null | while read -r backup_path; do
    backup_ts=$(basename "$backup_path")
    if [[ -f "$backup_path/mutter.info" && -f "$backup_path/gnome-control-center.info" ]]; then
      mutter_ver=$(grep ^Version "$backup_path/mutter.info" | head -1 | cut -d' ' -f2)
      gcc_ver=$(grep ^Version "$backup_path/gnome-control-center.info" | head -1 | cut -d' ' -f2)
      echo "  $backup_ts: mutter=$mutter_ver, g-c-c=$gcc_ver"
    fi
  done
  exit 0
fi

if [[ -z "${BACKUP_TS:-}" ]]; then
  if [[ -f "$BACKUP_DIR/latest" ]]; then
    BACKUP_TS=$(cat "$BACKUP_DIR/latest")
  else
    fail "No latest backup found; use --list to see available backups"
  fi
fi

BACKUP_PATH="$BACKUP_DIR/$BACKUP_TS"

if [[ ! -d "$BACKUP_PATH" ]]; then
  fail "Backup not found: $BACKUP_PATH"
fi

if [[ ! -f "$BACKUP_PATH/mutter.info" || ! -f "$BACKUP_PATH/gnome-control-center.info" ]]; then
  fail "Backup incomplete; missing package info in $BACKUP_PATH"
fi

mutter_ver=$(grep ^Version "$BACKUP_PATH/mutter.info" | head -1 | cut -d' ' -f2)
gcc_ver=$(grep ^Version "$BACKUP_PATH/gnome-control-center.info" | head -1 | cut -d' ' -f2)

info "Restoring from backup: $BACKUP_TS"
info "  mutter: $mutter_ver"
info "  gnome-control-center: $gcc_ver"

if ! prompt_confirm "Proceed with restoration?"; then
  info "Cancelled"
  exit 0
fi

info "Removing package holds"
sudo apt-mark unhold mutter gnome-control-center 2>/dev/null || true

info "Reinstalling packages from Debian repositories"
sudo apt remove --allow-downgrades -y mutter gnome-control-center || true
sudo apt install --allow-downgrades -y "mutter=$mutter_ver" "gnome-control-center=$gcc_ver"

info "Removing x11 scaling from experimental features"
# Keep only other features if any
gsettings set org.gnome.mutter experimental-features "[]" 2>&1 | grep -v "Failed to load module" | grep -v "libgnutls" || true

info "Recompiling GLib schemas"
sudo glib-compile-schemas /usr/share/glib-2.0/schemas

ok "Recovery complete"
warn "Please re-login or reboot for changes to take effect"
