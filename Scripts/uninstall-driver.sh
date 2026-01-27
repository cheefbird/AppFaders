#!/bin/bash
# uninstall-driver.sh
# Removes the AppFaders driver and helper service from the system

set -e

DRIVER_PATH="/Library/Audio/Plug-Ins/HAL/AppFadersDriver.driver"
HELPER_NAME="AppFadersHelper"
HELPER_SUPPORT_DIR="/Library/Application Support/AppFaders"
LAUNCHAGENT_PLIST="com.fbreidenbach.appfaders.helper.plist"
LAUNCHAGENTS_DIR="/Library/LaunchAgents"

# colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# step 1: remove driver
if [[ -d $DRIVER_PATH ]]; then
  info "Removing driver at $DRIVER_PATH..."
  sudo rm -rf "$DRIVER_PATH"
else
  warn "Driver not installed at $DRIVER_PATH"
fi

# step 2: restart coreaudiod
info "Restarting coreaudiod..."
sudo killall coreaudiod 2>/dev/null || true
sleep 2

# step 3: unload LaunchAgent (ignore errors if not loaded)
info "Unloading helper LaunchAgent..."
sudo launchctl unload "$LAUNCHAGENTS_DIR/$LAUNCHAGENT_PLIST" 2>/dev/null || true

# step 4: remove LaunchAgent plist
if [[ -f "$LAUNCHAGENTS_DIR/$LAUNCHAGENT_PLIST" ]]; then
  info "Removing LaunchAgent plist..."
  sudo rm -f "$LAUNCHAGENTS_DIR/$LAUNCHAGENT_PLIST"
else
  warn "LaunchAgent plist not found"
fi

# step 5: remove helper binary
if [[ -f "$HELPER_SUPPORT_DIR/$HELPER_NAME" ]]; then
  info "Removing helper binary..."
  sudo rm -f "$HELPER_SUPPORT_DIR/$HELPER_NAME"
else
  warn "Helper binary not found"
fi

# step 6: remove support directory if empty
if [[ -d "$HELPER_SUPPORT_DIR" ]]; then
  if [[ -z "$(ls -A "$HELPER_SUPPORT_DIR")" ]]; then
    info "Removing empty support directory..."
    sudo rmdir "$HELPER_SUPPORT_DIR"
  else
    warn "Support directory not empty, leaving in place"
  fi
fi

info "Done. Driver and helper uninstalled."
