#!/usr/bin/env bash
set -euo pipefail

AUTO_YES=0
DEBUG=0

# Always skip running unit tests during Debian builds unless explicitly overridden
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-nocheck}

usage() {
  cat <<'EOF'
Usage: fix.sh [--debug] [-y|--yes]

  --debug   Show full command output.
  -y,--yes  Accept all prompts automatically.
EOF
}

# Do not run the full interactive patch/build as root. Running as root
# causes `gsettings` to operate on root's dconf database, not the user's,
# which can result in experimental features being written to the wrong account
# and the UI showing options that don't take effect for the logged-in user.
if [[ "$(id -u)" -eq 0 ]]; then
  warn "It looks like you're running this script as root. This is not recommended."
  warn "Run this script as your regular user (it will use sudo internally for package operations)."
  if ! prompt_confirm "Continue running as root?"; then
    fail "Aborting: re-run the script as your regular user."
  fi
fi

for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
    -y|--yes) AUTO_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage; exit 1 ;;
  esac
done

# Set APT_YES_FLAG based on AUTO_YES
if [[ "$AUTO_YES" -eq 1 ]]; then
  APT_YES_FLAG="-y"
else
  APT_YES_FLAG=""
fi

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

backup_original_packages() {
  local backup_ts
  backup_ts=$(date +%Y%m%d-%H%M%S)
  local backup_path="$BACKUP_DIR/$backup_ts"
  
  mkdir -p "$backup_path"
  
  info "Backing up original mutter and gnome-control-center packages"
  local mutter_pkg gnome_cc_pkg
  mutter_pkg=$(dpkg-query -W -f='${Package}' mutter 2>/dev/null || true)
  gnome_cc_pkg=$(dpkg-query -W -f='${Package}' gnome-control-center 2>/dev/null || true)
  
  if [[ -n "$mutter_pkg" ]]; then
    run_cmd "backup mutter" bash -lc "apt-cache show '$mutter_pkg' > '$backup_path/mutter.info'"
  fi
  if [[ -n "$gnome_cc_pkg" ]]; then
    run_cmd "backup gnome-cc" bash -lc "apt-cache show '$gnome_cc_pkg' > '$backup_path/gnome-control-center.info'"
  fi
  
  echo "$backup_ts" > "$BACKUP_DIR/latest"
  ok "Backup created at $backup_path"
}

validate_patch_applied() {
  local src_dir="$1"
  local rej_files
  rej_files=$(find "$src_dir" -name '*.rej' 2>/dev/null | wc -l)
  
  if [[ $rej_files -gt 0 ]]; then
    fail "Patch conflicts detected ($rej_files .rej files found)"
  fi
}

validate_feature_enabled() {
  local features
  features=$(gsettings get org.gnome.mutter experimental-features 2>/dev/null || echo "['']")
  
  if ! echo "$features" | grep -q 'x11-randr-fractional-scaling'; then
    warn "Feature x11-randr-fractional-scaling not found in experimental-features: $features"
    return 1
  fi
  ok "Feature x11-randr-fractional-scaling enabled"
  return 0
}

add_experimental_feature() {
  local feature_to_add="$1"
  local current_features
  local new_features
  
  current_features=$(gsettings get org.gnome.mutter experimental-features 2>/dev/null || echo "[]")
  
  # Check if feature already exists
  if echo "$current_features" | grep -q "$feature_to_add"; then
    return 0
  fi
  
  # Extract array contents and add new feature
  # Example: ['scale-monitor-framebuffer'] -> ['scale-monitor-framebuffer', 'x11-randr-fractional-scaling']
  if [[ "$current_features" == "[]" ]]; then
    new_features="['$feature_to_add']"
  else
    # Remove trailing ']' then append the new feature
    new_features="${current_features%}]"
    new_features="${new_features}, '$feature_to_add']"
  fi
  
  gsettings set org.gnome.mutter experimental-features "$new_features" 2>&1 | grep -v "Failed to load module" | grep -v "libgnutls" || true
}

WORKDIR="${WORKDIR:-$HOME/debian-x11-scale}"
LOG_DIR="${LOG_DIR:-$WORKDIR/logs}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/share/debian-fix-backup}"
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

