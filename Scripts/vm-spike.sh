#!/bin/bash
# vm-spike.sh
# Run this INSIDE a Tart macOS VM to validate HAL driver loading.
# Expects the AppFaders repo to be shared at /Volumes/My Shared Files/appfaders
# with a completed `swift build` from the host.
#
# Usage: bash "/Volumes/My Shared Files/appfaders/Scripts/vm-spike.sh"

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $1"; }
step()  { echo -e "\n${CYAN}--- $1 ---${NC}"; }

SHARED_DIR="/Volumes/My Shared Files/appfaders"
WORK_DIR="$HOME/appfaders-spike"
HAL_PLUGINS_DIR="/Library/Audio/Plug-Ins/HAL"
DRIVER_NAME="AppFadersDriver.driver"
HELPER_NAME="AppFadersHelper"
HELPER_SUPPORT_DIR="/Library/Application Support/AppFaders"
LAUNCHDAEMON_PLIST="com.fbreidenbach.appfaders.helper.plist"
LAUNCHDAEMONS_DIR="/Library/LaunchDaemons"

# ─── Step 1: Baseline audio check ───────────────────────────────────

step "Step 1: Baseline audio check"

# coreaudiod runs in the system domain, so check with sudo
if sudo launchctl list 2>/dev/null | grep -q coreaudiod; then
  info "coreaudiod is running (system domain)"
else
  fail "coreaudiod is NOT running — audio subsystem may not be available in this VM"
  fail "RESULT: FAIL — no audio subsystem"
  exit 1
fi

AUDIO_BASELINE=$(system_profiler SPAudioDataType 2>/dev/null)
if [[ -n "$AUDIO_BASELINE" ]] && echo "$AUDIO_BASELINE" | grep -qi "device"; then
  info "Audio devices found:"
  echo "$AUDIO_BASELINE"
else
  fail "No audio devices found in system_profiler"
  exit 1
fi

info "SIP status:"
csrutil status 2>/dev/null || warn "Could not check SIP status"

# ─── Step 2: Copy build artifacts ────────────────────────────────────

step "Step 2: Copy build artifacts from shared directory"

if [[ ! -d "$SHARED_DIR" ]]; then
  fail "Shared directory not found at $SHARED_DIR"
  fail "Make sure you booted the VM with: tart run --dir=appfaders:~/Developer/AppFaders:ro"
  exit 1
fi

if [[ ! -d "$SHARED_DIR/.build" ]]; then
  fail "No .build directory found — run 'swift build' on the host first"
  exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

info "Copying .build directory..."
cp -RX "$SHARED_DIR/.build" "$WORK_DIR/.build" || true

info "Copying Resources..."
cp -RX "$SHARED_DIR/Resources" "$WORK_DIR/Resources" || true

# ─── Step 3: Prep driver bundle ──────────────────────────────────────

step "Step 3: Prepare driver bundle"

DYLIB_PATH="$WORK_DIR/.build/debug/libAppFadersDriver.dylib"
if [[ ! -f "$DYLIB_PATH" ]]; then
  fail "Driver dylib not found at $DYLIB_PATH"
  exit 1
fi

BUNDLE_PATH=$(find "$WORK_DIR/.build" -path "*BundleAssembler/$DRIVER_NAME" -type d 2>/dev/null | head -1)
if [[ -z "$BUNDLE_PATH" || ! -d "$BUNDLE_PATH" ]]; then
  fail "Bundle structure not found — BundleAssembler plugin may not have run"
  exit 1
fi
info "Found bundle: $BUNDLE_PATH"

BINARY_DEST="$BUNDLE_PATH/Contents/MacOS/AppFadersDriver"
cp "$DYLIB_PATH" "$BINARY_DEST"
chmod 755 "$BINARY_DEST"

info "Fixing install name..."
install_name_tool -id "@loader_path/AppFadersDriver" "$BINARY_DEST"
install_name_tool -change "@rpath/libAppFadersDriver.dylib" "@loader_path/AppFadersDriver" "$BINARY_DEST"

info "Ad-hoc code signing..."
rm -f "$BUNDLE_PATH/.bundle-ready"
codesign --force --sign - "$BINARY_DEST"
info "Signed (ad-hoc)"

