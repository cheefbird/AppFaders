#!/bin/bash
# uninstall-driver.sh
# Removes the AppFaders driver from the system

set -e

DRIVER_PATH="/Library/Audio/Plug-Ins/HAL/AppFadersDriver.driver"

if [[ ! -d $DRIVER_PATH ]]; then
	echo "Driver not installed at $DRIVER_PATH"
	exit 0
fi

echo "Removing $DRIVER_PATH..."
sudo rm -rf "$DRIVER_PATH"

echo "Restarting coreaudiod..."
sudo killall coreaudiod 2>/dev/null || true
sleep 2

echo "Done. Driver uninstalled."
