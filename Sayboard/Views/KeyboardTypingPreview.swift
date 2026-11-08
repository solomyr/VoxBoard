import SwiftUI

struct KeyboardTypingPreview: View {
  @StateObject private var keyboard = TypingKeyboardModel(language: SharedSettings().keyboardLanguage)
  @State private var text = ""
  @State private var cursor = 0
  @State private var usesInstalledKeyboard = false
  @State private var systemText = ""
  @FocusState private var systemEditorFocused: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Try the keys below. Use the language menu to switch layouts.")
        Toggle("Use installed iOS keyboard", isOn: self.$usesInstalledKeyboard)
          .accessibilityIdentifier("keyboard.preview.installed")
        if self.usesInstalledKeyboard {
          TextEditor(text: self.$systemText)
            .frame(minHeight: 140)
            .focused(self.$systemEditorFocused)
            .accessibilityLabel("Keyboard test text")
            .accessibilityIdentifier("keyboard.preview.systemText")
        } else {
        (Text(String(self.text.prefix(self.cursor))) + Text("│").foregroundColor(.accentColor)
          + Text(String(self.text.dropFirst(self.cursor))))
          .font(.title3)
          .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
          .padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
          .accessibilityLabel(self.text)
          .accessibilityIdentifier("keyboard.preview.text")
        }
        Text("The globe key switches to other installed iOS keyboards. The language menu switches VoxBoard’s own keys.")
          .font(.footnote).foregroundStyle(.secondary)
        Text("Tap the keyboard mic to dictate, then tap again to stop, or hold it while you speak. The first time, VoxBoard briefly opens to turn the microphone on. After that you record right in the keyboard until the mic times out or you turn it off. For one-handed typing, open the language menu.")
          .font(.footnote).foregroundStyle(.secondary)
        Button("Clear preview") { self.text = ""; self.systemText = ""; self.cursor = 0; self.syncCapitalization() }
          .accessibilityIdentifier("keyboard.preview.clear")
      }.padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Try the keyboard")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .onChange(of: self.usesInstalledKeyboard) { _, enabled in self.systemEditorFocused = enabled }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if !self.usesInstalledKeyboard {
      TypingKeyboardView(
        model: self.keyboard,
        onInsert: self.insert,
        onSpace: { self.insert(" ") },
        onDelete: self.delete,
        onMoveCursor: { self.cursor = min(max(0, self.cursor + $0), self.text.count); self.syncCapitalization() },
        onLanguageChange: { SharedSettings().keyboardLanguage = $0 },
        toolbar: {
          Spacer()
          Text("Keyboard preview").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Image(systemName: "mic.fill").foregroundStyle(.secondary).frame(width: 42, height: 42)
            .accessibilityLabel("Microphone preview")
        },
        globe: { Image(systemName: "globe").foregroundStyle(.secondary).accessibilityLabel("System keyboard switch preview") },
      )
      .background(Color(.systemGray5))
      }
    }
  }

  private func insert(_ value: String) {
    self.text.insert(contentsOf: value, at: self.text.index(self.text.startIndex, offsetBy: self.cursor))
    self.cursor += value.count
    self.syncCapitalization()
  }

  private func delete() {
    guard self.cursor > 0 else { return }
    self.cursor -= 1
    self.text.remove(at: self.text.index(self.text.startIndex, offsetBy: self.cursor))
    self.syncCapitalization()
  }

  private func syncCapitalization() {
    self.keyboard.updateContext(before: String(self.text.prefix(self.cursor)), capitalization: .sentences)
  }
}
