import CoreGraphics
import Foundation
import os

/// Word list for swipe typing, mapped onto one keyboard layout's keys.
/// Lists come from FrequencyWords (Hermit Dave, CC BY-SA 4.0), most frequent first.
final class SwipeLexicon: @unchecked Sendable {
  struct Entry: Sendable {
    let word: String
    /// Layout keys for each letter, with repeated keys collapsed ("hello" → h e l o).
    let keys: [Character]
    let rank: Int
  }

  init(language: KeyboardLanguage, words: [String], rankOffset: Int = 0) {
    let layoutKeys = Set(language.rows.joined().compactMap(\.first))
    var mapping: [Character: Character] = [:]
    for key in layoutKeys {
      mapping[key] = key
      for alternative in language.alternatives(for: String(key)) {
        if let character = alternative.first, mapping[character] == nil { mapping[character] = key }
      }
    }
    var byFirstKey: [Character: [Entry]] = [:]
    for (rank, word) in words.enumerated() {
      var keys: [Character] = []
      var usable = true
      for character in word {
        guard let key = mapping[character] ?? Self.baseLetter(character).flatMap({ mapping[$0] }) else {
          usable = false
          break
        }
        if keys.last != key { keys.append(key) }
      }
      guard usable, keys.count >= 2, let first = keys.first else { continue }
      byFirstKey[first, default: []].append(Entry(word: word, keys: keys, rank: rank + rankOffset))
    }
    self.entriesByFirstKey = byFirstKey
  }

  let entriesByFirstKey: [Character: [Entry]]

  static func fileCode(for language: KeyboardLanguage) -> String {
    language.rawValue.hasPrefix("bg") ? "bg" : language.rawValue
  }

  /// Loads the bundled list for a layout, or nil when none is bundled. Parsed lists are
  /// cached, so reopening the keyboard does not re-read 30,000 words each time.
  static func load(_ language: KeyboardLanguage) -> SwipeLexicon? {
    if let cached = self.cache.withLock({ $0[language] }) { return cached }
    let loaded = self.loadUncached(language)
    if let loaded { self.cache.withLock { $0[language] = loaded } }
    return loaded
  }

  /// Every word in the list, for checking whether a learned word is new.
  private(set) lazy var allWords: Set<String> = Set(self.entriesByFirstKey.values.flatMap { $0.map(\.word) })

  private static let cache = OSAllocatedUnfairLock<[KeyboardLanguage: SwipeLexicon]>(initialState: [:])

  private static func loadUncached(_ language: KeyboardLanguage) -> SwipeLexicon? {
    let name = "swipe-\(Self.fileCode(for: language))"
    let bundles = [Bundle.main, Bundle(for: SwipeLexicon.self)]
    guard
      let url = bundles.lazy.compactMap({ $0.url(forResource: name, withExtension: "txt") }).first,
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return nil }
    let words = text.split(separator: "\n").map(String.init)
    return SwipeLexicon(language: language, words: words)
  }

  private static func baseLetter(_ character: Character) -> Character? {
    let decomposed = String(character).decomposedStringWithCanonicalMapping
    return decomposed.unicodeScalars.first.map { Character($0) }
  }
}

/// Turns a finger path over the letter keys into ranked word candidates.
/// Candidates must start near the first touch, end near the last, and visit
/// every letter's key in order; survivors are ranked by how closely the
/// path follows the word's ideal key-to-key shape, plus word frequency.
struct SwipeDecoder: Sendable {
  /// Centers of the layout's letter keys, in the same coordinates as the path.
  let keyCenters: [Character: CGPoint]
  let keySize: CGSize

  /// Scoring weights, tuned against synthetic sloppy swipes (see SwipeTypingTests).
  struct Weights: Sendable {
    var shape: CGFloat = 2.0
    var coverage: CGFloat = 0.5
    var frequency: CGFloat = 0.06
    var endpoints: CGFloat = 0.5
  }

  var weights = Weights()

  func candidates(for path: [CGPoint], in lexicon: SwipeLexicon, limit: Int = 4,
                  boost: (String) -> CGFloat = { _ in 0 }) -> [String] {
    self.scored(for: path, in: lexicon, boost: boost).prefix(limit).map(\.word)
  }

