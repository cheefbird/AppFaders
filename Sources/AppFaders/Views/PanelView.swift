import SwiftUI

/// Root panel
struct PanelView: View {
  @Bindable var state: AppState

  private let panelBackground = Color("PanelBackground", bundle: .module)
  private let dividerColor = Color("Divider", bundle: .module)

  var body: some View {
    VStack(spacing: 0) {
      HeaderView()

      Rectangle()
        .fill(dividerColor)
        .frame(height: 1)

      MasterVolumeView(
        volume: $state.masterVolume,
        isMuted: state.masterMuted,
        onMuteToggle: { state.toggleMasterMute() }
      )

      ForEach(state.apps) { app in
        AppRowView(
          app: app,
          volume: volumeBinding(for: app.id),
          onMuteToggle: { Task { await state.toggleMute(for: app.id) } }
        )
      }

      Rectangle()
        .fill(dividerColor)
        .frame(height: 1)

      FooterView(onQuit: { state.quit() })
    }
    .padding(20)
    .frame(width: 380)
    .background(panelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 20))
  }

  private func volumeBinding(for bundleID: String) -> Binding<Float> {
    Binding(
      get: { state.apps.first { $0.id == bundleID }?.volume ?? 0 },
      set: { newValue in Task { await state.setVolume(for: bundleID, volume: newValue) } }
    )
  }
}

// MARK: - Previews

#Preview("Panel - Dark") {
  let orchestrator = AudioOrchestrator()
  let deviceManager = DeviceManager()
  let state = AppState(orchestrator: orchestrator, deviceManager: deviceManager)
  return PanelView(state: state)
    .preferredColorScheme(.dark)
}

#Preview("Panel - Light") {
  let orchestrator = AudioOrchestrator()
  let deviceManager = DeviceManager()
  let state = AppState(orchestrator: orchestrator, deviceManager: deviceManager)
  return PanelView(state: state)
    .preferredColorScheme(.light)
}
