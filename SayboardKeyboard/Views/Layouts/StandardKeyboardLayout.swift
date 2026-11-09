import SwiftUI
import UIKit

struct StandardKeyboardLayout: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState
  @State private var notice: LocalizedStringKey?
  /// A light tap like the system keyboard's. Needs Full Access; iOS ignores it otherwise.
  @State private var keyHaptic = UIImpactFeedbackGenerator(style: .light)
  /// What the current finger-down on the mic did, from touch-down to lift.
  private enum MicPress { case none, started(Date), stopped, deferredToTap, ignored }
  @State private var micPress = MicPress.none

  /// Holding the mic at least this long records push-to-talk: letting go stops it.
  private static let holdToTalkThreshold: TimeInterval = 0.4

  private func keyPressHaptic() {
    guard self.keyboardState.keyboardHapticsEnabled else { return }
    self.keyHaptic.impactOccurred(intensity: 0.7)
    self.keyHaptic.prepare()
  }

  private var isHoldingMic: Bool {
    if case .started = self.micPress { return true }
    return false
  }

  private var micDisabled: Bool {
    self.busy && !self.keyboardState.isRecording
  }

  private var busy: Bool {
    self.keyboardState.isProcessing || self.keyboardState.isLLMProcessing
  }

  var body: some View {
    VStack(spacing: 0) {
      self.statusBanner
      TypingKeyboardView(
        model: self.keyboardState.typing,
        scale: KeyboardMetrics.scale,
        // Typing stays on while the AI polishes; if you edit, its result is discarded.
        inputDisabled: self.keyboardState.isProcessing || self.keyboardState.isRecording,
        returnLabel: self.keyboardState.returnKeyLabel,
        onInsert: { self.proxy.insertText($0) },
        onSpace: { self.proxy.insertSpace() },
        onDelete: { self.proxy.deleteBackward() },
        onMoveCursor: self.proxy.adjustTextPosition,
        onLanguageChange: self.keyboardState.selectTypingLanguage,
        onKeyPress: self.keyPressHaptic,
        toolbar: { self.toolbar },
        globe: { GlobeKey(fixedWidth: 36.kbScaled) },
      )
    }
    .onAppear { self.proxy.setActionBarVisible(false) }
    .onChange(of: self.keyboardState.isRecording) { _, recording in
      if recording { self.notice = nil }
    }
    .onChange(of: self.keyboardState.sessionSetupRequired) { _, required in
      if required { self.notice = SetupBlocker.sessionInactive.message }
    }
  }

  private var statusBanner: some View {
    VStack(spacing: 0) {
      if let message = self.keyboardState.llmError?.message ?? self.notice {
        HStack(spacing: 8) {
          Text(message).font(.footnote).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("typing.notice")
          Spacer(minLength: 0)
          TouchButton {
            self.notice = nil
            self.keyboardState.llmError = nil
          } label: { Image(systemName: "xmark.circle.fill").frame(width: 32, height: 36) }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
      } else if let outcome = self.keyboardState.dictationOutcome {
        DictationOutcomeLabel(outcome: outcome) { self.keyboardState.dictationOutcome = nil }
      }
    }
    .background {
      GeometryReader { geometry in
        Color.clear
          .onAppear { self.proxy.setStatusStripHeight(geometry.size.height) }
          .onChange(of: geometry.size.height) { _, height in self.proxy.setStatusStripHeight(height) }
      }
    }
  }

  private var toolbar: some View {
    SuggestionAware { suggestionsShown in self.toolbarRow(suggestionsShown: suggestionsShown) }
  }

  private func toolbarRow(suggestionsShown: Bool) -> some View {
    HStack(spacing: 8) {
      if !suggestionsShown {
        Spacer(minLength: 0)
        if self.busy { ProgressView().controlSize(.small) }
        Text(self.statusTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          .accessibilityIdentifier("typing.status")
        Spacer(minLength: 0)
      }
      if self.keyboardState.hasLLMHistory {
        TouchButton { self.proxy.undoLLM() } label: { Image(systemName: "arrow.uturn.backward") }
          .disabled(!self.keyboardState.canUndoLLM || self.busy || self.keyboardState.isRecording)
          .accessibilityLabel("Undo cleanup")
      }
      #if VOXBOARD_INTENT_PROBE
      if #available(iOS 27.0, *) { KeyboardBackgroundProbeButton() }
      KeyboardContextModelProbeButton()
      #endif
      if self.keyboardState.showsAIButton {
        TouchButton {
          self.proxy.requestLLMProcessing(.readyToSend, nil)
        } label: {
          Image(systemName: "sparkles").frame(minWidth: 32, minHeight: 44.kbScaled)
        }
        .disabled(self.busy || self.keyboardState.isRecording)
        .accessibilityLabel("Polish text")
        .accessibilityIdentifier("typing.polish")
      }
      if self.keyboardState.isSessionActive, !self.keyboardState.isRecording, !self.busy {
        TouchButton {
          TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestEndSession)
        } label: {
          Image(systemName: "mic.slash").frame(minWidth: 32, minHeight: 44.kbScaled)
        }
        .accessibilityLabel("Turn microphone off")
        .accessibilityIdentifier("typing.microphoneOff")
      }
      Image(systemName: self.keyboardState.isRecording ? "stop.fill" : "mic.fill")
        .font(.system(size: 18.kbScaled, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 42.kbScaled, height: 42.kbScaled)
        .background(self.keyboardState.isRecording ? Color.red : Color.accentColor, in: Circle())
        .scaleEffect(self.isHoldingMic ? 0.92 : 1)
        .opacity(self.micDisabled ? 0.4 : 1)
        .contentShape(Circle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { _ in self.micPressBegan() }
            .onEnded { _ in self.micPressEnded() }
        )
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(self.keyboardState.isRecording ? "Stop dictation" : "Start dictation")
        .accessibilityHint("Tap to start and tap again to finish, or hold while speaking.")
        .accessibilityAction { self.tapMicrophone() }
        .accessibilityIdentifier("typing.microphone")
    }
  }

  private var statusTitle: LocalizedStringKey {
    if self.keyboardState.isRecording { return "Listening…" }
    if self.keyboardState.isLLMProcessing { return "Polishing…" }
    if self.keyboardState.isProcessing { return "Transcribing…" }
    return self.keyboardState.isSessionActive ? "Mic active" : "Mic off"
  }

  private func micPressBegan() {
    guard case .none = self.micPress else { return }
    if !self.micDisabled { self.keyPressHaptic() }
    if self.micDisabled {
      self.micPress = .ignored
    } else if self.keyboardState.isRecording {
      self.tapMicrophone()
      self.micPress = .stopped
    } else if self.keyboardState.isSessionActive {
      // A running mic session records in place, so start on touch-down.
      self.micPress = self.tapMicrophone() ? .started(Date()) : .ignored
    } else {
      // Without a session the keyboard has to open VoxBoard; do that on lift.
      self.micPress = .deferredToTap
    }
  }

  private func micPressEnded() {
    let press = self.micPress
    self.micPress = .none
    switch press {
    case .started(let start):
      // Held long enough: push-to-talk, so letting go finishes the recording.
      if Date().timeIntervalSince(start) >= Self.holdToTalkThreshold {
        self.keyPressHaptic()
        self.proxy.stopDictation()
      }
    case .deferredToTap:
      self.tapMicrophone()
    case .none, .stopped, .ignored:
      break
    }
  }

  /// Starts or stops dictation. Returns true when a start was requested.
  @discardableResult
  private func tapMicrophone() -> Bool {
    self.keyboardState.dismissMicHint()
    if self.keyboardState.isRecording {
      self.proxy.stopDictation()
    } else if !self.keyboardState.hasFullAccess {
      self.notice = SetupBlocker.fullAccessMissing.message
    } else if !self.keyboardState.isMicrophoneAuthorized {
      self.notice = SetupBlocker.micDenied.message
    } else if !self.keyboardState.hasUsableModel {
      self.notice = SetupBlocker.noModel.message
    } else {
      self.notice = nil
      self.proxy.startDictation()
      return true
    }
    return false
  }
}

/// Reads whether swipe suggestions share the top row, at the toolbar's own position.
private struct SuggestionAware<Content: View>: View {
  @Environment(\.typingSuggestionsShown) private var shown
  let content: (Bool) -> Content
  var body: some View { self.content(self.shown) }
}
