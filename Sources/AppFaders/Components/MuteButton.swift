import SwiftUI

/// Clickable speaker/muted icon toggle matching Pencil design (tLYj9, u847K)
struct MuteButton: View {
  let isMuted: Bool
  let onToggle: () -> Void

  private let speakerColor = AppColors.sliderThumb
  private let mutedColor = AppColors.accent

  var body: some View {
    Button(action: onToggle) {
      Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        .font(.system(size: 18))
        .foregroundStyle(isMuted ? mutedColor : speakerColor)
        .frame(width: 23, height: 18)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Previews

#Preview("Unmuted - Light") {
  MuteButton(isMuted: false, onToggle: {})
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Muted - Light") {
  MuteButton(isMuted: true, onToggle: {})
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Unmuted - Dark") {
  MuteButton(isMuted: false, onToggle: {})
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Muted - Dark") {
  MuteButton(isMuted: true, onToggle: {})
    .padding()
    .preferredColorScheme(.dark)
}
