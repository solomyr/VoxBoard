@preconcurrency import AVFoundation
import Foundation
import UIKit
import WatchConnectivity

/// Messages exchanged with the VoxBoard Watch app. Keep in sync with VoxBoardWatch/WatchLink.swift.
enum WatchDictationProtocol {
  /// Reply keys (JSON object).
  static let textKey = "text"
  static let originalKey = "original"
  static let errorKey = "error"
}

/// Receives recordings from the Watch, transcribes them with the selected
/// speech model, runs the AI writer when it is on, and replies with the text.
/// iOS wakes VoxBoard in the background for this, so it never needs the screen.
@MainActor
final class WatchDictationService: NSObject {
  static let shared = WatchDictationService()

  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  /// Transcribes and polishes a recording; returns the reply for the Watch.
  func handle(audio: Data) async -> [String: String] {
    let services = AppServices.shared
    services.wireIfNeeded()
    let speech = services.speechService
    guard !speech.isRecording, !speech.isStopping else {
      return [WatchDictationProtocol.errorKey: "VoxBoard is recording on your iPhone. Try again in a moment."]
    }
    guard let samples = Self.samples(from: audio), !samples.isEmpty else {
      return [WatchDictationProtocol.errorKey: "The recording could not be read."]
    }
    services.downloadService.verifyExistingModels()
    guard services.downloadService.hasUsableModel else {
      return [WatchDictationProtocol.errorKey: "Download a speech model in VoxBoard on your iPhone first."]
    }
    if speech.activeLoadState != .loaded {
      await speech.loadModelIfAvailable(downloadService: services.downloadService)
    }
    guard let original = await speech.transcribeForWatch(samples: samples), !original.isEmpty else {
      return [WatchDictationProtocol.errorKey: "No speech was recognized. Try again a little closer."]
    }
    var text = original
    let settings = SharedSettings()
    services.llmDownloadService.verifyExistingModels()
    // In the background iOS allows only about 30 seconds; skip polishing rather than lose the text.
    let app = UIApplication.shared
    let hasTime = app.applicationState != .background || app.backgroundTimeRemaining > 18
    if hasTime, settings.llmEnabled, settings.defaultLLMActionSelection.isSet, services.llmDownloadService.hasUsableModel,
       let polished = await services.llmCoordinator.polish(original) {
      text = polished
    }
    return [WatchDictationProtocol.textKey: text, WatchDictationProtocol.originalKey: original]
  }

  /// Decodes any audio file iOS can read to 16 kHz mono samples.
  nonisolated static func samples(from data: Data) -> [Float]? {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString).m4a")
    defer { try? FileManager.default.removeItem(at: url) }
    guard (try? data.write(to: url)) != nil, let file = try? AVAudioFile(forReading: url) else { return nil }
    guard
      let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
      let converter = AVAudioConverter(from: file.processingFormat, to: target),
      let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
      (try? file.read(into: input)) != nil
    else { return nil }
    let ratio = 16_000 / file.processingFormat.sampleRate
    let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1_024
    guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
    var consumed = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if consumed {
        status.pointee = .endOfStream
        return nil
      }
      consumed = true
      status.pointee = .haveData
      return input
    }
    guard error == nil, let channel = output.floatChannelData?[0] else { return nil }
    return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
  }
}

extension WatchDictationService: WCSessionDelegate {
  nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: (any Error)?) {}
  nonisolated func sessionDidBecomeInactive(_: WCSession) {}
  nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

  /// Short recordings: an interactive message, answered directly.
  nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    let id = message["id"] as? String ?? ""
    let audio = message["audio"] as? Data ?? Data()
    let reply = UncheckedReply(send: replyHandler)
    Task { @MainActor in
      reply.send(await WatchDictationService.shared.process(audio: audio, id: id))
    }
  }

  /// Longer recordings: a file transfer, answered with a message or a queued transfer.
  nonisolated func session(_: WCSession, didReceive file: WCSessionFile) {
    let id = file.metadata?["id"] as? String ?? ""
    let audio = (try? Data(contentsOf: file.fileURL)) ?? Data()
    Task { @MainActor in
      let result = await WatchDictationService.shared.process(audio: audio, id: id)
      let session = WCSession.default
      if session.isReachable {
        session.sendMessage(result, replyHandler: nil) { _ in session.transferUserInfo(result) }
      } else {
        session.transferUserInfo(result)
      }
    }
  }
}

extension WatchDictationService {
  /// Runs a request with background time and tags the reply with its id.
  func process(audio: Data, id: String) async -> [String: Any] {
    let task = UIApplication.shared.beginBackgroundTask(withName: "Watch dictation")
    defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task) } }
    var result: [String: Any] = await self.handle(audio: audio)
    result["id"] = id
    return result
  }
}

private struct UncheckedReply: @unchecked Sendable {
  let send: ([String: Any]) -> Void
}