# verify bundle
if [[ ! -f "$BUNDLE_PATH/Contents/Info.plist" ]]; then
  fail "Info.plist missing from bundle"
  exit 1
fi
info "Bundle structure verified"

# ─── Step 4: Install helper ──────────────────────────────────────────

step "Step 4: Install helper service"

HELPER_BINARY="$WORK_DIR/.build/debug/$HELPER_NAME"
if [[ ! -f "$HELPER_BINARY" ]]; then
  fail "Helper binary not found at $HELPER_BINARY"
  exit 1
fi

sudo mkdir -p "$HELPER_SUPPORT_DIR"
sudo cp "$HELPER_BINARY" "$HELPER_SUPPORT_DIR/"
sudo chmod 755 "$HELPER_SUPPORT_DIR/$HELPER_NAME"
sudo chown root:wheel "$HELPER_SUPPORT_DIR/$HELPER_NAME"
info "Helper binary installed"

# install LaunchDaemon plist
PLIST_SOURCE="$WORK_DIR/Resources/$LAUNCHDAEMON_PLIST"
if [[ -f "$PLIST_SOURCE" ]]; then
  sudo launchctl bootout system "$LAUNCHDAEMONS_DIR/$LAUNCHDAEMON_PLIST" 2>/dev/null || true
  sudo cp "$PLIST_SOURCE" "$LAUNCHDAEMONS_DIR/"
  sudo chown root:wheel "$LAUNCHDAEMONS_DIR/$LAUNCHDAEMON_PLIST"
  sudo chmod 644 "$LAUNCHDAEMONS_DIR/$LAUNCHDAEMON_PLIST"
  sudo launchctl bootstrap system "$LAUNCHDAEMONS_DIR/$LAUNCHDAEMON_PLIST" || warn "Failed to bootstrap LaunchDaemon"
  info "Helper LaunchDaemon installed"
else
  warn "LaunchDaemon plist not found at $PLIST_SOURCE — skipping"
fi

# ─── Step 5: Install driver ──────────────────────────────────────────

step "Step 5: Install driver to HAL directory"

INSTALL_PATH="$HAL_PLUGINS_DIR/$DRIVER_NAME"
sudo mkdir -p "$HAL_PLUGINS_DIR"

if [[ -d "$INSTALL_PATH" ]]; then
  warn "Removing existing installation..."
  sudo rm -rf "$INSTALL_PATH"
fi

sudo cp -R "$BUNDLE_PATH" "$HAL_PLUGINS_DIR/"
sudo chown -R root:wheel "$INSTALL_PATH"
sudo chmod -R 755 "$INSTALL_PATH"
info "Driver installed to $INSTALL_PATH"

# ─── Step 6: Restart coreaudiod ──────────────────────────────────────

step "Step 6: Restart coreaudiod"

sudo killall coreaudiod 2>/dev/null || true
info "Waiting for coreaudiod to restart..."
sleep 3

# ─── Step 7: Validate ────────────────────────────────────────────────

step "Step 7: Validate HAL plugin registration"

info "Checking system_profiler for AppFaders device..."
AUDIO_OUTPUT=$(system_profiler SPAudioDataType 2>/dev/null)

if echo "$AUDIO_OUTPUT" | grep -qi "appfaders"; then
  echo ""
  info "======================================"
  info "  RESULT: PASS"
  info "  AppFaders Virtual Device registered!"
  info "======================================"
  echo ""
  info "Audio devices:"
  echo "$AUDIO_OUTPUT"
else
  warn "AppFaders device NOT found in system_profiler"
  echo ""
  info "Full audio output:"
  echo "$AUDIO_OUTPUT"
  echo ""
  info "Checking coreaudiod logs..."
  log show --last 30s --predicate 'process == "coreaudiod"' --info 2>/dev/null || true
  echo ""
  info "Checking driver logs..."
  log show --last 30s --predicate 'subsystem == "com.fbreidenbach.appfaders.driver"' 2>/dev/null || true
  echo ""
  fail "======================================"
  fail "  RESULT: PARTIAL FAIL"
  fail "  coreaudiod runs but driver not loaded"
  fail "  Try: disable SIP and re-run"
  fail "======================================"
fi
