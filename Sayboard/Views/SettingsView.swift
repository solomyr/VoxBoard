import SwiftUI
import UIKit

private struct RetentionPolicyListView: View {

  @Binding var selected: HistoryRetentionPolicy

  var body: some View {
    List {
      ForEach(HistoryRetentionPolicy.allCases, id: \.self) { policy in
        self.policyRow(for: policy)
      }
    }
    .navigationTitle("Keep History")
    .navigationBarTitleDisplayMode(.inline)
  }

  @Environment(\.dismiss) private var dismiss
  @State private var pendingPolicy: HistoryRetentionPolicy?
  @State private var deletionCount = 0

  private func policyRow(for policy: HistoryRetentionPolicy) -> some View {
    Button {
      guard policy != self.selected else {
        self.dismiss()
        return
      }
      let count = HistoryStore.shared.recordsToDeleteCount(for: policy)
      if count > 0 {
        self.deletionCount = count
        self.pendingPolicy = policy
      } else {
        self.selected = policy
        self.dismiss()
      }
    } label: {
      HStack {
        Text(LocalizedStringKey(policy.displayNameKey))
        Spacer()
        if self.selected == policy {
          Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
            .fontWeight(.semibold)
        }
      }
    }
    .foregroundStyle(.primary)
    .confirmationDialog(
      "Delete Recordings",
      isPresented: self.isConfirmationPresented(for: policy),
      titleVisibility: .visible,
    ) {
      Button("Delete \(self.deletionCount)", role: .destructive) {
        self.selected = policy
        self.dismiss()
      }
    } message: {
      Text("This will permanently delete \(self.deletionCount) recordings and their audio files.")
    }
  }

  private func isConfirmationPresented(for policy: HistoryRetentionPolicy) -> Binding<Bool> {
    Binding(
      get: { self.pendingPolicy == policy },
      set: { if !$0 { self.pendingPolicy = nil } },
    )
  }
}

struct SettingsView: View, Equatable {

  init() {
    let shared = SharedSettings()
    _selectedRetentionPolicy = State(initialValue: shared.retentionPolicy)
    _selectedKeyboardKind = State(initialValue: shared.keyboardKind)
  }

  var body: some View {
    Form {
      if !self.setupChecklist.isComplete || self.showsLowStorageWarning {
        self.setupSection
      }
      #if APPSTORE
      PurchaseSection()
      #endif
      self.sessionSection
      self.historySection
      TextOutputSection()
      self.keyboardSection
      FeedbackSection()
      self.aboutSection
    }
    .sensoryFeedback(.success, trigger: self.historyClearedTrigger)
    .sensoryFeedback(.success, trigger: self.cacheClearedTrigger)
    .navigationTitle("Settings")
    .navigationDestination(for: Route.self) { _ in
      SetupView()
    }
    .onAppear {
      self.refreshHistoryInfo()
      self.refreshCacheSize()
      self.showsLowStorageWarning = DiskSpace.isLow() && !OperatingSystem.isBackgroundNeuralEngineBlocked
    }
    .onChange(of: self.selectedRetentionPolicy) { _, newValue in
      self.settings.retentionPolicy = newValue
      HistoryStore.shared.applyRetentionPolicy()
      self.refreshHistoryInfo()
    }
    .onChange(of: self.selectedKeyboardKind) { _, newValue in
      self.settings.keyboardKind = newValue
    }
  }

  nonisolated static func ==(_: Self, _: Self) -> Bool {
    true
  }

  private enum Route: Hashable {
    case setup
  }

  private static let defaultLanguage = AppLanguageConfig.fallback

