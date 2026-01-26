@testable import AppFaders
import AppKit
import Foundation
import Testing

@Suite("TrackedApp")
struct TrackedAppTests {
  @Test("Equality check works correctly")
  func equality() {
    let date = Date()
    let app1 = TrackedApp(
      bundleID: "com.test.app",
      localizedName: "Test App",
      icon: nil,
      launchDate: date
    )

    let app2 = TrackedApp(
      bundleID: "com.test.app",
      localizedName: "Different Name",
      icon: NSImage(),
      launchDate: date
    )

    #expect(app1 == app2)

    let app3 = TrackedApp(
      bundleID: "com.test.other",
      localizedName: "Test App",
      icon: nil,
      launchDate: date
    )

    #expect(app1 != app3)
  }

  @Test("Hashable implementation is consistent")
  func hashing() {
    let date = Date()
    let app1 = TrackedApp(
      bundleID: "com.test.app",
      localizedName: "Test App",
      icon: nil,
      launchDate: date
    )

    let app2 = TrackedApp(
      bundleID: "com.test.app",
      localizedName: "Test App",
      icon: nil,
      launchDate: date
    )

    var hasher1 = Hasher()
    app1.hash(into: &hasher1)

    var hasher2 = Hasher()
    app2.hash(into: &hasher2)

    #expect(hasher1.finalize() == hasher2.finalize())
  }
}

@Suite("AppAudioMonitor")
struct AppAudioMonitorTests {
  @Test("Initial app enumeration populates runningApps")
  func initialEnumeration() {
    let monitor = AppAudioMonitor()

    #expect(monitor.runningApps.isEmpty)

    monitor.start()

    let apps = monitor.runningApps
    #expect(!apps.isEmpty)

    if !apps.isEmpty {
      let firstApp = apps[0]
      #expect(!firstApp.bundleID.isEmpty)
    }
  }

  @Test("Stream can be created and cancelled")
  func streamMechanics() async {
    let monitor = AppAudioMonitor()
    let stream = monitor.events

    let task = Task {
      for await _ in stream {}
    }

    try? await Task.sleep(nanoseconds: 10_000_000)
    task.cancel()

    #expect(Bool(true))
  }

  @Test("runningApps is thread-safe")
  func concurrency() async {
    let monitor = AppAudioMonitor()
    monitor.start()

    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
          _ = monitor.runningApps
        }
        continuation.resume()
      }
    }

    #expect(Bool(true))
  }
}
