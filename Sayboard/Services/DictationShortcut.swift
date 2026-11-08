import AppIntents
import SwiftUI

@MainActor
final class DictationLaunchRequest: ObservableObject {
  static let shared = DictationLaunchRequest()
  @Published var pendingRequest: UUID?
}

struct DictateWithVoxBoard: AppIntent {
  static var title: LocalizedStringResource { "Dictate with VoxBoard" }
  static var description: IntentDescription {
    "Open VoxBoard and start an on-device recording. Stop in the app to transcribe and polish your message."
  }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

  @MainActor
  func perform() async throws -> some IntentResult {
    DictationLaunchRequest.shared.pendingRequest = UUID()
    return .result()
  }
}

struct VoxBoardShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: DictateWithVoxBoard(),
      phrases: ["Dictate with \(.applicationName)", "Record with \(.applicationName)"],
      shortTitle: "Dictate",
      systemImageName: "mic.fill",
    )
  }
}
