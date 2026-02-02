import SwiftUI

/// Panel header with title and settings icon matching Pencil design (7tlKE)
struct HeaderView: View {
  private let primaryText = AppColors.primaryText
  private let secondaryText = AppColors.secondaryText

  var body: some View {
    HStack {
      Text("AppFaders")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(primaryText)

      Spacer()

      Image(systemName: "gear")
        .font(.system(size: 18))
        .foregroundStyle(secondaryText)
    }
    .frame(height: 40)
  }
}

// MARK: - Previews

#Preview("Header - Light") {
  HeaderView()
    .padding()
    .background(AppColors.panelBackground)
    .preferredColorScheme(.light)
}

#Preview("Header - Dark") {
  HeaderView()
    .padding()
    .background(AppColors.panelBackground)
    .preferredColorScheme(.dark)
}