  @AppStorage(SharedKey.appLanguage) private var selectedAppLanguage = defaultLanguage
  @AppStorage(SharedKey.hasUsableModel, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hasUsableModel = false
  @Environment(\.locale) private var locale
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @EnvironmentObject private var permissionService: PermissionService
  @State private var settings = SharedSettings()
  @AppStorage(SharedKey.keepsKeyboardMicReady, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keepsKeyboardMicReady = true
  @AppStorage(SharedKey.sessionAutoStopPolicy, store: UserDefaults(suiteName: AppGroup.identifier))
  private var sessionAutoStopPolicy = SessionAutoStopPolicy.fifteenMinutes
  @State private var selectedRetentionPolicy: HistoryRetentionPolicy
  @State private var selectedKeyboardKind: KeyboardKind
  @State private var showClearHistoryConfirmation = false
  @State private var showClearCacheConfirmation = false
  @State private var historyInfoText = ""
  @State private var historyInfoModificationDate: Date?
  @State private var historyClearedTrigger = false
  @State private var cacheClearedTrigger = false
  @State private var showsLowStorageWarning = false
  @State private var cacheSizeBytes: Int64 = 0

  private let clearHistoryMessage: LocalizedStringKey = "All recordings from the History tab, including transcription text and audio files stored on this device, will be permanently deleted."

  private let clearCacheMessage: LocalizedStringKey = "Compiled models will be removed from cache. Recompilation will be required on next use, which may take up to a minute."

  private let lowStorageMessage: LocalizedStringKey = "When storage runs low, your device may clear the prepared speech model, forcing a slow rebuild before dictation. Free up space in Settings \u{203A} General \u{203A} Storage."

  private var setupChecklist: SetupChecklist {
    SetupChecklist(permissions: self.permissionService, hasUsableModel: self.hasUsableModel)
  }

  private var setupSection: some View {
    Section {
      if !self.setupChecklist.isComplete {
        self.setupRow
      }
      if self.showsLowStorageWarning {
        self.lowStorageRow
      }
    } header: {
      Text("\u{26A0}\u{FE0F} Action Required")
    } footer: {
      if !self.setupChecklist.isComplete {
        Text("Finish these steps to use voice input from the keyboard. Normal typing and Compose are available separately.")
      }
    }
  }

  private var setupRow: some View {
    NavigationLink(value: Route.setup) {
      HStack {
        Text("Setup")
        Spacer()
        if self.setupChecklist.isComplete {
          SetupCompletedMark()
        } else {
          let remaining = self.setupChecklist.remainingCount
          Text(verbatim: "\(remaining)")
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("\(remaining) items need attention"))
        }
      }
    }
  }

  private var lowStorageRow: some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text("Storage Is Getting Low")
        Text(self.lowStorageMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
  }

  private var sessionSection: some View {
    Section {
      Toggle("Instant keyboard dictation", isOn: self.$keepsKeyboardMicReady)
        .onChange(of: self.keepsKeyboardMicReady) { _, enabled in
          if !enabled { self.speechService.session.endSession() }
        }
      if self.keepsKeyboardMicReady {
        Picker("Keep microphone ready", selection: self.$sessionAutoStopPolicy) {
          ForEach(SessionAutoStopPolicy.allCases, id: \.self) { policy in
            Text(LocalizedStringKey(policy.displayNameKey)).tag(policy)
          }
        }
        .onChange(of: self.sessionAutoStopPolicy) { _, _ in self.speechService.session.updateTimeout() }
      }
      if self.speechService.isSessionActive, !self.speechService.isRecording {
        Button("Turn microphone off now", role: .destructive) { self.speechService.session.endSession() }
      }
      NavigationLink("How microphone access works") { SessionInfoView() }
    } header: {
      Text("Keyboard dictation")
    } footer: {
      Text(self.keepsKeyboardMicReady
        ? "After the first recording, the keyboard records in place without opening VoxBoard until the microphone has been idle for the time above. Nothing is captured until you tap the mic, but iOS shows the orange microphone indicator while VoxBoard is ready."
        : "The microphone turns off after every recording, so each keyboard recording briefly opens VoxBoard.")
    }
  }

  private var historySection: some View {
    Section {
      NavigationLink {
        RetentionPolicyListView(selected: self.$selectedRetentionPolicy)
      } label: {
        HStack {
          Text("Keep History")
          Spacer()
          Text(LocalizedStringKey(self.selectedRetentionPolicy.shortDisplayNameKey))
            .foregroundStyle(.secondary)
        }
      }

      self.clearHistoryButton
    } header: {
      Text("History")
    }
  }

  private var clearHistoryButton: some View {
    Button(role: .destructive) {
      self.showClearHistoryConfirmation = true
    } label: {
      HStack {
        Text("Clear All History")
        Spacer()
        Text(verbatim: self.historyInfoText)
          .foregroundStyle(.secondary)
      }
    }
    .confirmationDialog(
      "Clear All History",
      isPresented: self.$showClearHistoryConfirmation,
      titleVisibility: .visible,
    ) {
      Button("Delete All Recordings", role: .destructive) {
        HistoryStore.shared.deleteAllRecords()
        self.historyClearedTrigger.toggle()
        self.refreshHistoryInfo()
      }
    } message: {
      Text(self.clearHistoryMessage)
    }
  }

  private var keyboardSection: some View {
    Section {
      NavigationLink {
        KeyboardSettingsView(selectedKind: self.$selectedKeyboardKind)
      } label: {
        HStack {
          Text("Keyboard")
          Spacer()
          Text(LocalizedStringKey(self.selectedKeyboardKind.displayNameKey))
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityIdentifier("settings.keyboard")
    }
  }

  private var aboutSection: some View {
    Section("About") {
      self.appLanguageRow

      if self.setupChecklist.isComplete {
        self.setupRow
      }

      #if APPSTORE
      FullVersionRow()
      #endif

      Button(role: .destructive) {
        self.showClearCacheConfirmation = true
      } label: {
        HStack {
          Text("Clear Model Cache")
          Spacer()
          Text(verbatim: self.formattedCacheSize)
            .foregroundStyle(.secondary)
        }
      }
      .confirmationDialog(
        "Clear Model Cache",
        isPresented: self.$showClearCacheConfirmation,
        titleVisibility: .visible,
      ) {
        Button("Clear Cache", role: .destructive) {
          ModelStorageManager.clearCompiledModelCache()
          self.refreshCacheSize()
          self.cacheClearedTrigger.toggle()
        }
      } message: {
        Text(self.clearCacheMessage)
      }

      HStack {
        Text("Version")
        Spacer()
        Text(verbatim: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var formattedCacheSize: String {
    guard self.cacheSizeBytes > 0 else { return "" }
    return self.cacheSizeBytes.formatted(.byteCount(style: .file).locale(self.locale))
  }

  private var appLanguageRow: some View {
    NavigationLink {
      AppLanguageListView()
    } label: {
      HStack {
        Text("App Language")
        Spacer()
        Text(verbatim: nativeLanguageNames[self.selectedAppLanguage] ?? self.selectedAppLanguage)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func refreshCacheSize() {
    self.cacheSizeBytes = ModelStorageManager.compiledModelCacheSize()
  }

  private func refreshHistoryInfo() {
    let modified = HistoryStore.shared.historyModificationDate()
    guard modified != self.historyInfoModificationDate else { return }
    guard let count = try? HistoryStore.shared.readRecords().count else { return }
    self.historyInfoModificationDate = modified
    guard count > 0 else { self.historyInfoText = ""
      return
    }
    let bytes = HistoryStore.shared.audioStorageSize()
    guard bytes > 0 else { self.historyInfoText = "\(count)"
      return
    }
    self.historyInfoText = "\(count) \u{00B7} \(bytes.formatted(.byteCount(style: .file).locale(self.locale)))"
  }

}