  /// Candidates ordered best first, with their cost (lower is better).
  func scored(for path: [CGPoint], in lexicon: SwipeLexicon,
              boost: (String) -> CGFloat = { _ in 0 }) -> [(word: String, cost: CGFloat)] {
    guard path.count >= 2, self.keySize.width > 0, self.keySize.height > 0 else { return [] }
    let user = Self.resample(path, count: Self.shapePoints).map(self.normalized)
    let userLength = Self.length(user)
    guard let first = user.first, let last = user.last else { return [] }
    let startKeys = self.keysNear(path[0], radius: 1.6)
    let endKeys = Set(self.keysNear(path[path.count - 1], radius: 1.6))

    var results: [(word: String, cost: CGFloat)] = []
    for start in startKeys {
      for entry in lexicon.entriesByFirstKey[start] ?? [] {
        guard let lastKey = entry.keys.last, endKeys.contains(lastKey) else { continue }
        let keyPoints = entry.keys.compactMap { self.keyCenters[$0] }.map(self.normalized)
        guard keyPoints.count == entry.keys.count, let kFirst = keyPoints.first, let kLast = keyPoints.last else { continue }
        let templateLength = Self.length(keyPoints)
        // Corner cutting makes real paths a bit shorter; far longer or shorter is another word.
        guard templateLength < userLength * 1.9 + 1.2, templateLength > userLength * 0.45 - 0.6 else { continue }
        let template = Self.resample(keyPoints, count: Self.shapePoints)
        var shape: CGFloat = 0
        for index in template.indices { shape += Self.distance(template[index], user[index]) }
        shape /= CGFloat(template.count)
        // Every letter's key should lie near the path, in order: the cheapest
        // monotonic alignment of keys to path points (dynamic programming).
        var previousRow = [CGFloat](repeating: 0, count: user.count)
        var row = [CGFloat](repeating: 0, count: user.count)
        for (keyIndex, key) in keyPoints.enumerated() {
          var runningMin = CGFloat.greatestFiniteMagnitude
          for index in user.indices {
            let d = Self.distance(key, user[index])
            let before = keyIndex == 0 ? 0 : previousRow[index]
            runningMin = min(runningMin, before)
            row[index] = d * d + runningMin
          }
          swap(&previousRow, &row)
        }
        var coverage = previousRow.min() ?? 0
        coverage /= CGFloat(keyPoints.count)
        let endpoints = Self.distance(kFirst, first) + Self.distance(kLast, last)
        let cost = self.weights.shape * shape * shape
          + self.weights.coverage * coverage
          + self.weights.endpoints * endpoints * endpoints
          + self.weights.frequency * log(CGFloat(entry.rank) + 1)
          - boost(entry.word)
        results.append((entry.word, cost))
      }
    }
    var seen = Set<String>()
    return results.sorted { $0.cost < $1.cost }.filter { seen.insert($0.word).inserted }
  }

  private static let shapePoints = 40

  /// Points in key units (1 = one key width or height).
  private func normalized(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x / self.keySize.width, y: point.y / self.keySize.height)
  }

  private static func length(_ points: [CGPoint]) -> CGFloat {
    zip(points, points.dropFirst()).reduce(0) { $0 + Self.distance($1.0, $1.1) }
  }

  /// Keys whose center lies within `radius` key sizes of the point.
  private func keysNear(_ point: CGPoint, radius: CGFloat) -> [Character] {
    self.keyCenters.compactMap { key, center in
      let dx = (point.x - center.x) / self.keySize.width
      let dy = (point.y - center.y) / self.keySize.height
      return dx * dx + dy * dy <= radius * radius ? key : nil
    }
  }

  static func resample(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
    guard let first = points.first, spacing > 0 else { return points }
    var result = [first]
    var previous = first
    var carried: CGFloat = 0
    for point in points.dropFirst() {
      var segmentStart = previous
      var segment = Self.distance(segmentStart, point)
      while carried + segment >= spacing {
        let t = (spacing - carried) / segment
        let next = CGPoint(x: segmentStart.x + (point.x - segmentStart.x) * t, y: segmentStart.y + (point.y - segmentStart.y) * t)
        result.append(next)
        segmentStart = next
        segment = Self.distance(segmentStart, point)
        carried = 0
      }
      carried += segment
      previous = point
    }
    if let last = points.last, result.last != last { result.append(last) }
    return result
  }

  static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
    guard points.count >= 2, count >= 2 else { return Array(repeating: points.first ?? .zero, count: count) }
    var length: CGFloat = 0
    for index in 1 ..< points.count { length += Self.distance(points[index - 1], points[index]) }
    guard length > 0 else { return Array(repeating: points[0], count: count) }
    var result = Self.resample(points, spacing: length / CGFloat(count - 1))
    if result.count > count { result = Array(result.prefix(count - 1)) + [points[points.count - 1]] }
    while result.count < count { result.append(points[points.count - 1]) }
    return result
  }

  static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(b.x - a.x, a.y - b.y)
  }
}

