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
}
