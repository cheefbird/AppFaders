# XPC Integration Test Procedure

Manual test to verify XPC communication between host app, helper service, and driver.

## Prerequisites

- macOS 26+ (arm64)
- Developer ID Application certificate in keychain
- Admin access for installation

## Test Steps

### 1. Install Helper and Driver

```bash
./Scripts/install-driver.sh
```

**Expected output:**
- Helper binary copied to `/Library/Application Support/AppFaders/`
- LaunchAgent plist installed to `/Library/LaunchAgents/`
- LaunchAgent loaded
- Driver installed to `/Library/Audio/Plug-Ins/HAL/`
- coreaudiod restarted
- "AppFaders Virtual Device is registered!" message

### 2. Verify Helper Registration

```bash
launchctl list | grep appfaders
```

**Expected:** Line containing `com.fbreidenbach.appfaders.helper`

Note: If using system-wide installation, use `sudo launchctl list` instead.

### 3. Check Driver Logs (Terminal 1)

```bash
log stream --predicate 'subsystem == "com.fbreidenbach.appfaders.driver"' --level debug
```

**Expected on startup:** "Connecting to helper" and "XPC connection established" messages

### 4. Check Helper Logs (Terminal 2)

```bash
log stream --predicate 'subsystem == "com.fbreidenbach.appfaders.helper"' --level debug
```

**Expected:** "XPC connection accepted" when driver or host connects

### 5. Run Host App

```bash
swift run AppFaders
```

**Expected in host logs:**
- "Connected to AppFaders Helper Service"

**Expected in helper logs:**
- Second "XPC connection accepted" (from host)

### 6. Trigger Volume Change

Since the UI isn't implemented yet, add temporary debug code to `AudioOrchestrator.start()`:

```swift
// Temporary test - remove after verification
Task {
  try? await Task.sleep(for: .seconds(2))
  await setVolume(for: "com.apple.Safari", volume: 0.5)
}
```

Or use lldb if running in debugger:
```
(lldb) expr await orchestrator.setVolume(for: "com.apple.Safari", volume: 0.5)
```

**Expected in helper logs:**
- "setVolume: com.apple.Safari -> 0.5"

### 7. Verify Round-Trip

Query volume back:
- Get Safari volume: triggers `getVolume(bundleID: "com.apple.Safari")`

**Expected:**
- Returns 0.5
- Helper logs show "getVolume: com.apple.Safari -> 0.5"

### 8. Verify Driver Cache

The driver connects to helper on load and periodically refreshes its local cache.

**Check Terminal 1 (driver logs) for:**
- "Connecting to helper: com.fbreidenbach.appfaders.helper"
- "XPC connection established"
- "Cache refreshed with N volumes" (N >= 1 after step 6)

The driver's `HelperBridge.getVolume(for:)` returns from local cache synchronously - this is verified by the driver functioning without blocking audio callbacks.

## Cleanup

```bash
./Scripts/uninstall-driver.sh
```

**Expected:**
- Driver removed
- coreaudiod restarted
- LaunchAgent unloaded
- Helper binary and plist removed

## Troubleshooting

### Helper not starting
```bash
# Check plist syntax
plutil -lint /Library/LaunchAgents/com.fbreidenbach.appfaders.helper.plist

# Manual load
sudo launchctl load /Library/LaunchAgents/com.fbreidenbach.appfaders.helper.plist

# Check for errors
sudo launchctl error system/com.fbreidenbach.appfaders.helper
```

### XPC connection fails
- Verify `AudioServerPlugIn_MachServices` in driver Info.plist
- Check helper binary exists at `/Library/Application Support/AppFaders/AppFadersHelper`
- Verify helper is executable: `ls -la "/Library/Application Support/AppFaders/"`

### Driver not connecting
- Restart coreaudiod: `sudo killall coreaudiod`
- Check Console.app for coreaudiod errors
- Filter by subsystem: `com.fbreidenbach.appfaders`

## Success Criteria

- [ ] Helper starts on-demand via launchd
- [ ] Host connects to helper via XPC
- [ ] Driver connects to helper via XPC
- [ ] setVolume from host stores in helper's VolumeStore
- [ ] getVolume from host retrieves from helper
- [ ] Driver's cache refresh fetches volumes from helper
- [ ] Driver's getVolume returns cached value (non-blocking)
- [ ] Uninstall cleanly removes all components
