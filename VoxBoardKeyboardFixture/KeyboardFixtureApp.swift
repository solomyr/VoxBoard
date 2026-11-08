import SwiftUI

/// A separate process for verifying the real keyboard handoff without touching
/// the owner's messages, drafts, or another app's personal data. Not shipped.
@main
struct KeyboardFixtureApp: App {
  var body: some Scene {
    WindowGroup { FixtureView() }
  }
}

private struct FixtureView: View {
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("VoxBoard test field").font(.title.bold())
      Text("Temporary text for keyboard testing. Nothing is sent or saved.")
      TextEditor(text: self.$text)
        .focused(self.$focused)
        .accessibilityIdentifier("fixture.text")
      Button("Clear test text") { self.text = "" }
    }
    .padding()
    .task { self.focused = true }
  }
}
