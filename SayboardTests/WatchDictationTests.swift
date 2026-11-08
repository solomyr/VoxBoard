@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import Sayboard

@Suite("Apple Watch dictation", .serialized)
@MainActor
struct WatchDictationTests {
  /// Encodes samples as the Watch does: 16 kHz mono AAC in an .m4a file.
  private static func watchAudio(_ samples: [Float], sampleRate: Double) throws -> Data {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false))
    do {
      let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000,
      ], commonFormat: .pcmFormatFloat32, interleaved: false)
      let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
      buffer.frameLength = AVAudioFrameCount(samples.count)
      for (index, sample) in samples.enumerated() { buffer.floatChannelData![0][index] = sample }
      try file.write(from: buffer)
    }
    return try Data(contentsOf: url)
  }

  @Test
  func `watch recordings decode to 16 kHz mono samples`() throws {
    let tone = (0 ..< 32_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 16_000)) * 0.3 }
    let samples = try #require(WatchDictationService.samples(from: Self.watchAudio(tone, sampleRate: 16_000)))
    #expect(abs(samples.count - 32_000) < 2_000, "\(samples.count)")
    #expect((samples.map(abs).max() ?? 0) > 0.1)
  }

  @Test(.enabled(if: SharedSettings().hasUsableModel && FileManager.default.fileExists(atPath: Self.fixture.path)))
  func `a watch recording comes back transcribed and polished from the phone models`() async throws {
    let file = try AVAudioFile(forReading: Self.fixture)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    let reply = await WatchDictationService.shared.handle(audio: try Self.watchAudio(samples, sampleRate: file.processingFormat.sampleRate))
    print("VoxBoard Watch reply: \(reply)")
    let text = try #require(reply[WatchDictationProtocol.textKey], "\(reply)")
    #expect(text.lowercased().contains("meeting"))
  }

  private nonisolated static var fixture: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("voxboard-test-dictation.aiff")
  }
}
