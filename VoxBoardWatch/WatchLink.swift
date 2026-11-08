import Foundation
import WatchConnectivity

/// Sends a recording to VoxBoard on the iPhone and waits for the finished text.
/// Keep the keys in sync with Sayboard/Services/WatchDictationService.swift.
///
/// Small recordings go as an interactive message (fast); longer ones as a file
/// transfer, which has no size limit. The iPhone answers with a message, or with
/// a queued user-info transfer when the Watch app was not reachable, so a result
/// is never lost: it is also saved and shown when the app is opened again.
@MainActor
final class WatchLink: NSObject, WCSessionDelegate {
  static let shared = WatchLink()

  struct Reply: Sendable, Equatable {
    let text: String
    let original: String
  }

  enum LinkError: LocalizedError {
    case unreachable
    case phone(String)
    case timeout
    case transfer(String)

    var errorDescription: String? {
      switch self {
      case .unreachable: "Can't reach your iPhone. Keep it nearby with Bluetooth on."
      case .phone(let message): message
      case .timeout: "Your iPhone is taking too long. Open VoxBoard on the iPhone once, then try again."
      case .transfer(let message): "Sending to your iPhone failed: \(message)"
      }
    }
  }

  /// The last finished result, shown if the app was closed while waiting.
  var lastReply: Reply? {
    guard let text = UserDefaults.standard.string(forKey: "lastReply.text") else { return nil }
    return Reply(text: text, original: UserDefaults.standard.string(forKey: "lastReply.original") ?? text)
  }

  var onLateReply: ((Reply) -> Void)?

  func activate() {
    guard WCSession.isSupported(), WCSession.default.activationState != .activated else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func clearLastReply() {
    UserDefaults.standard.removeObject(forKey: "lastReply.text")
    UserDefaults.standard.removeObject(forKey: "lastReply.original")
  }

  func transcribe(_ audio: Data) async throws -> Reply {
    self.activate()
    for _ in 0 ..< 30 where WCSession.default.activationState != .activated {
      try await Task.sleep(for: .milliseconds(100))
    }
    let id = UUID().uuidString
    self.clearLastReply()
    return try await withCheckedThrowingContinuation { continuation in
      self.pending = (id, continuation)
      self.send(audio, id: id)
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(150))
        self.finish(id: id, with: .failure(LinkError.timeout))
      }
    }
  }

  // MARK: Private

  private var pending: (id: String, continuation: CheckedContinuation<Reply, any Error>)?

  private static let messageLimit = 50_000

  private func send(_ audio: Data, id: String) {
    let session = WCSession.default
    if audio.count <= Self.messageLimit, session.isReachable {
      session.sendMessage(["id": id, "audio": audio], replyHandler: { reply in
        Task { @MainActor in WatchLink.shared.handle(reply) }
      }, errorHandler: { error in
        // The phone may still answer through the queued path; only fail if nothing else can.
        Task { @MainActor in
          WatchLink.shared.sendAsFile(audio, id: id, after: error)
        }
      })
    } else {
      self.sendAsFile(audio, id: id, after: nil)
    }
  }

  private func sendAsFile(_ audio: Data, id: String, after _: (any Error)?) {
    guard self.pending?.id == id else { return }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).m4a")
    do {
      try audio.write(to: url)
    } catch {
      self.finish(id: id, with: .failure(LinkError.transfer(error.localizedDescription)))
      return
    }
    WCSession.default.transferFile(url, metadata: ["id": id])
  }

  private func handle(_ reply: [String: Any]) {
    guard let id = reply["id"] as? String else { return }
    if let error = reply["error"] as? String {
      self.finish(id: id, with: .failure(LinkError.phone(error)))
    } else if let text = reply["text"] as? String {
      let result = Reply(text: text, original: reply["original"] as? String ?? text)
      UserDefaults.standard.set(result.text, forKey: "lastReply.text")
      UserDefaults.standard.set(result.original, forKey: "lastReply.original")
      if self.pending?.id == id {
        self.finish(id: id, with: .success(result))
      } else {
        self.onLateReply?(result)
      }
    }
  }

  private func finish(id: String, with result: Result<Reply, any Error>) {
    guard let pending = self.pending, pending.id == id else { return }
    self.pending = nil
    pending.continuation.resume(with: result)
  }

  nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: (any Error)?) {}

  nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
    let box = MessageBox(message)
    Task { @MainActor in WatchLink.shared.handle(box.value) }
  }

  nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    let box = MessageBox(userInfo)
    Task { @MainActor in WatchLink.shared.handle(box.value) }
  }

  nonisolated func session(_: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
    try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    guard let error, let id = fileTransfer.file.metadata?["id"] as? String else { return }
    let message = error.localizedDescription
    Task { @MainActor in WatchLink.shared.finish(id: id, with: .failure(LinkError.transfer(message))) }
  }
}

private struct MessageBox: @unchecked Sendable {
  let value: [String: Any]
  init(_ value: [String: Any]) { self.value = value }
}
