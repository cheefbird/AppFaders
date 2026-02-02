import SwiftUI

/// App color palette w/ light/dark mode. Gave up on asset catalog for now.
enum AppColors {
  // MARK: - Panel

  static var panelBackground: Color {
    Color(light: rgb(0xF5F5F5), dark: rgb(0x1E1E1E))
  }

  // MARK: - Text

  static var primaryText: Color {
    Color(light: rgb(0x1E1E1E), dark: rgb(0xFFFFFF))
  }

  static var secondaryText: Color {
    Color(light: rgb(0x666666), dark: rgb(0x888888))
  }

  static var tertiaryText: Color {
    Color(light: rgb(0x999999), dark: rgb(0x666666))
  }

  // MARK: - Controls

  static var sliderTrack: Color {
    Color(light: rgb(0xCCCCCC), dark: rgb(0x4A4A4A))
  }

  static var sliderThumb: Color {
    Color(light: rgb(0x1E1E1E), dark: rgb(0xFFFFFF))
  }

  static var divider: Color {
    Color(light: rgb(0xDDDDDD), dark: rgb(0x333333))
  }

  // MARK: - Accent

  static let accent = Color(rgb(0xE53935))

  // MARK: - Helpers

  private static func rgb(_ hex: UInt32) -> Color {
    Color(
      red: Double((hex >> 16) & 0xFF) / 255.0,
      green: Double((hex >> 8) & 0xFF) / 255.0,
      blue: Double(hex & 0xFF) / 255.0
    )
  }
}

// MARK: - Color Extension for Light/Dark

extension Color {
  init(light: Color, dark: Color) {
    self.init(nsColor: NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(dark)
        : NSColor(light)
    })
  }
}
