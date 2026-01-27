// DriverBridgeTests.swift
// Unit tests for DriverBridge validation logic
//
// Tests validation before XPC calls - helper doesn't need to be running

@testable import AppFaders
import Foundation
import Testing

@Suite("DriverBridge")
struct DriverBridgeTests {
  // MARK: - Validation Tests

  @Test("setAppVolume throws invalidVolumeRange for negative values")
  func validateNegativeVolume() async {
    let bridge = DriverBridge()

    await #expect(throws: DriverError.invalidVolumeRange(-0.1)) {
      try await bridge.setAppVolume(bundleID: "com.test.app", volume: -0.1)
    }
  }

  @Test("setAppVolume throws invalidVolumeRange for values > 1.0")
  func validateExcessiveVolume() async {
    let bridge = DriverBridge()

    await #expect(throws: DriverError.invalidVolumeRange(1.1)) {
      try await bridge.setAppVolume(bundleID: "com.test.app", volume: 1.1)
    }
  }

  @Test("setAppVolume accepts valid volume range (0.0 - 1.0)")
  func validateValidVolume() async {
    let bridge = DriverBridge()

    // Valid volumes should pass validation and fail at XPC (helper not running)
    // We check that invalidVolumeRange is NOT thrown
    func check(_ volume: Float) async {
      do {
        try await bridge.setAppVolume(bundleID: "com.test.app", volume: volume)
      } catch let error as DriverError {
        if case .invalidVolumeRange = error {
          Issue.record("Should not throw invalidVolumeRange for \(volume)")
        }
        // Other errors (helperNotRunning) are expected
      } catch {
        // Other errors are expected
      }
    }

    await check(0.0)
    await check(0.5)
    await check(1.0)
  }

  @Test("setAppVolume throws bundleIDTooLong for huge bundle IDs")
  func validateBundleIDLength() async {
    let bridge = DriverBridge()

    let hugeID = String(repeating: "a", count: 256)

    await #expect(throws: DriverError.bundleIDTooLong(256)) {
      try await bridge.setAppVolume(bundleID: hugeID, volume: 0.5)
    }
  }

  @Test("setAppVolume accepts max length bundle IDs (255 bytes)")
  func validateMaxBundleIDLength() async {
    let bridge = DriverBridge()

    // 255 'a' characters = 255 bytes
    let maxID = String(repeating: "a", count: 255)

    do {
      try await bridge.setAppVolume(bundleID: maxID, volume: 0.5)
    } catch let error as DriverError {
      if case .bundleIDTooLong = error {
        Issue.record("Should accept 255-byte bundle ID")
      }
      // Other errors (helperNotRunning) are expected
    } catch {
      // Other errors are expected
    }
  }

  @Test("setAppVolume correctly handles multi-byte UTF-8 length")
  func validateMultiByteBundleID() async {
    let bridge = DriverBridge()

    // 🚀 is 4 bytes. 256 / 4 = 64 rockets = 256 bytes (too long)
    let hugeEmojiID = String(repeating: "🚀", count: 64)

    await #expect(throws: DriverError.bundleIDTooLong(256)) {
      try await bridge.setAppVolume(bundleID: hugeEmojiID, volume: 0.5)
    }

    // 63 rockets = 252 bytes (valid)
    let validEmojiID = String(repeating: "🚀", count: 63)
    do {
      try await bridge.setAppVolume(bundleID: validEmojiID, volume: 0.5)
    } catch let error as DriverError {
      if case .bundleIDTooLong = error {
        Issue.record("Should accept 252-byte bundle ID")
      }
    } catch {
      // Other errors are expected
    }
  }

  @Test("getAppVolume throws bundleIDTooLong for huge bundle IDs")
  func validateGetVolumeBundleIDLength() async {
    let bridge = DriverBridge()

    let hugeID = String(repeating: "a", count: 256)

    await #expect(throws: DriverError.bundleIDTooLong(256)) {
      _ = try await bridge.getAppVolume(bundleID: hugeID)
    }
  }

  // MARK: - Connection State Tests

  @Test("Methods throw helperNotRunning when disconnected")
  func helperNotRunning() async {
    let bridge = DriverBridge()
    // Ensure disconnected
    bridge.disconnect()

    await #expect(throws: DriverError.helperNotRunning) {
      try await bridge.setAppVolume(bundleID: "com.test.app", volume: 0.5)
    }

    await #expect(throws: DriverError.helperNotRunning) {
      _ = try await bridge.getAppVolume(bundleID: "com.test.app")
    }
  }

  @Test("Connection state is managed correctly")
  func connectionState() async {
    let bridge = DriverBridge()
    #expect(!bridge.isConnected)

    // connect() will succeed (creates connection object) even without helper
    try? await bridge.connect()
    #expect(bridge.isConnected)

    bridge.disconnect()
    #expect(!bridge.isConnected)
  }
}