# If mutter already appears to be a locally patched package, skip rebuilding
# unless the user explicitly wants to force reapply. This avoids repeatedly
# replacing the system mutter package and reduces the chance of session
# breakage when the script is re-run.
installed_version=$(dpkg-query -W -f='${Version}' mutter 2>/dev/null || true)
if [[ -n "$installed_version" && "$installed_version" == *x11scale* ]]; then
  warn "Detected installed mutter package appears to be a local x11scale build: $installed_version"
  if prompt_confirm "Skip rebuilding and installing mutter (already patched)?"; then
    ok "Skipping mutter build/install"
    # Still attempt to enable the experimental feature and continue with g-c-c
    add_experimental_feature "x11-randr-fractional-scaling" || true
    if ! validate_feature_enabled; then
      warn "Feature may not have been enabled correctly"
    fi
    # Continue on to gnome-control-center patching/build steps
  else
    info "User requested to continue and rebuild mutter"
  fi
fi

if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
  warn "Current session is '${XDG_SESSION_TYPE:-unknown}', Xorg is required"
  prompt_confirm "Continue anyway?" || exit 1
fi

if ! command -v quilt >/dev/null 2>&1; then
  fail "quilt is required but not installed; install with: sudo apt install quilt"
fi

info "Installing build tools"
if ! run_cmd "apt update" sudo apt update; then
  warn "apt update failed; continuing with existing package lists"
  warn "Consider disabling unsigned repos (e.g. repo.fig.io)"
fi
run_cmd "apt install base tools" sudo apt install $APT_YES_FLAG devscripts build-essential quilt git

if prompt_confirm "Create backup of original packages before patching?"; then
  backup_original_packages
else
  warn "Proceeding without backup; consider this unsafe"
fi

info "Installing build dependencies for mutter"
run_cmd "apt build-dep mutter" sudo apt build-dep $APT_YES_FLAG mutter

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

validate_patch_applied "${WORKDIR}/${MUTTER_DIR}"

info "Building mutter package"
run_cmd "build mutter" env DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-nocheck} dpkg-buildpackage -b -us -uc

info "Installing mutter packages"
cd "${WORKDIR}"
run_cmd "dpkg install mutter" sudo dpkg -i ./*~x11scale*.deb
run_cmd "glib-compile-schemas" sudo glib-compile-schemas /usr/share/glib-2.0/schemas

# Post-install verification: show installed package versions so user can
# confirm the local x11scale packages are in place and know what to reboot.
installed_mutter_ver=$(dpkg-query -W -f='${Version}' mutter 2>/dev/null || true)
installed_gcc_ver=$(dpkg-query -W -f='${Version}' gnome-control-center 2>/dev/null || true)
info "Installed mutter version: ${installed_mutter_ver:-<not-installed>}"
info "Installed gnome-control-center version: ${installed_gcc_ver:-<not-installed>}"
if [[ -n "${installed_mutter_ver}" && "${installed_mutter_ver}" == *x11scale* ]]; then
  ok "Detected local mutter package (${installed_mutter_ver}). Reboot required for changes to take effect."
else
  warn "mutter package does not look like the local x11scale build. If you reinstalled stock mutter earlier, the patched package may have been overwritten."
fi
if [[ -n "${installed_gcc_ver}" && "${installed_gcc_ver}" == *x11scale* ]]; then
  ok "Detected local gnome-control-center package (${installed_gcc_ver})."
else
  warn "gnome-control-center package does not look like the local x11scale build. The UI toggle may appear but not work if the backend (mutter) isn't patched/active."
fi

info "Enable X11 fractional scaling feature"
add_experimental_feature "x11-randr-fractional-scaling"

if ! validate_feature_enabled; then
  warn "Feature may not have been enabled correctly"
fi

info "Installing build dependencies for gnome-control-center"
run_cmd "apt build-dep g-c-c" sudo apt build-dep $APT_YES_FLAG gnome-control-center

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

info "Holding mutter and gnome-control-center to avoid accidental overwrites"
run_cmd "apt-mark hold" sudo apt-mark hold mutter gnome-control-center || true
ok "Packages held"

if prompt_confirm "Clean build artifacts (.deb/.changes/.buildinfo) in $WORKDIR?"; then
  rm -f "$WORKDIR"/*.deb "$WORKDIR"/*.changes "$WORKDIR"/*.buildinfo || true
  ok "Artifacts removed"
fi

if [[ -n "${WORKDIR}" && "${WORKDIR}" != "/" ]]; then
  rm -rf "${WORKDIR}"
  ok "Removed workdir: ${WORKDIR}"
fi

ok "Installation complete"
info "Backup location: $BACKUP_DIR"
info "To rollback: sudo apt install --allow-downgrades $(ls $BACKUP_DIR/latest -r | head -1 | xargs -I {} cat $BACKUP_DIR/{}/mutter.info | grep ^Package | awk '{print $2}')"
warn "Please re-login or reboot for changes to take effect"
