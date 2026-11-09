
import Foundation

import UIKit

@MainActor
final class LLMProcessingCoordinator: ObservableObject {

  let inferenceService = LLMInferenceService()

  weak var speechService: SpeechRecognitionService?
  weak var downloadService: LLMDownloadService?

  @Published private(set) var isProcessing = false

  /// Foreground composition shares the same local runtime as keyboard cleanup.
  /// A failed cleanup leaves the caller's original transcript intact.
  func polish(_ text: String, action: LLMAction = .readyToSend) async -> String? {
    guard !self.isProcessing, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let downloadService = self.downloadService, downloadService.hasUsableModel,
      self.speechService?.isRecording != true, self.speechService?.isStopping != true
    else { return nil }
    let variant = SharedSettings().selectedLLMVariant
    guard let modelPath = downloadService.modelFileURL(for: variant)?.path else { return nil }

    self.isProcessing = true
    let settings = SharedSettings()
    settings.isLLMProcessing = true
    defer {
      self.releaseModelWhenIdle()
      self.isProcessing = false
      settings.isLLMProcessing = false
    }
    await self.prepareForInference(variant: variant, modelPath: modelPath)
    guard self.inferenceService.loadState == .loaded, !Task.isCancelled else { return nil }
    let result = await self.runInferenceWithTimeout(
      systemPrompt: LLMPromptTemplates.systemPrompt(for: action, language: nil),
      userText: text,
      assistantPrefill: "",
    )
    guard !Task.isCancelled, let result else { return nil }
    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
    guard action != .readyToSend || ReadyToSendValidation.preservesNumbers(original: text, edited: trimmed) else { return nil }
    return trimmed.isEmpty ? nil : trimmed
  }

