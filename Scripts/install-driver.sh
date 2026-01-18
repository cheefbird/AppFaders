#!/bin/bash
# install-driver.sh
# Builds the AppFaders driver and installs it to the HAL plug-ins directory
#
# Usage: ./Scripts/install-driver.sh
# Requires: sudo access for installation and coreaudiod restart

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HAL_PLUGINS_DIR="/Library/Audio/Plug-Ins/HAL"
DRIVER_NAME="AppFadersDriver.driver"

# colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # no color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() {
	echo -e "${RED}[ERROR]${NC} $1"
	exit 1
}

cd "$PROJECT_DIR"

# step 1: build
info "Building project..."
swift build || error "Build failed"

# step 2: locate built dylib
DYLIB_PATH=".build/debug/libAppFadersDriver.dylib"
if [[ ! -f $DYLIB_PATH ]]; then
	error "Built dylib not found at $DYLIB_PATH"
fi
info "Found dylib: $DYLIB_PATH"

# step 3: locate bundle structure created by plugin
BUNDLE_PATH=$(find .build -path "*BundleAssembler/$DRIVER_NAME" -type d 2>/dev/null | head -1)
if [[ -z $BUNDLE_PATH || ! -d $BUNDLE_PATH ]]; then
	error "Bundle structure not found. Make sure BundleAssembler plugin ran."
fi
info "Found bundle: $BUNDLE_PATH"

# step 4: copy dylib to bundle Contents/MacOS/
MACOS_DIR="$BUNDLE_PATH/Contents/MacOS"
BINARY_DEST="$MACOS_DIR/AppFadersDriver"
info "Copying dylib to bundle..."
cp "$DYLIB_PATH" "$BINARY_DEST"
chmod 755 "$BINARY_DEST"

# step 5: fix install name (dylib references @rpath/libAppFadersDriver.dylib which won't resolve)
info "Fixing install name..."
install_name_tool -id "@loader_path/AppFadersDriver" "$BINARY_DEST"
install_name_tool -change "@rpath/libAppFadersDriver.dylib" "@loader_path/AppFadersDriver" "$BINARY_DEST"

# step 6: code sign the binary
info "Code signing binary..."
# remove marker file that interferes with signing
rm -f "$BUNDLE_PATH/.bundle-ready"
# use SHA-1 hash to avoid ambiguity when multiple certs have same name
SIGNING_HASH=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')
if [[ -z $SIGNING_HASH ]]; then
	error "No 'Developer ID Application' certificate found in keychain"
fi
info "Using identity hash: $SIGNING_HASH"
codesign --force --options runtime --timestamp --sign "$SIGNING_HASH" "$BINARY_DEST" || error "Code signing failed"
info "Binary signed"

# step 7: verify bundle structure
if [[ ! -f "$BUNDLE_PATH/Contents/Info.plist" ]]; then
	error "Info.plist missing from bundle"
fi
if [[ ! -f $BINARY_DEST ]]; then
	error "Binary missing from bundle"
fi
info "Bundle structure verified"

# step 8: install to HAL directory (requires sudo)
INSTALL_PATH="$HAL_PLUGINS_DIR/$DRIVER_NAME"
info "Installing to $INSTALL_PATH (requires sudo)..."

if [[ -d $INSTALL_PATH ]]; then
	warn "Removing existing installation..."
	sudo rm -rf "$INSTALL_PATH"
fi

sudo cp -R "$BUNDLE_PATH" "$HAL_PLUGINS_DIR/"
sudo chown -R root:wheel "$INSTALL_PATH"
sudo chmod -R 755 "$INSTALL_PATH"
info "Driver installed"

# step 9: restart coreaudiod
info "Restarting coreaudiod (requires sudo)..."
sudo killall coreaudiod 2>/dev/null || true
sleep 2

# step 10: verify device appears
info "Verifying device registration..."
sleep 1

if system_profiler SPAudioDataType 2>/dev/null | grep -q "AppFaders"; then
	info "SUCCESS: AppFaders Virtual Device is registered!"
else
	warn "Device not found in system_profiler output"
	warn "Check Console.app for coreaudiod logs (filter: com.fbreidenbach.appfaders)"
	exit 1
fi

echo ""
info "Installation complete!"
info "The device should appear in System Settings > Sound > Output"
