import SwiftUI

/// A button that responds the moment a finger lands. Inside a keyboard extension,
/// iOS holds back touches near the top edge, so standard `Button`s there often
/// miss taps; a zero-distance drag is delivered immediately (like the mic button).
struct TouchButton<Label: View>: View {
  init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
    self.action = action
    self.label = label()
  }

  var body: some View {
    self.label
      .foregroundStyle(.tint)
      .opacity(self.isPressed ? 0.45 : (self.isEnabled ? 1 : 0.35))
      // Inside a keyboard, fully transparent pixels receive no touches at all,
      // so give the whole button area an invisible but drawn background.
      .background(Color.black.opacity(0.001))
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in if self.isEnabled, !self.isPressed { self.isPressed = true } }
          .onEnded { value in
            self.isPressed = false
            // A finger that slid well away cancels, like a normal button.
            guard self.isEnabled, hypot(value.translation.width, value.translation.height) < 40 else { return }
            self.action()
          }
      )
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { if self.isEnabled { self.action() } }
  }

  private let action: () -> Void
  private let label: Label
  @State private var isPressed = false
  @Environment(\.isEnabled) private var isEnabled
}
