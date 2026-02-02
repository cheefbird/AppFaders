@testable import AppFaders
import AppKit
import Testing

@Suite("AppVolumeState")
struct AppVolumeStateTests {
  @Test("displayPercentage shows percentage when not muted")
  func displayPercentageNormal() {
    let state = AppVolumeState(
      id: "com.test.app",
      name: "Test App",
      icon: nil,
      volume: 0.75,
      isMuted: false,
      previousVolume: 0.75
    )

    #expect(state.displayPercentage == "75%")
  }

  @Test("displayPercentage shows 'Muted' when muted")
  func displayPercentageMuted() {
    let state = AppVolumeState(
      id: "com.test.app",
      name: "Test App",
      icon: nil,
      volume: 0.0,
      isMuted: true,
      previousVolume: 0.75
    )

    #expect(state.displayPercentage == "Muted")
  }

  @Test("displayPercentage rounds to integer")
  func displayPercentageRounding() {
    let state = AppVolumeState(
      id: "com.test.app",
      name: "Test App",
      icon: nil,
      volume: 0.333,
      isMuted: false,
      previousVolume: 0.333
    )

    #expect(state.displayPercentage == "33%")
  }

  @Test("volume at 0% shows 0%")
  func displayPercentageZero() {
    let state = AppVolumeState(
      id: "com.test.app",
      name: "Test App",
      icon: nil,
      volume: 0.0,
      isMuted: false,
      previousVolume: 0.5
    )

    #expect(state.displayPercentage == "0%")
  }

  @Test("volume at 100% shows 100%")
  func displayPercentageFull() {
    let state = AppVolumeState(
      id: "com.test.app",
      name: "Test App",
      icon: nil,
      volume: 1.0,
      isMuted: false,
      previousVolume: 1.0
    )

    #expect(state.displayPercentage == "100%")
  }

  @Test("id matches bundleID")
  func identifiable() {
    let state = AppVolumeState(
      id: "com.test.app",
      name: "Test App",
      icon: nil,
      volume: 0.5,
      isMuted: false,
      previousVolume: 0.5
    )

    #expect(state.id == "com.test.app")
  }
}
