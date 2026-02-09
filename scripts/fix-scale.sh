#!/usr/bin/env bash
set -euo pipefail

AUTO_YES=0
DEBUG=0

usage() {
  cat <<'EOF'
Usage: fix.sh [--debug] [-y|--yes]

  --debug   Show full command output.
  -y,--yes  Accept all prompts automatically.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
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

WORKDIR="${WORKDIR:-$HOME/debian-x11-scale}"
LOG_DIR="${LOG_DIR:-$WORKDIR/logs}"
MUTTER_PATCH_REPO="${MUTTER_PATCH_REPO:-https://github.com/puxplaying/mutter-x11-scaling.git}"
GCC_PATCH_REPO="${GCC_PATCH_REPO:-https://github.com/puxplaying/gnome-control-center-x11-scaling.git}"

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

ensure_clean_gcc_source() {
  local src_dir="$1"
  local file_rel="panels/display/cc-display-config.c"
  local file_path="$src_dir/$file_rel"
  local symbol="cc_display_config_layout_use_ui_scale"
  local count

  if [[ ! -f "$file_path" ]]; then
    return 0
  fi

  count=$(grep -c "$symbol" "$file_path" || true)
  if [[ "$count" -le 1 ]]; then
    return 0
  fi

  warn "Detected duplicate '$symbol' definitions in $file_rel (count=$count)"
  if prompt_confirm "Re-extract gnome-control-center source to clean patches?"; then
    rm -rf "$src_dir"
    run_cmd "apt source g-c-c" apt source gnome-control-center
  else
    fail "Source tree contains duplicate definitions; aborting"
  fi
}

patch_if_needed() {
  local label="$1"
  local marker_file="$2"
  local marker_grep="$3"
  local patch_file="$4"

  if grep -q "$marker_grep" "$marker_file"; then
    warn "$label already applied; skipping"
    return 0
  fi

  run_cmd "$label" patch -p1 -N < "$patch_file"
}

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" != "debian" ]]; then
    warn "This script targets Debian; detected ID='${ID:-unknown}'"
    prompt_confirm "Continue anyway?" || exit 1
  fi
  case "${VERSION_ID:-}" in
    12|13) : ;;
    *)
      warn "Expected Debian 12/13, got '${VERSION_ID:-unknown}'"
      prompt_confirm "Continue anyway?" || exit 1
      ;;
  esac
fi

if command -v gnome-shell >/dev/null 2>&1; then
  gs_ver=$(gnome-shell --version | awk '{print $3}')
  if [[ "${gs_ver:-}" != 48* ]]; then
    warn "Expected GNOME 48, got '${gs_ver:-unknown}'"
    prompt_confirm "Continue anyway?" || exit 1
  fi
else
  warn "gnome-shell not found"
  prompt_confirm "Continue anyway?" || exit 1
fi

if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
  warn "Current session is '${XDG_SESSION_TYPE:-unknown}', Xorg is required"
  prompt_confirm "Continue anyway?" || exit 1
fi

info "Installing build tools"
if ! run_cmd "apt update" sudo apt update; then
  warn "apt update failed; continuing with existing package lists"
  warn "Consider disabling unsigned repos (e.g. repo.fig.io)"
fi
run_cmd "apt install base tools" sudo apt install -y devscripts build-essential quilt git

info "Installing build dependencies for mutter"
run_cmd "apt build-dep mutter" sudo apt build-dep -y mutter

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

if [[ ! -d mutter-x11-scaling ]]; then
  run_cmd "clone mutter-x11-scaling" git clone "${MUTTER_PATCH_REPO}"
fi

if ! ls -d mutter-48.* >/dev/null 2>&1; then
  run_cmd "apt source mutter" apt source mutter
fi

MUTTER_DIR=$(ls -d mutter-48.* 2>/dev/null | head -n1 || true)
[[ -n "${MUTTER_DIR}" ]] || fail "mutter-48.* source directory not found"

PATCH_FILE="${WORKDIR}/mutter-x11-scaling/x11-Add-support-for-fractional-scaling-using-Randr.patch"
[[ -f "${PATCH_FILE}" ]] || fail "patch not found: ${PATCH_FILE}"

cd "${WORKDIR}/${MUTTER_DIR}"

info "Preparing Debian changelog"
export DEBFULLNAME="${DEBFULLNAME:-Local Builder}"
export DEBEMAIL="${DEBEMAIL:-local@example.invalid}"
if ! grep -q "x11scale" debian/changelog; then
  dch --local "~x11scale1" "Enable X11 fractional scaling (local build)" >/dev/null
