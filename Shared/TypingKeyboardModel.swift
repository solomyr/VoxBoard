import Combine
import CoreGraphics
import Foundation

/// Letter order follows familiar QWERTY/AZERTY/QWERTZ and Cyrillic layouts.
/// Bulgarian reference: https://unicode.org/cldr/charts/41/keyboards/layouts/bg.html
enum KeyboardLanguage: String, CaseIterable, Identifiable, Sendable {
  case english = "en"
  case bulgarianPhonetic = "bg-phonetic"
  case bulgarianBDS = "bg-bds"
  case german = "de"
  case french = "fr"
  case spanish = "es"
  case italian = "it"
  case portuguese = "pt"
  case greek = "el"
  case russian = "ru"
  case ukrainian = "uk"
  case turkish = "tr"

  var id: String { self.rawValue }

  var name: String {
    switch self {
    case .english: "English · QWERTY"
    case .bulgarianPhonetic: "Български · Фонетична"
    case .bulgarianBDS: "Български · БДС"
    case .german: "Deutsch · QWERTZ"
    case .french: "Français · AZERTY"
    case .spanish: "Español"
    case .italian: "Italiano"
    case .portuguese: "Português"
    case .greek: "Ελληνικά"
    case .russian: "Русский"
    case .ukrainian: "Українська"
    case .turkish: "Türkçe"
    }
  }

  var shortName: String {
    switch self {
    case .bulgarianPhonetic: "БГ · Фон"
    case .bulgarianBDS: "БГ · БДС"
    default: self.rawValue.uppercased()
    }
  }

  /// Shown on the space bar.
  var spaceLabel: String {
    switch self {
    case .bulgarianPhonetic: "Български · Фонетична"
    case .bulgarianBDS: "Български · БДС"
    default: String(self.name.split(separator: " · ").first ?? Substring(self.name))
    }
  }

  var locale: Locale {
    Locale(identifier: self.rawValue.hasPrefix("bg-") ? "bg" : self.rawValue)
  }

  var rows: [[String]] {
    let rows: [String] = switch self {
    case .english, .italian, .portuguese: ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    case .bulgarianPhonetic: ["явертъуиопю", "асдфгхйклшщ", "зьцжбнмч"]
    case .bulgarianBDS: ["уеишщксдзцб", "ьяаожгтнвмч", "юйъэфхпрл"]
    case .german: ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"]
    case .french: ["azertyuiop", "qsdfghjklm", "wxcvbn"]
    case .spanish: ["qwertyuiop", "asdfghjklñ", "zxcvbnm"]
    case .greek: ["ςερτυθιοπ", "ασδφγηξκλ", "ζχψωβνμ"]
    case .russian: ["йцукенгшщзхъ", "фывапролджэ", "ячсмитьбю"]
    case .ukrainian: ["йцукенгшщзхї", "фівапролджє", "ячсмитьбюґ"]
    case .turkish: ["qwertyuıopğü", "asdfghjklşi", "zxcvbnmöç"]
    }
    return rows.map { $0.map(String.init) }
  }

  func alternatives(for key: String) -> [String] {
    if self == .bulgarianPhonetic || self == .bulgarianBDS {
      return key == "и" ? ["ѝ"] : []
    }
    if self == .russian { return key == "е" ? ["ё"] : [] }
    if self == .ukrainian { return key == "г" ? ["ґ"] : [] }
    if self == .greek {
      return ["α": ["ά"], "ε": ["έ"], "η": ["ή"], "ι": ["ί", "ϊ", "ΐ"],
              "ο": ["ό"], "υ": ["ύ", "ϋ", "ΰ"], "ω": ["ώ"]][key] ?? []
    }
    return ["a": ["á", "à", "â", "ä", "ã", "å", "æ"], "c": ["ç", "ć", "č"],
            "e": ["é", "è", "ê", "ë"], "i": ["í", "ì", "î", "ï", "ı"],
            "n": ["ñ", "ń"], "o": ["ó", "ò", "ô", "ö", "õ", "ø", "œ"],
            "s": ["ß", "ś", "š", "ş"], "u": ["ú", "ù", "û", "ü"],
            "y": ["ý", "ÿ"], "g": ["ğ"], "z": ["ź", "ż", "ž"]][key] ?? []
  }
}

enum TypingPage { case letters, numbers, symbols }
enum TypingShift { case off, once, locked }
enum TypingCapitalization { case none, sentences, words, allCharacters }

/// One-handed typing: the keys shrink toward one side of the screen.
enum OneHandedMode: String, CaseIterable, Sendable {
  case off, left, right

  static let defaultsKey = "keyboardOneHandedMode"
  /// Fraction of the full keyboard width the keys use in one-handed mode.
  static let keyWidthFraction: CGFloat = 0.82
}

