#if VOXBOARD_INTENT_PROBE
import AppIntents
import Foundation
import SwiftUI

@available(iOS 27.0, *)
struct KeyboardBackgroundProbeIntent: AudioRecordingIntent {
  static let title: LocalizedStringResource = "Check background execution"
  static var supportedModes: IntentModes { .background }
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  func perform() async throws -> some IntentResult {
    let result = Bundle.main.bundleIdentifier ?? "unknown"
    AppGroup.sharedDefaults?.set(result, forKey: "voxboard.intentProbe.result")
    AppGroup.sharedDefaults?.synchronize()
    return .result()
  }
}

@available(iOS 27.0, *)
struct KeyboardBackgroundProbeButton: View {
  @State private var result = "Check background"
  var body: some View {
    Button(intent: KeyboardBackgroundProbeIntent()) { Image(systemName: "bolt").frame(width: 32, height: 44) }
      .accessibilityLabel("Check background")
      .accessibilityValue(self.result)
      .accessibilityIdentifier("typing.backgroundProbe")
      .task {
        AppGroup.sharedDefaults?.removeObject(forKey: "voxboard.intentProbe.result")
        while !Task.isCancelled {
          AppGroup.sharedDefaults?.synchronize()
          if let value = AppGroup.sharedDefaults?.string(forKey: "voxboard.intentProbe.result") { self.result = value }
          try? await Task.sleep(for: .milliseconds(200))
        }
      }
  }
}
#endif
