import SwiftUI

/// Slider size variants per Row
enum SliderSize {
  case large // Master volume
  case small // App rows

  /// Track width in points
  var trackWidth: CGFloat {
    switch self {
    case .large: 300
    case .small: 200
    }
  }

  /// Track height in points
  var trackHeight: CGFloat {
    4
  }

  /// Thumb circle diameter in points
  var thumbDiameter: CGFloat {
    switch self {
    case .large: 20
    case .small: 16
    }
  }

  /// Total frame height (includes vertical padding)
  var frameHeight: CGFloat {
    switch self {
    case .large: 24
    case .small: 16
    }
  }
}

/// Custom volume slider matching Pencil design specs
struct VolumeSlider: View {
  @Binding var value: Float
  var size: SliderSize = .large

  private let trackColor = Color("SliderTrack", bundle: .module)
  private let thumbColor = Color("SliderThumb", bundle: .module)

  var body: some View {
    GeometryReader { geometry in
      let trackWidth = min(geometry.size.width, size.trackWidth)
      let thumbRadius = size.thumbDiameter / 2
      let usableWidth = trackWidth - size.thumbDiameter
      let thumbX = thumbRadius + CGFloat(value) * usableWidth

      ZStack(alignment: .leading) {
        // Track
        RoundedRectangle(cornerRadius: 2)
          .fill(trackColor)
          .frame(width: trackWidth, height: size.trackHeight)

        // Thumb
        Circle()
          .fill(thumbColor)
          .frame(width: size.thumbDiameter, height: size.thumbDiameter)
          .offset(x: thumbX - thumbRadius)
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { gesture in
                let newValue = (gesture.location.x - thumbRadius) / usableWidth
                value = Float(max(0, min(1, newValue)))
              }
          )
      }
      .frame(width: trackWidth, height: size.frameHeight)
    }
    .frame(width: size.trackWidth, height: size.frameHeight)
  }
}

// MARK: - Previews

#Preview("Large Slider - Light") {
  VolumeSlider(value: .constant(0.7), size: .large)
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Large Slider - Dark") {
  VolumeSlider(value: .constant(0.7), size: .large)
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Small Slider - Dark") {
  VolumeSlider(value: .constant(0.5), size: .small)
    .padding()
    .preferredColorScheme(.dark)
}
