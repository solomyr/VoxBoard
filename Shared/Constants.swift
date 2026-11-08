import Foundation

enum AppGroup {
  static let identifier = "group.app.voxboard.shared"

  static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }

  static var sharedDefaults: UserDefaults? {
    UserDefaults(suiteName: identifier)
  }
}

enum DeepLink {
  static let scheme = "voxboard"
  static let polishHost = "polish"
  static var polishURL: URL? { URL(string: "\(scheme)://\(polishHost)") }
  static let dictateHost = "dictate"
  static let stopHost = "stop"
  static let settingsHost = "settings"
  static let modelsHost = "models"
  static let setupMicHost = "setup-mic"
  static let unlockHost = "unlock"

  static var dictateURL: URL? {
    URL(string: "\(scheme)://\(dictateHost)")
  }

  static var settingsURL: URL? {
    URL(string: "\(scheme)://\(settingsHost)")
  }

  static var modelsURL: URL? {
    URL(string: "\(scheme)://\(modelsHost)")
  }

  static var setupMicURL: URL? {
    URL(string: "\(scheme)://\(setupMicHost)")
  }

  static var unlockURL: URL? {
    URL(string: "\(scheme)://\(unlockHost)")
  }
}

enum SharedKey {
  static let transcribedText = "transcribedText"
  static let lastDictationOutcome = "lastDictationOutcome"
  static let isRecording = "isRecording"
  static let selectedVariant = "selectedVariant"
  static let keyboardRequestedDictation = "keyboardRequestedDictation"
  static let keyboardRequestedDictationAt = "keyboardRequestedDictationAt"
  static let appLanguage = "appLanguage"
  static let retentionPolicy = "retentionPolicy"
  static let isSessionActive = "isSessionActive"
  static let mainAppHeartbeat = "mainAppHeartbeat"
  static let sessionAutoStopPolicy = "sessionAutoStopPolicy"
  static let keepsKeyboardMicReady = "keepsKeyboardMicReady"
  static let whisperKitModelPath = "whisperKitModelPath"
  static let hostBundleId = "hostBundleId"
  static let canResolveHostApplication = "canResolveHostApplication"
  static let hostPid = "hostPid"
  static let hostPidVersion = "hostPidVersion"
  static let rememberedHostsByProcess = "rememberedHostsByProcess"
  static let downloadInProgressVariants = "downloadInProgressVariants"
  static let downloadStartedAt = "downloadStartedAt"
  static let preferredLanguagesPerVariant = "preferredLanguagesPerVariant"
  static let hasUsableModel = "hasUsableModel"
  static let parakeetV3NeedsRedownload = "parakeetV3NeedsRedownload"
  static let audioLevel = "audioLevel"
  static let isMicrophoneAuthorized = "isMicrophoneAuthorized"
  static let hasCompletedOnboarding = "hasCompletedOnboarding"
  static let onboardingRecord = "onboardingRecord"
  static let onboardingPracticePid = "onboardingPracticePid"
  static let onboardingPracticeAt = "onboardingPracticeAt"
  static let micHintDismissed = "micHintDismissed"
  static let hasFullAccess = "hasFullAccess"
  static let isModelLoading = "isModelLoading"
  static let hasPreparedModelOnce = "hasPreparedModelOnce"
  static let useCustomSpaceBar = "useCustomSpaceBar"
  static let isTranslationMode = "isTranslationMode"
  static let appWritingStyles = "appWritingStyles"
  static let defaultWritingStyle = "defaultWritingStyle"
  static let selectedLLMVariant = "selectedLLMVariant"
  static let hasUsableLLMModel = "hasUsableLLMModel"
  static let llmDownloadInProgressVariants = "llmDownloadInProgressVariants"
  static let completedLLMUpgradeFrom = "completedLLMUpgradeFrom"
  static let declinedLLMUpgrades = "declinedLLMUpgrades"
  static let isLLMProcessing = "isLLMProcessing"
  static let llmEnabled = "llmEnabled"
  static let defaultLLMAction = "defaultLLMAction"
  static let defaultLLMActionSelection = "defaultLLMActionSelection"
  static let llmCustomPrompts = "llmCustomPrompts"
  static let longPressLLMAction = "longPressLLMAction"
  static let disabledLLMActions = "disabledLLMActions"
  static let snippets = "snippets"
  static let dictationSessionToken = "dictationSessionToken"
  static let showGlobeKey = "showGlobeKey"
  static let needsInputModeSwitchKey = "needsInputModeSwitchKey"
  static let alsoCopyToClipboard = "alsoCopyToClipboard"
  static let keyboardKind = "keyboardKind"
  static let keyboardLanguage = "keyboardLanguage"
  static let keyboardHapticsEnabled = "keyboardHapticsEnabled"
  static let periodShortcutEnabled = "periodShortcutEnabled"
  static let entitlementStatus = "entitlementStatus"
  static let entitlementEnvironment = "entitlementEnvironment"
  static let freeWordsUsed = "freeWordsUsed"
}

