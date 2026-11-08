import CoreGraphics
import Testing
@testable import Sayboard

@Suite("Swipe typing")
@MainActor
struct SwipeTypingTests {
  /// Key centers for a phone-sized layout: 36×46 pt keys, rows offset like iOS.
  private static func centers(_ language: KeyboardLanguage) -> [Character: CGPoint] {
    var result: [Character: CGPoint] = [:]
    for (row, keys) in language.rows.enumerated() {
      let width: CGFloat = 390 / CGFloat(language.rows[0].count)
      let inset = (390 - width * CGFloat(keys.count)) / 2
      for (column, key) in keys.enumerated() {
        result[Character(key)] = CGPoint(x: inset + width * (CGFloat(column) + 0.5), y: 23 + CGFloat(row) * 52)
      }
    }
    return result
  }

  /// A sloppy finger path: through each key with a small wobble.
  private static func path(for word: String, _ centers: [Character: CGPoint]) -> [CGPoint] {
    var points: [CGPoint] = []
    let keys = word.compactMap { centers[$0] }
    for (index, key) in keys.enumerated() {
      let wobble = CGFloat(index % 2 == 0 ? 5 : -5)
      if let previous = points.last {
        for step in 1 ... 6 {
          let t = CGFloat(step) / 6
          points.append(CGPoint(x: previous.x + (key.x - previous.x) * t, y: previous.y + (key.y - previous.y) * t + wobble * t))
        }
      } else {
        points.append(CGPoint(x: key.x + 3, y: key.y - 4))
      }
    }
    return points
  }

  @Test(arguments: [
    (KeyboardLanguage.english, "hello"), (.english, "thanks"), (.english, "keyboard"), (.english, "tomorrow"),
    (.english, "meeting"), (.bulgarianPhonetic, "здравей"), (.bulgarianPhonetic, "благодаря"),
    (.german, "danke"), (.french, "bonjour"),
  ])
  func `a swipe through a word's keys suggests that word first`(language: KeyboardLanguage, word: String) throws {
    let lexicon = try #require(SwipeLexicon.load(language))
    let centers = Self.centers(language)
    let decoder = SwipeDecoder(keyCenters: centers, keySize: CGSize(width: 390 / CGFloat(language.rows[0].count), height: 46))
    let candidates = decoder.candidates(for: Self.path(for: word, centers), in: lexicon)
    #expect(candidates.first == word, "\(candidates)")
  }

  @Test
  func `swiped words follow shift and need a space after a word`() {
    let model = TypingKeyboardModel(language: .english, defaults: UserDefaults(suiteName: "swipe-tests")!)
    model.updateContext(before: "", capitalization: .sentences)
    #expect(model.casedSwipeWord("hello") == "Hello")
    #expect(model.casedSwipeWord("there") == "there")
    model.updateContext(before: "Hello", capitalization: .sentences)
    #expect(model.swipeNeedsLeadingSpace)
    model.updateContext(before: "Hello ", capitalization: .sentences)
    #expect(!model.swipeNeedsLeadingSpace)
    #expect(model.matchCase("help", to: "Hello") == "Help")
  }

  @Test
  func `sloppy swipes of common words are decoded accurately`() throws {
    let language = KeyboardLanguage.english
    let lexicon = try #require(SwipeLexicon.load(language))
    let centers = Self.centers(language)
    let size = CGSize(width: 390 / CGFloat(language.rows[0].count), height: 46)
    let decoder = SwipeDecoder(keyCenters: centers, keySize: size)
    let entries = lexicon.entriesByFirstKey.values.flatMap { $0 }.filter { $0.rank < 2000 }.sorted { $0.rank < $1.rank }
    var seed: UInt64 = 42
    func noise() -> CGFloat {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return CGFloat(Int64(bitPattern: seed >> 11) % 1000) / 1000 * 0.3
    }
    var hits = 0
    for entry in entries.prefix(300) {
      let path = entry.keys.compactMap { centers[$0] }.map { CGPoint(x: $0.x + noise() * size.width, y: $0.y + noise() * size.height) }
      if decoder.candidates(for: path, in: lexicon).first == entry.word { hits += 1 }
    }
    #expect(hits >= 270, "\(hits)/300")
  }

  @Test
  func `words you use after a word win the same swipe next time`() throws {
    let defaults = try #require(UserDefaults(suiteName: "swipe-memory-tests"))
    defaults.removePersistentDomain(forName: "swipe-memory-tests")
    let memory = SwipeMemory(defaults: defaults)
    #expect(memory.boost("hey", after: "oh", language: .english) == 0)
    memory.learn("hey", after: "oh", language: .english, weight: 3)
    #expect(memory.boost("hey", after: "oh", language: .english) > memory.boost("hey", after: "the", language: .english))
    #expect(memory.boost("hey", after: "the", language: .english) > 0)
    #expect(SwipeMemory.previousWord(in: "Oh ", locale: Locale(identifier: "en")) == "oh")
    #expect(SwipeMemory.previousWord(in: "Done. ", locale: Locale(identifier: "en")) == nil)
  }

  @Test(arguments: [
    ("Could you please pass me the", ["sale", "salt"], "salt"),
    ("Could you please pass me the", ["salt", "sale"], "salt"),
    ("I agree with the", ["tens", "terms"], "terms"),
    ("See you", ["tomorrow", "tomorrows", "tomato"], "tomorrow"),
    ("Thank you so", ["much", "mich", "mud"], "much"),
  ])
  func `the on-device model picks the word that fits the sentence when available`(context: String, options: [String], expected: String) async {
    guard let choice = await SwipeContextRanker.choose(context: context, candidates: options, language: .english) else {
      print("SWIPE CONTEXT MODEL: unavailable")
      return
    }
    print("SWIPE CONTEXT MODEL: \(context) \(options) -> \(choice)")
    #expect(choice == expected)
  }
}
