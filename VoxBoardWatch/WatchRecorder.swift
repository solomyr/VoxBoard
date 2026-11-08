@preconcurrency import AVFoundation
import Foundation

/// Records speech on the Watch as small AAC audio for the iPhone to transcribe.
@MainActor
final class WatchRecorder {
  func start() async throws {
    let granted = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
    }
    guard granted else { throw RecorderError.denied }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .default)
    try session.setActive(true)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("voxboard-watch.m4a")
    try? FileManager.default.removeItem(at: url)
    let recorder = try AVAudioRecorder(url: url, settings: [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 32_000,
    ])
    guard recorder.record(forDuration: 120) else { throw RecorderError.failed }
    self.recorder = recorder
  }

  /// Stops recording, releases the microphone, and returns the audio.
  func stop() -> Data? {
    guard let recorder = self.recorder else { return nil }
    recorder.stop()
    self.recorder = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    let data = try? Data(contentsOf: recorder.url)
    try? FileManager.default.removeItem(at: recorder.url)
    return data
  }

  var isRecording: Bool { self.recorder?.isRecording == true }

  enum RecorderError: LocalizedError {
    case denied, failed
    var errorDescription: String? {
      switch self {
      case .denied: "Allow microphone access for VoxBoard in the Watch app's settings on your iPhone."
      case .failed: "Recording could not start."
      }
    }
  }

  private var recorder: AVAudioRecorder?
}
