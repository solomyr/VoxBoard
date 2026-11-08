import CoreGraphics
import Foundation

/// Word list for swipe typing, mapped onto one keyboard layout's keys.
/// Lists come from FrequencyWords (Hermit Dave, CC BY-SA 4.0), most frequent first.
final class SwipeLexicon: @unchecked Sendable {
  struct Entry: Sendable {
    let word: String
    /// Layout keys for each letter, with repeated keys collapsed ("hello" → h e l o).
    let keys: [Character]
    let rank: Int
  }

  init(language: KeyboardLanguage, words: [String]) {
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
      byFirstKey[first, default: []].append(Entry(word: word, keys: keys, rank: rank))
    }
    self.entriesByFirstKey = byFirstKey
  }

  let entriesByFirstKey: [Character: [Entry]]

  static func fileCode(for language: KeyboardLanguage) -> String {
    language.rawValue.hasPrefix("bg") ? "bg" : language.rawValue
  }

  /// Loads the bundled list for a layout, or nil when none is bundled.
  static func load(_ language: KeyboardLanguage) -> SwipeLexicon? {
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
struct SwipeDecoder {
  /// Centers of the layout's letter keys, in the same coordinates as the path.
  let keyCenters: [Character: CGPoint]
  let keySize: CGSize

  func candidates(for path: [CGPoint], in lexicon: SwipeLexicon, limit: Int = 4) -> [String] {
    guard path.count >= 2, self.keySize.width > 0, self.keySize.height > 0 else { return [] }
    let samples = Self.resample(path, spacing: self.keySize.width * 0.25)
    let near = samples.map { self.keysNear($0, radius: 0.85) }
    let startKeys = self.keysNear(samples[0], radius: 1.1)
    let endKeys = self.keysNear(samples[samples.count - 1], radius: 1.1)
    let userShape = Self.resample(samples, count: Self.shapePoints)

    var scored: [(word: String, score: CGFloat)] = []
    for first in startKeys {
      for entry in lexicon.entriesByFirstKey[first] ?? [] {
        guard let last = entry.keys.last, endKeys.contains(last), Self.follows(entry.keys, near) else { continue }
        let ideal = Self.resample(entry.keys.compactMap { self.keyCenters[$0] }, count: Self.shapePoints)
        guard ideal.count == userShape.count else { continue }
        var distance: CGFloat = 0
        for index in ideal.indices {
          let dx = (ideal[index].x - userShape[index].x) / self.keySize.width
          let dy = (ideal[index].y - userShape[index].y) / self.keySize.height
          distance += (dx * dx + dy * dy).squareRoot()
        }
        let shape = distance / CGFloat(ideal.count)
        let frequency = 0.07 * log(CGFloat(entry.rank) + 1)
        scored.append((entry.word, shape + frequency))
      }
    }
    var seen = Set<String>()
    return scored.sorted { $0.score < $1.score }.map(\.word).filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
  }

  private static let shapePoints = 32

  /// Keys whose center lies within `radius` key sizes of the point.
  private func keysNear(_ point: CGPoint, radius: CGFloat) -> Set<Character> {
    var keys = Set<Character>()
    for (key, center) in self.keyCenters {
      let dx = (point.x - center.x) / self.keySize.width
      let dy = (point.y - center.y) / self.keySize.height
      if dx * dx + dy * dy <= radius * radius { keys.insert(key) }
    }
    return keys
  }

  /// True when the path passes near each key in order.
  private static func follows(_ keys: [Character], _ near: [Set<Character>]) -> Bool {
    var sample = 0
    for key in keys {
      while sample < near.count, !near[sample].contains(key) { sample += 1 }
      if sample == near.count { return false }
    }
    return true
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

  private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(b.x - a.x, a.y - b.y)
  }
}
