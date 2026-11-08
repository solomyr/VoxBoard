import AVFoundation
import Testing
@testable import Sayboard

@Suite("Microphone lifecycle", .serialized,
       .enabled(if: AVAudioApplication.shared.recordPermission == .granted,
                "Requires previously granted microphone permission"))
@MainActor
struct MicrophoneSessionTests {
  @Test
  func `microphone is off initially and after on demand capture ends`() throws {
    let session = BackgroundAudioSession()
    defer { session.endSession() }
    #expect(!session.isSessionActive)
    #expect(!session.audioEngine.isRunning)
    // Never present a permission prompt from the test runner.
    try #require(AVAudioApplication.shared.recordPermission == .granted,
                 "Grant microphone access before running audio hardware checks.")
    try session.startSession()
    #expect(session.audioEngine.isRunning)
    session.deactivateTap()
    #expect(!session.isSessionActive)
    #expect(!session.audioEngine.isRunning)
    #expect(!SharedSettings().isSessionActive)
  }

  @Test
  func `successive recordings each release the microphone`() throws {
    try #require(AVAudioApplication.shared.recordPermission == .granted)
    let session = BackgroundAudioSession()
    defer { session.endSession() }
    for _ in 0 ..< 2 {
      try session.startSession()
      #expect(session.isSessionActive)
      #expect(session.audioEngine.isRunning)
      session.deactivateTap()
      #expect(!session.isSessionActive)
      #expect(!session.audioEngine.isRunning)
      #expect(!SharedSettings().isSessionActive)
    }
  }

  @Test
  func `keyboard recording keeps the session ready until it is ended`() throws {
    try #require(AVAudioApplication.shared.recordPermission == .granted)
    let session = BackgroundAudioSession()
    defer { session.endSession() }
    try session.startSession()
    session.deactivateTap(keepSessionReady: true)
    #expect(session.isSessionActive)
    #expect(session.audioEngine.isRunning)
    #expect(SharedSettings().isSessionActive)
    session.endSession()
    #expect(!session.isSessionActive)
    #expect(!session.audioEngine.isRunning)
    #expect(!SharedSettings().isSessionActive)
  }
}