/// What this keyboard has learned from you, kept only on this device: words you
/// swipe, pick, or type (so names and slang become swipeable), and which word
/// tends to follow which, so the same swipe can mean different words in context.
@MainActor
final class SwipeMemory {
  static let shared = SwipeMemory()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Cost reduction for a candidate: more for words you use, most after the same previous word.
  func boost(_ word: String, after previous: String?, language: KeyboardLanguage) -> CGFloat {
    self.snapshot(language: language).boost(word, after: previous)
  }

  /// A copy of what has been learned, safe to read off the main thread.
  struct Snapshot: Sendable {
    let words: [String: Int]
    let pairs: [String: Int]

    func boost(_ word: String, after previous: String?) -> CGFloat {
      let single = CGFloat(self.words[word] ?? 0)
      let pair = previous.map { CGFloat(self.pairs["\($0) \(word)"] ?? 0) } ?? 0
      return 0.12 * log(1 + single) + 0.35 * log(1 + pair)
    }
  }

  func snapshot(language: KeyboardLanguage) -> Snapshot {
    let store = self.store(for: language)
    return Snapshot(words: store.words, pairs: store.pairs)
  }

  func learn(_ word: String, after previous: String?, language: KeyboardLanguage, weight: Int = 1) {
    let word = word.lowercased(with: language.locale)
    guard word.count >= 2, word.allSatisfy(\.isLetter) else { return }
    var store = self.store(for: language)
    store.words[word, default: 0] += weight
    if let previous { store.pairs[Self.pairKey(previous, word), default: 0] += weight }
    if store.words[word, default: 0] <= 0 { store.words[word] = nil }
    store.trim()
    self.stores[SwipeLexicon.fileCode(for: language)] = store
    self.scheduleSave(language)
  }

  /// Writing thousands of entries on every word would stall typing; save once things are quiet.
  private func scheduleSave(_ language: KeyboardLanguage) {
    self.pendingSave?.cancel()
    self.pendingSave = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard let self, !Task.isCancelled else { return }
      self.save(self.store(for: language), language)
    }
  }

  private var pendingSave: Task<Void, Never>?

  /// Words you have used at least twice that the bundled list lacks.
  func extraWords(language: KeyboardLanguage, excluding lexicon: SwipeLexicon) -> [String] {
    let known = lexicon.allWords
    return self.store(for: language).words.filter { $0.value >= 2 && !known.contains($0.key) }.map(\.key)
  }

  func forget(language: KeyboardLanguage) {
    self.stores[SwipeLexicon.fileCode(for: language)] = Store()
    self.defaults.removeObject(forKey: Self.key(language))
  }

  /// The last whole word before the cursor, if the cursor follows a word and a space.
  static func previousWord(in context: String?, locale: Locale) -> String? {
    guard let context, let last = context.split(whereSeparator: { !$0.isLetter }).last else { return nil }
    // Only the current sentence counts.
    let tail = context[last.endIndex...]
    guard !tail.contains(where: { ".!?\n".contains($0) }) else { return nil }
    return String(last).lowercased(with: locale)
  }

  private struct Store: Codable {
    var words: [String: Int] = [:]
    var pairs: [String: Int] = [:]

    mutating func trim() {
      if self.words.count > 3000 { self.words = Dictionary(uniqueKeysWithValues: self.words.sorted { $0.value > $1.value }.prefix(2500).map { ($0.key, $0.value) }) }
      if self.pairs.count > 6000 { self.pairs = Dictionary(uniqueKeysWithValues: self.pairs.sorted { $0.value > $1.value }.prefix(5000).map { ($0.key, $0.value) }) }
    }
  }

  private let defaults: UserDefaults
  private var stores: [String: Store] = [:]

  private func store(for language: KeyboardLanguage) -> Store {
    if let store = self.stores[SwipeLexicon.fileCode(for: language)] { return store }
    let store = self.defaults.data(forKey: Self.key(language)).flatMap { try? JSONDecoder().decode(Store.self, from: $0) } ?? Store()
    self.stores[SwipeLexicon.fileCode(for: language)] = store
    return store
  }

  private func save(_ store: Store, _ language: KeyboardLanguage) {
    if let data = try? JSONEncoder().encode(store) { self.defaults.set(data, forKey: Self.key(language)) }
  }

  private static func key(_ language: KeyboardLanguage) -> String { "swipeMemory.\(SwipeLexicon.fileCode(for: language))" }
  private static func pairKey(_ previous: String, _ word: String) -> String { "\(previous) \(word)" }
}