@MainActor
final class TypingKeyboardModel: ObservableObject {
  init(language: KeyboardLanguage = .english, defaults: UserDefaults = .standard) {
    self.language = language
    self.defaults = defaults
    self.oneHanded = defaults.string(forKey: OneHandedMode.defaultsKey).flatMap(OneHandedMode.init(rawValue:)) ?? .off
  }

  @Published var oneHanded: OneHandedMode {
    didSet { self.defaults.set(self.oneHanded.rawValue, forKey: OneHandedMode.defaultsKey) }
  }
  private let defaults: UserDefaults

  // MARK: Swipe typing

  /// Other likely words for the last swiped word; tapping one replaces it.
  @Published var swipeSuggestions: [String] = []
  /// The last word a swipe inserted, while it can still be replaced or deleted as a whole.
  @Published var lastSwipeWord: String?
  /// Text before the cursor, as last reported by the text field.
  private(set) var contextBefore: String?

  /// Applies the current shift state to a swiped word and uses up a one-shot shift.
  func casedSwipeWord(_ word: String) -> String {
    let result: String
    switch self.shift {
    case .off: result = word
    case .once: result = word.prefix(1).uppercased(with: self.language.locale) + word.dropFirst()
    case .locked: result = word.uppercased(with: self.language.locale)
    }
    if self.shift == .once { self.shift = .off }
    self.lastShiftTap = nil
    return result
  }

  /// Matches a replacement word to the case of the word it replaces.
  func matchCase(_ word: String, to original: String) -> String {
    if original.count > 1, original == original.uppercased(with: self.language.locale) {
      return word.uppercased(with: self.language.locale)
    }
    if let first = original.first, first.isUppercase {
      return word.prefix(1).uppercased(with: self.language.locale) + word.dropFirst()
    }
    return word
  }

  /// A swiped word starts with a space unless it follows a space, a line break, or an opening bracket.
  var swipeNeedsLeadingSpace: Bool {
    // The last swiped word already ended with a space (the text field may not have caught up yet).
    if self.lastSwipeWord != nil { return false }
    guard let last = self.contextBefore?.last else { return false }
    return !(last.isWhitespace || "([{\"«„“‘¿¡".contains(last))
  }

  func clearSwipe() {
    if !self.swipeSuggestions.isEmpty { self.swipeSuggestions = [] }
    if self.lastSwipeWord != nil { self.lastSwipeWord = nil }
  }

  @Published var language: KeyboardLanguage

  /// The language used before the current one: a flick on the space bar switches back to it.
  var previousLanguage: KeyboardLanguage? {
    self.defaults.string(forKey: Self.previousLanguageKey).flatMap(KeyboardLanguage.init(rawValue:))
  }

  private static let previousLanguageKey = "keyboardPreviousLanguage"

  /// Switches layout and remembers the one you left, so the space bar can toggle between them.
  func choose(_ language: KeyboardLanguage) {
    if language != self.language { self.defaults.set(self.language.rawValue, forKey: Self.previousLanguageKey) }
    self.language = language
    self.page = .letters
  }
  @Published var page = TypingPage.letters
  @Published private(set) var shift = TypingShift.once
  private var lastShiftTap: TimeInterval?

  var rows: [[String]] {
    switch self.page {
    case .letters: self.language.rows
    case .numbers: [Array("1234567890").map(String.init), Array("-/:;()€&@\"").map(String.init), [".", ",", "?", "!", "'"]]
    case .symbols: [Array("[]{}#%^*+=").map(String.init), ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"], [".", ",", "?", "!", "'"]]
    }
  }

  func displayed(_ key: String) -> String {
    self.page == .letters && self.shift != .off ? key.uppercased(with: self.language.locale) : key
  }

  func consume(_ key: String) -> String {
    let result = self.displayed(key)
    if self.shift == .once { self.shift = .off }
    self.lastShiftTap = nil
    return result
  }

  func tapShift(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    if let previous = self.lastShiftTap, time >= previous, time - previous < 0.35 {
      self.shift = .locked
      self.lastShiftTap = nil
    } else {
      self.shift = self.shift == .off ? .once : .off
      self.lastShiftTap = time
    }
  }

  func updateContext(before: String?, capitalization: TypingCapitalization) {
    self.contextBefore = before
    guard self.shift != .locked else { return }
    guard let before else { if self.shift != .off { self.shift = .off }; return }
    let upper: Bool
    switch capitalization {
    case .none: upper = false
    case .allCharacters: upper = true
    case .words: upper = before.isEmpty || before.last?.isWhitespace == true
    case .sentences:
      let trimmed = before.trimmingCharacters(in: .whitespaces)
      upper = trimmed.isEmpty || trimmed.last.map { ".!?\n".contains($0) } == true
    }
    let shift: TypingShift = upper ? .once : .off
    if self.shift != shift { self.shift = shift }
  }
}
