// DriverBridgeTests.swift
// Unit tests for DriverBridge validation logic
//
// bit of nasty code never hurt a

@testable import AppFaders
import CoreAudio
import Foundation
import Testing

@Suite("DriverBridge")
struct DriverBridgeTests {
  // MARK: - Validation Tests

  @Test("setAppVolume throws invalidVolumeRange for negative values")
  func validateNegativeVolume() {
    let bridge = DriverBridge()
    try? bridge.connect(deviceID: 123)

    #expect(throws: DriverError.invalidVolumeRange(-0.1)) {
      try bridge.setAppVolume(bundleID: "com.test.app", volume: -0.1)
    }
  }

  @Test("setAppVolume throws invalidVolumeRange for values > 1.0")
  func validateExcessiveVolume() {
    let bridge = DriverBridge()
    try? bridge.connect(deviceID: 123)

    #expect(throws: DriverError.invalidVolumeRange(1.1)) {
      try bridge.setAppVolume(bundleID: "com.test.app", volume: 1.1)
    }
  }

  @Test("setAppVolume accepts valid volume range (0.0 - 1.0)")
  func validateValidVolume() {
    let bridge = DriverBridge()
    try? bridge.connect(deviceID: 123)

    // Helper to check validation
    func check(_ volume: Float) {
      do {
        try bridge.setAppVolume(bundleID: "com.test.app", volume: volume)
      } catch let error as DriverError {
        // We expect it to PASS validation and fail at the CoreAudio call
        if case .invalidVolumeRange = error {
          Issue.record("Should not throw invalidVolumeRange for \(volume)")
        }
      } catch {
        // Other errors are expected
      }
    }

    check(0.0)
    check(0.5)
    check(1.0)
  }

  @Test("setAppVolume throws bundleIDTooLong for huge bundle IDs")
  func validateBundleIDLength() {
    let bridge = DriverBridge()
    try? bridge.connect(deviceID: 123)

    let hugeID = String(repeating: "a", count: 256)

    #expect(throws: DriverError.bundleIDTooLong(256)) {
      try bridge.setAppVolume(bundleID: hugeID, volume: 0.5)
    }
  }

  @Test("setAppVolume accepts max length bundle IDs (255 bytes)")
  func validateMaxBundleIDLength() {
    let bridge = DriverBridge()
    try? bridge.connect(deviceID: 123)

    // 255 'a' characters = 255 bytes
    let maxID = String(repeating: "a", count: 255)

    do {
      try bridge.setAppVolume(bundleID: maxID, volume: 0.5)
    } catch let error as DriverError {
      if case .bundleIDTooLong = error {
        Issue.record("Should accept 255-byte bundle ID")
      }
    } catch {
      // Ignore write failure
    }
  }

  @Test("setAppVolume correctly handles multi-byte UTF-8 length")
  func validateMultiByteBundleID() {
    let bridge = DriverBridge()
    try? bridge.connect(deviceID: 123)

    // 🚀 is 4 bytes. 256 / 4 = 64 rockets = 256 bytes (too long)
    let hugeEmojiID = String(repeating: "🚀", count: 64)

    #expect(throws: DriverError.bundleIDTooLong(256)) {
      try bridge.setAppVolume(bundleID: hugeEmojiID, volume: 0.5)
    }

    // 63 rockets = 252 bytes (valid)
    let validEmojiID = String(repeating: "🚀", count: 63)
    do {
      try bridge.setAppVolume(bundleID: validEmojiID, volume: 0.5)
    } catch let error as DriverError {
      if case .bundleIDTooLong = error {
        Issue.record("Should accept 252-byte bundle ID")
      }
    } catch {
      // Ignore write failure
    }
  }

  @Test("getAppVolume throws bundleIDTooLong for huge bundle IDs")
  func validateGetVolumeBundleIDLength() {
    let bridge = DriverBridge()
    try? bridge.connect(deviceID: 123)

    let hugeID = String(repeating: "a", count: 256)

    #expect(throws: DriverError.bundleIDTooLong(256)) {
      _ = try bridge.getAppVolume(bundleID: hugeID)
    }
  }

  // MARK: - Connection State Tests

  @Test("Methods throw deviceNotFound when disconnected")
  func deviceNotFound() {
    let bridge = DriverBridge()
    // Ensure disconnected
    bridge.disconnect()

    #expect(throws: DriverError.deviceNotFound) {
      try bridge.setAppVolume(bundleID: "com.test.app", volume: 0.5)
    }

    #expect(throws: DriverError.deviceNotFound) {
      _ = try bridge.getAppVolume(bundleID: "com.test.app")
    }
  }

  @Test("Connection state is managed correctly")
  func connectionState() {
    let bridge = DriverBridge()
    #expect(!bridge.isConnected)

    try? bridge.connect(deviceID: 123)
    #expect(bridge.isConnected)

    bridge.disconnect()
    #expect(!bridge.isConnected)
  }
}
