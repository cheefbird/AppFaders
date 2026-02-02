import AppKit
import SwiftUI

/// Per-application volume control row matching Pencil design (SZAXz, MBi9g)
struct AppRowView: View {
  let app: AppVolumeState
  @Binding var volume: Float
  let onMuteToggle: () -> Void

  private let primaryText = AppColors.primaryText
  private let secondaryText = AppColors.secondaryText
  private let accentColor = AppColors.accent

  var body: some View {
    HStack(spacing: 16) {
      // App icon
      appIcon
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12))

      // Content: name row + slider
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(app.name)
            .font(.system(size: 16))
            .foregroundStyle(primaryText)
            .lineLimit(1)

          Spacer()

          Text(app.isMuted ? "Muted" : "\(Int(app.volume * 100))%")
            .font(.system(size: 14))
            .foregroundStyle(app.isMuted ? accentColor : secondaryText)
        }

        VolumeSlider(value: $volume, size: .small)
      }

      // Mute button
      MuteButton(isMuted: app.isMuted, onToggle: onMuteToggle)
    }
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private var appIcon: some View {
    if let nsImage = app.icon {
      Image(nsImage: nsImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
    } else {
      Image(systemName: "app.fill")
        .font(.system(size: 32))
        .foregroundStyle(secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.divider)
    }
  }
}

// MARK: - Previews

#Preview("App Row - Dark") {
  AppRowView(
    app: AppVolumeState(
      id: "com.apple.music",
      name: "Music",
      icon: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil),
      volume: 0.75,
      isMuted: false,
      previousVolume: 0.75
    ),
    volume: .constant(0.75),
    onMuteToggle: {}
  )
  .padding(.horizontal, 20)
  .background(AppColors.panelBackground)
  .preferredColorScheme(.dark)
}

#Preview("App Row Muted - Dark") {
  AppRowView(
    app: AppVolumeState(
      id: "com.apple.music",
      name: "Music",
      icon: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil),
      volume: 0.0,
      isMuted: true,
      previousVolume: 0.75
    ),
    volume: .constant(0.0),
    onMuteToggle: {}
  )
  .padding(.horizontal, 20)
  .background(AppColors.panelBackground)
  .preferredColorScheme(.dark)
}

#Preview("App Row No Icon - Light") {
  AppRowView(
    app: AppVolumeState(
      id: "com.unknown.app",
      name: "Unknown App",
      icon: nil,
      volume: 0.5,
      isMuted: false,
      previousVolume: 0.5
    ),
    volume: .constant(0.5),
    onMuteToggle: {}
  )
  .padding(.horizontal, 20)
  .background(AppColors.panelBackground)
  .preferredColorScheme(.light)
}
