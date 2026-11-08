import Foundation

enum KeyboardKind: String, CaseIterable, Sendable {
  case standard
  case extended

  var displayNameKey: String {
    switch self {
    case .standard: "Typing + Voice"
    case .extended: "Voice + Symbols"
    }
  }
}
