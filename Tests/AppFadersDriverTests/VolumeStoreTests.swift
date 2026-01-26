// VolumeStoreTests.swift
// unit tests for VolumeStore
//
// trying to keep it simple for now

@testable import AppFadersDriver
import Foundation
import Testing

@Suite("VolumeStore")
struct VolumeStoreTests {
  // Helper to generate unique bundle IDs to avoid state collision in shared singleton
  func makeBundleID(function: String = #function) -> String {
    "com.test.app.\(function)-\(UUID().uuidString)"
  }

  @Test("getVolume returns default 1.0 for unknown bundleID")
  func defaultVolume() {
    let store = VolumeStore.shared
    let bundleID = makeBundleID()

    #expect(store.getVolume(for: bundleID) == 1.0)
  }

  @Test("setVolume updates volume correctly")
  func setVolume() {
    let store = VolumeStore.shared
    let bundleID = makeBundleID()

    store.setVolume(for: bundleID, volume: 0.5)
    #expect(store.getVolume(for: bundleID) == 0.5)

    store.setVolume(for: bundleID, volume: 0.0)
    #expect(store.getVolume(for: bundleID) == 0.0)

    store.setVolume(for: bundleID, volume: 1.0)
    #expect(store.getVolume(for: bundleID) == 1.0)
  }

  @Test("setVolume clamps values to 0.0-1.0 range")
  func volumeClamping() {
    let store = VolumeStore.shared
    let bundleID = makeBundleID()

    store.setVolume(for: bundleID, volume: 1.5)
    #expect(store.getVolume(for: bundleID) == 1.0)

    store.setVolume(for: bundleID, volume: -0.5)
    #expect(store.getVolume(for: bundleID) == 0.0)
  }

  @Test("removeVolume resets to default")
  func removeVolume() {
    let store = VolumeStore.shared
    let bundleID = makeBundleID()

    store.setVolume(for: bundleID, volume: 0.3)
    #expect(store.getVolume(for: bundleID) == 0.3)

    store.removeVolume(for: bundleID)
    #expect(store.getVolume(for: bundleID) == 1.0)
  }

  @Test("concurrent access is thread-safe")
  func concurrentAccess() async {
    let store = VolumeStore.shared
    let bundleID = makeBundleID()
    let iterations = 1000

    // use dispatch queue concurrent perform to stress the lock
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
          if i % 2 == 0 {
            store.setVolume(for: bundleID, volume: Float(i) / Float(iterations))
          } else {
            _ = store.getVolume(for: bundleID)
          }
        }
        continuation.resume()
      }
    }

    // Verify it didn't crash and returns a valid value
    let finalVol = store.getVolume(for: bundleID)
    #expect(finalVol >= 0.0 && finalVol <= 1.0)
  }
}
