#if VOXBOARD_INTENT_PROBE
@preconcurrency import AVFoundation
import os
import SwiftUI

/// Debug-only probe: can the keyboard extension itself capture microphone audio?
struct KeyboardMicProbeButton: View {
  @State private var result = "idle"

  var body: some View {
    Button { self.run() } label: { Image(systemName: "waveform").frame(width: 32, height: 44) }
      .accessibilityLabel("Keyboard mic probe")
      .accessibilityValue(self.result)
      .accessibilityIdentifier("typing.micProbe")
  }

  private func run() {
    self.result = "running"
    let session = AVAudioSession.sharedInstance()
    let perm = AVAudioApplication.shared.recordPermission.rawValue
    do {
      try session.setCategory(.record, mode: .measurement, options: [])
      try session.setActive(true)
    } catch {
      self.result = "session error perm=\(perm): \((error as NSError).code) \(error.localizedDescription)"
      return
    }
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    let stats = OSAllocatedUnfairLock(initialState: (buffers: 0, peak: Float(0)))
    if format.channelCount == 0 || format.sampleRate == 0 {
      self.result = "no input format perm=\(perm) ch=\(format.channelCount) sr=\(format.sampleRate)"
      try? session.setActive(false)
      return
    }
    input.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
      var peak: Float = 0
      if let data = buffer.floatChannelData?[0] {
        for i in 0 ..< Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
      }
      let bufferPeak = peak
      stats.withLock { $0.buffers += 1; $0.peak = max($0.peak, bufferPeak) }
    }
    do {
      engine.prepare()
      try engine.start()
    } catch {
      self.result = "engine error perm=\(perm): \((error as NSError).code) \(error.localizedDescription)"
      input.removeTap(onBus: 0)
      try? session.setActive(false)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      engine.stop()
      input.removeTap(onBus: 0)
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      let s = stats.withLock { $0 }
      self.result = "done perm=\(perm) sr=\(Int(format.sampleRate)) buffers=\(s.buffers) peak=\(String(format: "%.4f", s.peak))"
    }
  }
}
#endif

#if VOXBOARD_INTENT_PROBE
/// Debug-only probe: can the keyboard extension use Apple's on-device model?
struct KeyboardContextModelProbeButton: View {
  @State private var result = "idle"

  var body: some View {
    Button {
      self.result = "running"
      Task { @MainActor in
        let start = Date()
        let choice = await SwipeContextRanker.choose(context: "Could you please pass me the", candidates: ["sale", "salt"], language: .english)
        self.result = "\(choice ?? "unavailable") \(Int(Date().timeIntervalSince(start) * 1000))ms"
      }
    } label: { Image(systemName: "brain").frame(width: 32, height: 44) }
      .accessibilityLabel("Context model probe")
      .accessibilityValue(self.result)
      .accessibilityIdentifier("typing.contextProbe")
  }
}
#endif
