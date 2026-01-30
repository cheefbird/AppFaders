import SwiftUI

/// Placeholder panel view for task 5 - will be replaced by PanelView in later tasks
struct PlaceholderPanelView: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 16) {
      Text("AppFaders")
        .font(.system(size: 20, weight: .semibold))

      Text("Panel placeholder")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)

      Text("Click outside or press Esc to dismiss")
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
    }
    .frame(width: 380)
    .padding(20)
    .background(panelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 20))
  }

  private var panelBackground: Color {
    colorScheme == .dark ? Color(hex: 0x1E1E1E) : Color(hex: 0xF5F5F5)
  }
}

private extension Color {
  init(hex: UInt32) {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >> 8) & 0xFF) / 255.0
    let b = Double(hex & 0xFF) / 255.0
    self.init(red: r, green: g, blue: b)
  }
}
