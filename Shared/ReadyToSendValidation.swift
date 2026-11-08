import Foundation

enum ReadyToSendValidation {
  /// A conservative guard against silently changing amounts, times, dates, or quantities.
  /// It supplements the model prompt; it cannot verify names or overall meaning.
  static func preservesNumbers(original: String, edited: String) -> Bool {
    self.numbers(in: original) == self.numbers(in: edited)
  }

  private static func numbers(in text: String) -> [String] {
    let expression = try? NSRegularExpression(pattern: #"[-−]?\p{Nd}+(?:[.,:/−-]\p{Nd}+)*"#)
    let range = NSRange(text.startIndex ..< text.endIndex, in: text)
    return (expression?.matches(in: text, range: range) ?? []).compactMap { match in
      Range(match.range, in: text).map { String(text[$0]) }
    }.sorted()
  }
}