enum HistoryRetentionPolicy: String, CaseIterable, Sendable {
  case never
  case last5
  case last25
  case last50
  case last100
  case last500
  case past24Hours
  case pastWeek
  case pastMonth
  case forever

  var displayNameKey: String {
    switch self {
    case .never: "Never"
    case .last5: "Last 5 recordings"
    case .last25: "Last 25 recordings"
    case .last50: "Last 50 recordings"
    case .last100: "Last 100 recordings"
    case .last500: "Last 500 recordings"
    case .past24Hours: "Past 24 hours"
    case .pastWeek: "Past week"
    case .pastMonth: "Past month"
    case .forever: "Forever"
    }
  }

  var shortDisplayNameKey: String {
    switch self {
    case .never: "Never"
    case .last5: "Last 5"
    case .last25: "Last 25"
    case .last50: "Last 50"
    case .last100: "Last 100"
    case .last500: "Last 500"
    case .past24Hours: "24 hours"
    case .pastWeek: "1 week"
    case .pastMonth: "1 month"
    case .forever: "Forever"
    }
  }
}

enum DarwinNotificationName {
  static let transcriptionReady = "app.voxboard.transcriptionReady"
  static let dictationStarted = "app.voxboard.dictationStarted"
  static let dictationStopped = "app.voxboard.dictationStopped"
  static let requestStartDictation = "app.voxboard.requestStartDictation"
  static let requestStopDictation = "app.voxboard.requestStopDictation"
  static let sessionStarted = "app.voxboard.sessionStarted"
  static let sessionEnded = "app.voxboard.sessionEnded"
  static let requestEndSession = "app.voxboard.requestEndSession"
  static let requestSessionStatus = "app.voxboard.requestSessionStatus"
  static let fullAccessChanged = "app.voxboard.fullAccessChanged"
  static let modelLoadingFailed = "app.voxboard.modelLoadingFailed"
  static let requestLLMProcessing = "app.voxboard.requestLLMProcessing"
  static let llmProcessingStarted = "app.voxboard.llmProcessingStarted"
  static let llmProcessingComplete = "app.voxboard.llmProcessingComplete"
  static let llmProcessingFailed = "app.voxboard.llmProcessingFailed"
  static let dictationLockChanged = "app.voxboard.dictationLockChanged"
  static let keyboardShownInPractice = "app.voxboard.keyboardShownInPractice"
}

enum SessionAutoStopPolicy: String, CaseIterable, Sendable {
  case never
  case fiveMinutes
  case fifteenMinutes
  case thirtyMinutes
  case oneHour
  case twoHours
  case fourHours
  case eightHours
  case twelveHours

  var displayNameKey: String {
    switch self {
    case .never: "Never"
    case .fiveMinutes: "5 minutes"
    case .fifteenMinutes: "15 minutes"
    case .thirtyMinutes: "30 minutes"
    case .oneHour: "1 hour"
    case .twoHours: "2 hours"
    case .fourHours: "4 hours"
    case .eightHours: "8 hours"
    case .twelveHours: "12 hours"
    }
  }

  var timeoutSeconds: TimeInterval? {
    switch self {
    case .never: nil
    case .fiveMinutes: 300
    case .fifteenMinutes: 900
    case .thirtyMinutes: 1_800
    case .oneHour: 3_600
    case .twoHours: 7_200
    case .fourHours: 14_400
    case .eightHours: 28_800
    case .twelveHours: 43_200
    }
  }
}

extension Notification.Name {
  static let appLanguageChangeRequested = Notification.Name("app.voxboard.appLanguageChangeRequested")
  static let dictationFailedNoModel = Notification.Name("app.voxboard.dictationFailedNoModel")
  static let dictationFailedNoMic = Notification.Name("app.voxboard.dictationFailedNoMic")
  static let purchaseScreenRequested = Notification.Name("app.voxboard.purchaseScreenRequested")
}

enum AppLanguageConfig {

  static let supported: Set = [
    "en",
    "ru",
    "bg",
    "cs",
    "da",
    "de",
    "el",
    "es",
    "et",
    "fi",
    "fr",
    "hi",
    "hr",
    "hu",
    "it",
    "ja",
    "ko",
    "lt",
    "lv",
    "nl",
    "no",
    "pl",
    "pt",
    "ro",
    "sk",
    "sl",
    "sv",
    "tr",
    "uk",
    "zh",
  ]
  static let fallback = "en"

  static func resolveLanguage(from preferredLanguages: [String]) -> String {
    let systemLanguage = preferredLanguages.first
      .flatMap { Locale(identifier: $0).language.languageCode?.identifier }
      ?? self.fallback
    let appLanguage = self.systemLanguageAliases[systemLanguage] ?? systemLanguage
    return self.supported.contains(appLanguage) ? appLanguage : self.fallback
  }

  private static let systemLanguageAliases = ["nb": "no", "nn": "no"]

}

enum AnimationSpeed {
  static let globalMultiplier: Float = 1.5
}
