import Foundation
import Testing

@Suite("Multilingual typing keyboard")
@MainActor
struct TypingKeyboardTests {
  @Test
  func `English uses QWERTY and both Bulgarian layouts contain the full alphabet`() {
    #expect(KeyboardLanguage.english.rows.map { $0.joined() } == ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
    let alphabet = Set("абвгдежзийклмнопрстуфхцчшщъьюя".map(String.init))
    for language in [KeyboardLanguage.bulgarianPhonetic, .bulgarianBDS] {
      let keys = language.rows.flatMap { $0 }
      #expect(alphabet.isSubset(of: Set(keys)))
      #expect(Set(keys).count == keys.count)
      #expect(language.alternatives(for: "и").contains("ѝ"))
    }
    #expect(KeyboardLanguage.bulgarianPhonetic.rows[0].prefix(6).joined() == "явертъ")
    #expect(KeyboardLanguage.bulgarianBDS.rows[0].prefix(6).joined() == "уеишщк")
  }

  @Test(arguments: KeyboardLanguage.allCases)
  func `every selectable layout has three nonempty rows with unique keys`(_ language: KeyboardLanguage) {
    #expect(language.rows.count == 3)
    #expect(language.rows.allSatisfy { !$0.isEmpty && $0.count <= 12 })
    #expect(language.rows.flatMap { $0 }.allSatisfy { $0.count == 1 })
    for row in language.rows { #expect(row.count == Set(row).count) }
  }

  @Test
  func `shift applies once and double tapping locks capitals`() {
    let keyboard = TypingKeyboardModel()
    #expect(keyboard.consume("a") == "A")
    #expect(keyboard.consume("b") == "b")
    keyboard.tapShift(at: 10)
    keyboard.tapShift(at: 10.2)
    #expect(keyboard.shift == .locked)
    #expect(keyboard.consume("c") == "C")
    keyboard.updateContext(before: "abc", capitalization: .sentences)
    #expect(keyboard.consume("d") == "D")
    keyboard.tapShift(at: 12)
    #expect(keyboard.consume("e") == "e")
  }

  @Test
  func `capitalization follows the host field and handles Cyrillic and Turkish`() {
    let keyboard = TypingKeyboardModel(language: .bulgarianPhonetic)
    keyboard.updateContext(before: "Здравей. ", capitalization: .sentences)
    #expect(keyboard.consume("щ") == "Щ")
    keyboard.updateContext(before: "Здравей", capitalization: .sentences)
    #expect(keyboard.consume("я") == "я")
    keyboard.updateContext(before: "", capitalization: .none)
    #expect(keyboard.consume("а") == "а")
    keyboard.language = .turkish
    keyboard.updateContext(before: "", capitalization: .sentences)
    #expect(keyboard.consume("i") == "İ")
    keyboard.updateContext(before: "", capitalization: .allCharacters)
    #expect(keyboard.consume("ı") == "I")
    keyboard.updateContext(before: nil, capitalization: .sentences)
    #expect(keyboard.shift == .off)
  }

  @Test
  func `numbers and symbols insert literally and leave the language intact`() {
    let keyboard = TypingKeyboardModel(language: .bulgarianPhonetic)
    keyboard.page = .numbers
    #expect(keyboard.rows[0].joined() == "1234567890")
    #expect(keyboard.consume("5") == "5")
    keyboard.page = .symbols
    #expect(keyboard.rows.flatMap { $0 }.contains("€") == false)
    #expect(keyboard.rows.flatMap { $0 }.contains("£"))
    #expect(keyboard.consume("@") == "@")
    #expect(keyboard.language == .bulgarianPhonetic)
    keyboard.page = .letters
    #expect(keyboard.rows[0].first == "я")
  }

  @Test
  func `language selection survives restart and invalid preferences fall back to English`() throws {
    let name = "app.voxboard.tests.typing.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = SharedSettings(defaults: defaults)
    #expect(settings.keyboardLanguage == .english)
    settings.keyboardLanguage = .bulgarianBDS
    #expect(SharedSettings(defaults: defaults).keyboardLanguage == .bulgarianBDS)
    defaults.set("unknown", forKey: SharedKey.keyboardLanguage)
    #expect(settings.keyboardLanguage == .english)
  }
}
