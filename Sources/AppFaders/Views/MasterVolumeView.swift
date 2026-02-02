import SwiftUI

/// Master volume control section
struct MasterVolumeView: View {
  @Binding var volume: Float
  let isMuted: Bool
  let onMuteToggle: () -> Void

  private let secondaryText = AppColors.secondaryText

  var body: some View {
    VStack(spacing: 16) {
      // Header row: label + percentage
      HStack {
        Text("MASTER OUTPUT")
          .font(.system(size: 11, weight: .bold))
          .tracking(1.5)
          .foregroundStyle(secondaryText)

        Spacer()

        Text(isMuted ? "Muted" : "\(Int(volume * 100))%")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(isMuted ? AppColors.accent : secondaryText)
      }

      // Slider row: slider + mute button
      HStack(spacing: 12) {
        VolumeSlider(value: $volume, size: .large)

        MuteButton(isMuted: isMuted, onToggle: onMuteToggle)
      }
    }
    .padding(.vertical, 20)
  }
}

// MARK: - Previews

#Preview("Master - Light") {
  MasterVolumeView(volume: .constant(0.85), isMuted: false, onMuteToggle: {})
    .padding(.horizontal, 20)
    .background(AppColors.panelBackground)
    .preferredColorScheme(.light)
}

#Preview("Master - Dark") {
  MasterVolumeView(volume: .constant(0.85), isMuted: false, onMuteToggle: {})
    .padding(.horizontal, 20)
    .background(AppColors.panelBackground)
    .preferredColorScheme(.dark)
}

#Preview("Master Muted - Dark") {
  MasterVolumeView(volume: .constant(0.0), isMuted: true, onMuteToggle: {})
    .padding(.horizontal, 20)
    .background(AppColors.panelBackground)
    .preferredColorScheme(.dark)
}
