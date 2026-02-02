import SwiftUI

/// Panel header with title and settings icon matching Pencil design (7tlKE)
struct HeaderView: View {
  private let primaryText = Color("PrimaryText", bundle: .module)
  private let secondaryText = Color("SecondaryText", bundle: .module)

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
    .background(Color("PanelBackground", bundle: .module))
    .preferredColorScheme(.light)
}

#Preview("Header - Dark") {
  HeaderView()
    .padding()
    .background(Color("PanelBackground", bundle: .module))
    .preferredColorScheme(.dark)
}
