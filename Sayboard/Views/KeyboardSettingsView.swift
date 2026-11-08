import SwiftUI

struct KeyboardSettingsView: View {

  @Binding var selectedKind: KeyboardKind

  var body: some View {
    Form {
      Section {
        Picker("Keyboard Type", selection: self.$selectedKind) {
          ForEach(KeyboardKind.allCases, id: \.self) { kind in
            Text(LocalizedStringKey(kind.displayNameKey)).tag(kind)
          }
        }
        Toggle("Haptic Feedback", isOn: self.$keyboardHapticsEnabled)
        if !self.needsInputModeSwitchKey {
          Toggle("Show Keyboard Switch Key", isOn: self.$showGlobeKey)
        }
      } footer: {
        if !self.needsInputModeSwitchKey {
          Text("Display an extra globe key on the keyboard. Your device already provides one, so this is optional.")
        }
      }
      Section {
        Picker("Typing language", selection: self.$keyboardLanguage) {
          ForEach(KeyboardLanguage.allCases) { language in
            Text(verbatim: language.name).tag(language.rawValue)
          }
        }
        NavigationLink("Try the keyboard") { KeyboardTypingPreview() }
          .accessibilityIdentifier("keyboard.preview.open")
      } footer: {
        Text("You can also switch languages directly above the keyboard. Hold a letter for accents. Slide across Space to move the cursor.")
      }
      Section {
        Toggle("“.” Shortcut", isOn: self.$periodShortcutEnabled)
      } footer: {
        Text("Double tapping the space bar will insert a period followed by a space.")
      }
    }
    .navigationTitle("Keyboard")
    .navigationBarTitleDisplayMode(.inline)
  }

  @AppStorage(SharedKey.showGlobeKey, store: UserDefaults(suiteName: AppGroup.identifier))
  private var showGlobeKey = true
  @AppStorage(SharedKey.keyboardHapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keyboardHapticsEnabled = true
  @AppStorage(SharedKey.needsInputModeSwitchKey, store: UserDefaults(suiteName: AppGroup.identifier))
  private var needsInputModeSwitchKey = true
  @AppStorage(SharedKey.periodShortcutEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var periodShortcutEnabled = true
  @AppStorage(SharedKey.keyboardLanguage, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keyboardLanguage = KeyboardLanguage.english.rawValue
}
