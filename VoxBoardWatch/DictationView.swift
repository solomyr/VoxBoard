import SwiftUI
import WatchKit

/// Tap to record, tap to finish. Your iPhone transcribes and polishes the text,
/// then Send opens the share sheet so you can pick a Messages contact.
struct DictationView: View {
  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        switch self.state {
        case .idle:
          self.micButton(recording: false)
          Text("Tap to dictate").font(.footnote).foregroundStyle(.secondary)
        case .recording:
          self.micButton(recording: true)
          Text("Listening… tap to finish").font(.footnote).foregroundStyle(.secondary)
        case .working:
          ProgressView()
          Text("Writing on your iPhone…").font(.footnote).foregroundStyle(.secondary)
        case .done(let reply):
          Text(reply.text).frame(maxWidth: .infinity, alignment: .leading)
          ShareLink(item: reply.text) { Label("Send", systemImage: "paperplane.fill") }
            .tint(.accentColor)
          Button {
            Task {
              if await WatchLink.shared.copyToPhone(reply.text) {
                WKInterfaceDevice.current().play(.success)
                self.copied = true
              }
            }
          } label: {
            Label(self.copied ? "Copied to iPhone" : "Copy to iPhone", systemImage: self.copied ? "checkmark" : "doc.on.doc")
          }
          if reply.original != reply.text {
            Button("Use original") { self.state = .done(.init(text: reply.original, original: reply.original)) }
          }
          Button("New message") {
            WatchLink.shared.clearLastReply()
            self.copied = false
            self.state = .idle
          }
        case .failed(let message):
          Text(message).font(.footnote).multilineTextAlignment(.center)
          Button("Try again") { self.state = .idle }
        }
      }
      .padding(.horizontal, 4)
    }
    .navigationTitle("VoxBoard")
    .onAppear {
      WatchLink.shared.activate()
      WatchLink.shared.onLateReply = { reply in self.state = .done(reply) }
      // A result that arrived while the app was closed.
      if case .idle = self.state, let reply = WatchLink.shared.lastReply { self.state = .done(reply) }
    }
  }

  private enum DictationState {
    case idle, recording, working
    case done(WatchLink.Reply)
    case failed(String)
  }

  @State private var state = DictationState.idle
  @State private var copied = false
  @State private var recorder = WatchRecorder()

  private func micButton(recording: Bool) -> some View {
    Button {
      Task { await (recording ? self.finish() : self.start()) }
    } label: {
      Image(systemName: recording ? "stop.fill" : "mic.fill")
        .font(.system(size: 34, weight: .semibold))
        .frame(width: 84, height: 84)
        .background(recording ? Color.red : Color.accentColor, in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(recording ? "Finish dictation" : "Start dictation")
  }

  private func start() async {
    do {
      try await self.recorder.start()
      WKInterfaceDevice.current().play(.start)
      self.state = .recording
    } catch {
      self.state = .failed(error.localizedDescription)
    }
  }

  private func finish() async {
    guard let audio = self.recorder.stop() else {
      self.state = .idle
      return
    }
    WKInterfaceDevice.current().play(.stop)
    self.state = .working
    do {
      self.state = .done(try await WatchLink.shared.transcribe(audio))
      WKInterfaceDevice.current().play(.success)
    } catch {
      self.state = .failed(error.localizedDescription)
      WKInterfaceDevice.current().play(.failure)
    }
  }
}
