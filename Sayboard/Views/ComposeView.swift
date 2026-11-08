import AVFoundation
import SwiftUI
import UIKit

struct ComposeView: View {
  @EnvironmentObject private var speech: SpeechRecognitionService
  @EnvironmentObject private var speechModels: ModelDownloadService
  @EnvironmentObject private var textModels: LLMDownloadService
  @EnvironmentObject private var llm: LLMProcessingCoordinator
  @EnvironmentObject private var permissions: PermissionService
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject private var dictationLaunch = DictationLaunchRequest.shared
  @AppStorage(SharedKey.llmEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var autoPolish = true
  @State private var draft = ""
  @State private var original = ""
  @State private var message: String?
  @State private var isWorking = false
  @State private var isStarting = false
  @State private var showsOriginal = false
  @State private var copied = false
  @State private var ownsRecording = false
  @State private var restoredDraft = false
  @FocusState private var editorFocused: Bool

  private var busy: Bool { self.isStarting || self.isWorking || self.llm.isProcessing || self.speech.isStopping }
  private var hasDraft: Bool { !self.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        self.introduction
        if !self.speechModels.hasUsableModel || !self.textModels.hasUsableModel {
          self.setupCard
        }
        self.recordingCard
        self.editorCard
        self.keyboardCard
      }
      .padding()
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("VoxBoard")
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { self.editorFocused = false }
      }
    }
    .task {
      guard !self.restoredDraft else { return }
      if let saved = try? ComposeDraftStore().load() {
        self.draft = saved.text
        self.original = saved.original
      }
      self.restoredDraft = true
      await self.handleDictationShortcut()
    }
    .task(id: self.dictationLaunch.pendingRequest) { await self.handleDictationShortcut() }
    .onChange(of: self.scenePhase) { _, phase in
      if phase == .active { Task { await self.handleDictationShortcut() } }
    }
    .onChange(of: self.draft) { _, _ in self.copied = false; self.saveDraft() }
    .onChange(of: self.original) { _, _ in self.saveDraft() }
    .onChange(of: self.speech.historySaveGeneration) {
      // Also finish a recording stopped by an interruption or the duration limit.
      guard self.ownsRecording, !self.isWorking else { return }
      Task { await self.finishRecording() }
    }
  }

  private var introduction: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("ON-DEVICE · MULTILINGUAL", systemImage: "lock.shield")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tint)
      Text("Your voice. Ready to send.")
        .font(.largeTitle.bold())
      Text("Speak naturally. VoxBoard transcribes your voice and polishes the text locally, in the language you use.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var setupCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Set up your local models", systemImage: "arrow.down.circle")
        .font(.headline)
      Text("Download once with an internet connection. Your voice and messages stay on this device.")
        .font(.footnote).foregroundStyle(.secondary)
      if !self.speechModels.hasUsableModel {
        self.downloadRow(
          title: "1. Multilingual transcription",
          detail: "Whisper Small · \(ModelVariant.whisperSmall.supportedLanguages.count) languages · 445 MB",
          state: self.speechModels.state(for: .whisperSmall),
          action: { self.speechModels.startDownload(variant: .whisperSmall) },
          cancel: { self.speechModels.cancelDownload(variant: .whisperSmall) },
        )
      }
      if !self.textModels.hasUsableModel {
        self.downloadRow(
          title: "2. Local text cleanup",
          detail: "Qwen 3.5 0.8B · multilingual · 562 MB",
          state: self.textModels.state(for: .qwen35Small),
          action: { self.textModels.startDownload(variant: .qwen35Small) },
          cancel: { self.textModels.cancelDownload(variant: .qwen35Small) },
        )
      }
      NavigationLink("Choose other models") { ModelsView() }
        .font(.subheadline.weight(.medium))
    }
    .voxCard()
  }

  private func downloadRow(
    title: String, detail: String, state: ModelDownloadState,
    action: @escaping () -> Void, cancel: @escaping () -> Void,
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.subheadline.weight(.semibold))
      Text(detail).font(.caption).foregroundStyle(.secondary)
      switch state {
      case .downloading(let progress):
        ProgressView(value: progress)
        HStack {
          Text(progress, format: .percent.precision(.fractionLength(0)))
          Spacer()
          Button("Cancel", action: cancel)
        }.font(.caption)
      case .error(let error):
        Text(error).font(.caption).foregroundStyle(.red)
        Button("Retry download", action: action).buttonStyle(.bordered)
      case .notDownloaded:
        Button("Download", action: action).buttonStyle(.bordered)
      case .downloaded:
        Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
      }
    }
  }

  private var recordingCard: some View {
    VStack(spacing: 16) {
      Button {
        self.editorFocused = false
        Task {
          if self.speech.isRecording { await self.finishRecording() }
          else { await self.beginRecording() }
        }
      } label: {
        HStack(spacing: 12) {
          if self.busy { ProgressView().tint(.white) }
          else { Image(systemName: self.speech.isRecording ? "stop.fill" : "mic.fill") }
          Text(self.recordButtonTitle)
            .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .foregroundStyle(.white)
        .background(self.speech.isRecording ? Color.red : Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
      }
      .buttonStyle(.plain)
      .disabled(self.busy || !self.speechModels.hasUsableModel)
      .accessibilityIdentifier("compose.record")

      HStack {
        Label(self.speechModels.selectedVariant.displayName, systemImage: "globe")
        Spacer()
        Text(self.speech.isRecording ? "Listening…" : "Automatic language detection")
      }
      .font(.caption).foregroundStyle(.secondary)
      Label(
        self.speech.isSessionActive ? "Microphone active" : "Microphone off",
        systemImage: self.speech.isSessionActive ? "mic.fill" : "mic.slash",
      )
      .font(.caption.weight(.medium))
      .foregroundStyle(self.speech.isSessionActive ? Color.orange : Color.secondary)
      .accessibilityIdentifier("compose.microphoneStatus")
      Toggle("Polish automatically", isOn: self.$autoPolish)
        .disabled(self.busy || self.speech.isRecording)
      if self.autoPolish, !self.textModels.hasUsableModel {
        Text("Download a text model above to enable polishing. Dictation works on its own.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let message = self.message {
        Text(message).font(.footnote).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("compose.status")
      }
    }
    .voxCard()
  }

  private var recordButtonTitle: String {
    if self.isStarting { return "Preparing to record…" }
    if self.busy { return self.llm.isProcessing ? "Polishing on-device…" : "Transcribing on-device…" }
    return self.speech.isRecording ? "Stop and prepare text" : "Tap to speak"
  }

  private var editorCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Your message").font(.headline)
        Spacer()
        if self.hasDraft {
          Button("Clear") { self.draft = ""; self.original = ""; self.message = nil }
            .font(.subheadline).disabled(self.busy || self.speech.isRecording)
            .accessibilityIdentifier("compose.clear")
        }
      }
      ZStack(alignment: .topLeading) {
        if self.draft.isEmpty {
          Text("Your finished text will appear here. You can also type or paste a draft to polish.")
            .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
        }
        TextEditor(text: self.$draft)
          .scrollContentBackground(.hidden)
          .frame(minHeight: 190)
          .focused(self.$editorFocused)
          .disabled(self.busy || self.speech.isRecording)
          .accessibilityLabel("Message draft")
          .accessibilityIdentifier("compose.draft")
      }
      HStack(spacing: 12) {
        Button {
          Task { await self.polishDraft() }
        } label: { Label("Polish", systemImage: "sparkles") }
          .buttonStyle(.bordered)
          .disabled(!self.hasDraft || self.busy || self.speech.isRecording || !self.textModels.hasUsableModel)
          .accessibilityIdentifier("compose.polish")
        Spacer()
        Button {
          UIPasteboard.general.string = self.draft
          self.copied = true
        } label: { Label(self.copied ? "Copied" : "Copy", systemImage: self.copied ? "checkmark" : "doc.on.doc") }
          .buttonStyle(.borderedProminent)
          .disabled(!self.hasDraft || self.busy || self.speech.isRecording)
          .accessibilityIdentifier("compose.copy")
        ShareLink(item: self.draft) { Image(systemName: "square.and.arrow.up") }
          .accessibilityLabel("Share message")
          .accessibilityIdentifier("compose.share")
          .disabled(!self.hasDraft || self.busy || self.speech.isRecording)
      }
      Text("Review names, numbers, and meaning before sending.")
        .font(.caption).foregroundStyle(.secondary)
      if !self.original.isEmpty {
        DisclosureGroup("Original transcript", isExpanded: self.$showsOriginal) {
          VStack(alignment: .leading, spacing: 8) {
            Text(self.original).font(.subheadline).textSelection(.enabled)
            Button("Restore original") { self.draft = self.original }
              .font(.subheadline).disabled(self.busy)
          }.padding(.top, 8)
        }
      }
    }
    .voxCard()
  }

  private var keyboardCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Dictate from your keyboard", systemImage: "keyboard").font(.headline)
      Text("Tap the keyboard microphone to start and tap again to finish, or hold it while you speak. The first recording opens VoxBoard briefly to turn the microphone on; after that you record right in the keyboard, and your text is prepared and inserted for you.")
        .font(.footnote).foregroundStyle(.secondary)
      Text("Nothing is recorded until you tap the mic. Turn the microphone off from the keyboard or in Settings.")
        .font(.footnote.weight(.medium))
      Button("Keyboard setup") {
        if let url = URL(string: UIApplication.openSettingsURLString) { self.openURL(url) }
      }.buttonStyle(.bordered)
      Text("You can also use “Dictate with VoxBoard” in Shortcuts or with your Action Button to record in Compose.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .voxCard()
  }

  private func microphoneAllowed() async -> Bool {
    self.permissions.refreshMicrophoneState()
    if self.permissions.microphoneState == .undetermined {
      let granted = await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
      }
      self.permissions.refreshMicrophoneState()
      return granted
    }
    return self.permissions.microphoneState == .granted
  }

  private func beginRecording() async {
    guard !self.busy else { return }
    guard self.draft.isEmpty else {
      self.message = "Copy or clear your current message before recording another."
      return
    }
    guard self.speechModels.hasUsableModel else {
      self.message = "Download a speech model before recording."
      return
    }
    self.isStarting = true
    defer { self.isStarting = false }
    guard await self.microphoneAllowed() else {
      self.message = "Allow microphone access in iOS Settings to record your voice."
      return
    }
    self.message = nil
    self.original = ""
    self.ownsRecording = true
    // Compose always records on demand, even after a previous background session.
    self.speech.session.endSession()
    await self.speech.startRecordingAfterModelLoad(deliverToKeyboard: false)
    if !self.speech.isRecording {
      self.ownsRecording = false
      self.speech.session.endSession()
      self.message = self.speech.errorMessage ?? "Could not start recording. Check your microphone and selected model."
    }
  }

  private func finishRecording() async {
    guard !self.isWorking else { return }
    self.isWorking = true
    defer { self.isWorking = false; self.ownsRecording = false }
    await self.speech.stopRecording()
    let transcript = self.speech.rawTranscription
    guard !transcript.isEmpty else {
      self.message = "No speech was transcribed. Check the microphone and try again."
      return
    }
    self.original = transcript
    self.draft = transcript
    if self.autoPolish, self.textModels.hasUsableModel {
      await self.applyPolish()
    } else {
      self.message = "Transcribed on-device. Your message is ready to review."
    }
  }

  private func polishDraft() async {
    guard !self.busy, self.hasDraft else { return }
    self.editorFocused = false
    self.isWorking = true
    defer { self.isWorking = false }
    if self.original.isEmpty { self.original = self.draft }
    await self.applyPolish()
  }

  private func applyPolish() async {
    if let result = await self.llm.polish(self.draft) {
      self.draft = result
      self.message = "Polished on-device. Ready to review, copy, or share."
    } else {
      self.message = "Polishing did not finish. Your original text is preserved. Try a shorter message or a smaller text model."
    }
  }

  private func saveDraft() {
    guard self.restoredDraft else { return }
    do {
      try ComposeDraftStore().save(ComposeDraft(text: self.draft, original: self.original))
    } catch {
      self.message = "Could not save your draft. Copy the message before closing VoxBoard."
    }
  }

  private func handleDictationShortcut() async {
    guard self.restoredDraft, self.scenePhase == .active,
          self.dictationLaunch.pendingRequest != nil else { return }
    self.dictationLaunch.pendingRequest = nil
    guard !self.speech.isRecording, !self.busy else { return }
    await self.beginRecording()
  }
}

private extension View {
  func voxCard() -> some View {
    self.padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
  }
}
