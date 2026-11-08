import Foundation
import WatchConnectivity

/// Sends a recording to VoxBoard on the iPhone and waits for the finished text.
/// Keep the reply keys in sync with Sayboard/Services/WatchDictationService.swift.
@MainActor
final class WatchLink: NSObject, WCSessionDelegate {
  static let shared = WatchLink()

  struct Reply: Sendable {
    let text: String
    let original: String
  }

  enum LinkError: LocalizedError {
    case unreachable
    case phone(String)
    case unreadable

    var errorDescription: String? {
      switch self {
      case .unreachable: "Can't reach your iPhone. Keep it nearby with Bluetooth on."
      case .phone(let message): message
      case .unreadable: "Your iPhone sent an unexpected reply."
      }
    }
  }

  func activate() {
    guard WCSession.isSupported(), WCSession.default.activationState != .activated else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func transcribe(_ audio: Data) async throws -> Reply {
    self.activate()
    // Activation is quick but asynchronous; give it a moment on first use.
    for _ in 0 ..< 20 where WCSession.default.activationState != .activated {
      try await Task.sleep(for: .milliseconds(100))
    }
    guard WCSession.default.isReachable else { throw LinkError.unreachable }
    let data: Data = try await withCheckedThrowingContinuation { continuation in
      WCSession.default.sendMessageData(audio, replyHandler: { continuation.resume(returning: $0) },
                                        errorHandler: { continuation.resume(throwing: $0) })
    }
    guard let reply = try? JSONDecoder().decode([String: String].self, from: data) else { throw LinkError.unreadable }
    if let error = reply["error"] { throw LinkError.phone(error) }
    guard let text = reply["text"] else { throw LinkError.unreadable }
    return Reply(text: text, original: reply["original"] ?? text)
  }

  nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: (any Error)?) {}
}
