import SwiftUI

/// Panel footer with version and quit button matching Pencil design (SCxSk)
struct FooterView: View {
  let onQuit: () -> Void

  private let tertiaryText = Color("TertiaryText", bundle: .module)
  private let accentColor = Color("Accent", bundle: .module)

  var body: some View {
    HStack {
      Text("V1.0.0 ALPHA")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(tertiaryText)

      Spacer()

      Button(action: onQuit) {
        Text("Quit")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(accentColor)
      }
      .buttonStyle(.plain)
    }
    .frame(height: 40)
  }
}

// MARK: - Previews

#Preview("Footer - Light") {
  FooterView(onQuit: {})
    .padding()
    .background(Color("PanelBackground", bundle: .module))
    .preferredColorScheme(.light)
}

#Preview("Footer - Dark") {
  FooterView(onQuit: {})
    .padding()
    .background(Color("PanelBackground", bundle: .module))
    .preferredColorScheme(.dark)
}