fi

info "Applying patch with quilt"
export QUILT_PATCHES=debian/patches
cp -f "${PATCH_FILE}" "${QUILT_PATCHES}/"
if ! grep -q "x11-Add-support-for-fractional-scaling-using-Randr.patch" "${QUILT_PATCHES}/series"; then
  echo "x11-Add-support-for-fractional-scaling-using-Randr.patch" >> "${QUILT_PATCHES}/series"
fi

if ! quilt push -a; then
  if quilt applied | grep -q "x11-Add-support-for-fractional-scaling-using-Randr.patch"; then
    warn "Patch already applied; continuing"
  else
    warn "Patch did not apply cleanly on mutter ${MUTTER_DIR}"
    warn "Manual porting is required; see the *.rej files if present"
    exit 1
  fi
fi

info "Building mutter package"
run_cmd "build mutter" env DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-nocheck} dpkg-buildpackage -b -us -uc

info "Installing mutter packages"
cd "${WORKDIR}"
run_cmd "dpkg install mutter" sudo dpkg -i ./*~x11scale*.deb
run_cmd "glib-compile-schemas" sudo glib-compile-schemas /usr/share/glib-2.0/schemas

info "Enable X11 fractional scaling feature"
run_cmd "gsettings set fractional" gsettings set org.gnome.mutter experimental-features "['x11-randr-fractional-scaling']" || true

info "Installing build dependencies for gnome-control-center"
run_cmd "apt build-dep g-c-c" sudo apt build-dep -y gnome-control-center

if [[ ! -d gnome-control-center-x11-scaling ]]; then
  run_cmd "clone g-c-c-x11-scaling" git clone "${GCC_PATCH_REPO}"
fi

if ! ls -d gnome-control-center-48.* >/dev/null 2>&1; then
  run_cmd "apt source g-c-c" apt source gnome-control-center
fi

GCC_DIR=$(ls -d gnome-control-center-48.* 2>/dev/null | head -n1 || true)
[[ -n "${GCC_DIR}" ]] || fail "gnome-control-center-48.* source directory not found"

ensure_clean_gcc_source "${WORKDIR}/${GCC_DIR}"
GCC_DIR=$(ls -d gnome-control-center-48.* 2>/dev/null | head -n1 || true)
[[ -n "${GCC_DIR}" ]] || fail "gnome-control-center-48.* source directory not found"

cd "${WORKDIR}/${GCC_DIR}"

info "Preparing Debian changelog for gnome-control-center"
if ! grep -q "x11scale" debian/changelog; then
  dch --local "~x11scale1" "Enable X11 fractional scaling UI" >/dev/null
fi

info "Applying gnome-control-center patches"
patch_if_needed \
  "patch g-c-c layout" \
  "panels/display/cc-display-config-dbus.c" \
  "GLOBAL_UI_LOGICAL" \
  "${WORKDIR}/gnome-control-center-x11-scaling/display-Support-UI-scaled-logical-monitor-mode.patch"

patch_if_needed \
  "patch g-c-c fractional" \
  "panels/display/cc-display-settings.ui" \
  "scale_fractional_row" \
  "${WORKDIR}/gnome-control-center-x11-scaling/display-Allow-fractional-scaling-to-be-enabled.patch"

info "Building gnome-control-center packages"
run_cmd "build g-c-c" env DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-nocheck} dpkg-buildpackage -b -us -uc

info "Installing gnome-control-center packages"
cd "${WORKDIR}"
run_cmd "dpkg install g-c-c" sudo dpkg -i ./gnome-control-center*~x11scale*.deb
run_cmd "glib-compile-schemas" sudo glib-compile-schemas /usr/share/glib-2.0/schemas

if prompt_confirm "Hold GNOME packages to avoid breaking updates?"; then
  run_cmd "apt-mark hold" sudo apt-mark hold mutter gnome-control-center
  ok "Packages held"
fi

if prompt_confirm "Clean build artifacts (.deb/.changes/.buildinfo) in $WORKDIR?"; then
  rm -f "$WORKDIR"/*.deb "$WORKDIR"/*.changes "$WORKDIR"/*.buildinfo || true
  ok "Artifacts removed"
fi

if [[ -n "${WORKDIR}" && "${WORKDIR}" != "/" ]]; then
  rm -rf "${WORKDIR}"
  ok "Removed workdir: ${WORKDIR}"
fi

ok "done"