  func setupObservers() {
    // Answer the keyboard's status ping while polishing, so it keeps waiting for the
    // result instead of giving up (the mic session may be off during a polish).
    self.statusObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.requestSessionStatus
    ) { [weak self] in
      Task { @MainActor [weak self] in
        guard self?.isProcessing == true else { return }
        TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingStarted)
      }
    }
    self.requestObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.requestLLMProcessing
    ) { [weak self] in
      Task { @MainActor [weak self] in
        let tokenSettings = SharedSettings()
        tokenSettings.synchronize()
        guard tokenSettings.dictationSessionToken != nil else {
          return
        }
        await self?.handleProcessingRequest()
      }
    }
  }

  private struct ValidatedRequest {
    let request: LLMRequest
    let modelPath: String
    let variant: LLMModelVariant
  }

  private static let safetyMarginSeconds: TimeInterval = 5
  private static let inferenceTimeoutSeconds: TimeInterval = 120

  private var requestObserver: DarwinNotificationObserver?
  private var statusObserver: DarwinNotificationObserver?

  func handleProcessingRequest() async {
    guard !self.isProcessing else {
      DiagnosticLog.write("llm: request ignored, already processing")
      return
    }
    DiagnosticLog.write("llm: request received")

    guard !SharedSettings().isDictationLocked else {
      LLMBridge.clearRequest()
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      return
    }

    self.isProcessing = true
    let settings = SharedSettings()
    settings.isLLMProcessing = true
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingStarted)
    let stylingHost = OnboardingTextEntry.stylingHost(settings.hostBundleId)
    let sessionToken = settings.dictationSessionToken

    defer {
      self.isProcessing = false
      settings.isLLMProcessing = false
      if settings.dictationSessionToken == sessionToken { settings.dictationSessionToken = nil }
      LLMBridge.clearRequest()
    }

    guard let validated = self.validateRequest(settings: settings) else { return }

    let bgTaskID = self.beginInferenceBackgroundTask()
    defer { self.endInferenceBackgroundTask(bgTaskID) }

    await self.prepareForInference(variant: validated.variant, modelPath: validated.modelPath)

    guard self.inferenceService.loadState == .loaded else {
      let state = String(describing: self.inferenceService.loadState)
      DiagnosticLog.write("llm: load failed, state=\(state)")
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      return
    }
    DiagnosticLog.write("llm: model loaded")

    let systemPrompt = self.buildSystemPrompt(for: validated.request, settings: settings)
    let prefill = validated.request.action.continuesInput ? validated.request.text : ""
    let result = await self.runInferenceWithTimeout(
      systemPrompt: systemPrompt,
      userText: validated.request.text,
      assistantPrefill: prefill,
    )

    if let result, !result.isEmpty,
      validated.request.action != .readyToSend
        || ReadyToSendValidation.preservesNumbers(original: validated.request.text, edited: result) {
      let finalResult = self.styled(result, action: validated.request.action, host: stylingHost, settings: settings)
      LLMBridge.writeResult(finalResult, replacing: validated.request.replacementContext,
                            hostBundleId: validated.request.hostBundleId)
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingComplete)
      DiagnosticLog.write("llm: complete, result=\(finalResult.count) chars")
    } else {
      DiagnosticLog.write("llm: FAILED, inference produced nothing")
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
    }

    self.releaseModelWhenIdle()
  }

  /// Devices with plenty of memory keep the text model (and the speech model) loaded
  /// between dictations, so back-to-back messages don't reload gigabytes from disk each
  /// time; it is released after two idle minutes. Smaller devices release it at once.
  static let keepsModelsLoaded = ProcessInfo.processInfo.physicalMemory >= 7_000_000_000

  private func releaseModelWhenIdle() {
    self.idleUnloadTask?.cancel()
    guard Self.keepsModelsLoaded else {
      self.inferenceService.unloadModel()
      return
    }
    self.idleUnloadTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(120))
      guard let self, !Task.isCancelled, !self.isProcessing else { return }
      self.inferenceService.unloadModel()
    }
  }

  private var idleUnloadTask: Task<Void, Never>?

  private func validateRequest(settings: SharedSettings) -> ValidatedRequest? {
    settings.synchronize()
    guard let request = LLMBridge.readRequest() else {
      DiagnosticLog.write("llm: no request in bridge")
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      return nil
    }
    DiagnosticLog.write("llm: text=\(request.text.count) chars, action=\(request.action.rawValue)")

    guard let downloadService = self.downloadService, downloadService.hasUsableModel else {
      DiagnosticLog.write("llm: no usable model, selected=\(settings.selectedLLMVariant.rawValue)")
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      return nil
    }

    let variant = settings.selectedLLMVariant
    guard let modelPath = downloadService.modelFileURL(for: variant)?.path else {
      DiagnosticLog.write("llm: model file missing for \(variant.rawValue)")
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      return nil
    }
    DiagnosticLog.write("llm: variant=\(variant.rawValue), template=\(variant.chatTemplate.rawValue)")

    return ValidatedRequest(request: request, modelPath: modelPath, variant: variant)
  }

  private func beginInferenceBackgroundTask() -> UIBackgroundTaskIdentifier {
    var bgTaskID = UIBackgroundTaskIdentifier.invalid
    bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "LLMInference") {
      DiagnosticLog.write("llm: background task EXPIRED — suspension imminent")
      UIApplication.shared.endBackgroundTask(bgTaskID)
      bgTaskID = .invalid
    }
    let remaining = UIApplication.shared.backgroundTimeRemaining
    let budget = remaining < .greatestFiniteMagnitude ? "\(Int(remaining))s" : "unlimited"
    DiagnosticLog.write("llm: bg task started, budget=\(budget)")
    return bgTaskID
  }

  private func endInferenceBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
    if taskID != .invalid {
      UIApplication.shared.endBackgroundTask(taskID)
    }
  }

  private func prepareForInference(variant: LLMModelVariant, modelPath: String) async {
    self.idleUnloadTask?.cancel()
    if let speechService = self.speechService {
      if Self.keepsModelsLoaded {
        if speechService.isRecording { await speechService.stopRecording() }
      } else {
        await speechService.unloadForLLMProcessing()
      }
    }

    if self.inferenceService.loadState != .loaded {
      await self.inferenceService.loadModel(variant: variant, path: modelPath)
    }
  }

  private func styled(_ text: String, action: LLMAction, host: String?, settings: SharedSettings) -> String {
    guard action != .readyToSend, action != .addPunctuation, action != .fixGrammar else { return text }
    let resolvedStyle = AppStyleStore().resolvedStyle(
      hostBundleId: host,
      defaultStyle: settings.defaultWritingStyle,
    )
    return TextStyleFormatter.format(text, style: resolvedStyle)
  }

  private func buildSystemPrompt(for request: LLMRequest, settings: SharedSettings) -> String {
    let language = request.language
    if
      let customId = request.customPromptId,
      let custom = settings.llmCustomPrompts.first(where: { $0.id == customId })
    {
      return LLMPromptTemplates.systemPrompt(for: custom, language: language)
    }
    return LLMPromptTemplates.systemPrompt(for: request.action, language: language)
  }

  private func runInferenceWithTimeout(
    systemPrompt: String,
    userText: String,
    assistantPrefill: String,
  ) async -> String? {
    let remaining = UIApplication.shared.backgroundTimeRemaining
    let timeout: TimeInterval =
      if remaining < .greatestFiniteMagnitude {
        max(remaining - Self.safetyMarginSeconds, 10)
      } else {
        Self.inferenceTimeoutSeconds
      }

    return await withTaskGroup(of: String?.self) { group in
      group.addTask {
        await self.inferenceService.process(
          systemPrompt: systemPrompt,
          userText: userText,
          assistantPrefill: assistantPrefill,
        )
      }

      group.addTask {
        try? await Task.sleep(for: .seconds(timeout))
        return nil
      }

      if let result = await group.next() {
        group.cancelAll()
        return result
      }

      group.cancelAll()
      return nil
    }
  }
}
