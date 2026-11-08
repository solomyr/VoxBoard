
import Foundation

struct LLMRequest: Codable, Sendable {
  let text: String
  let action: LLMAction
  let customPromptId: UUID?
  let language: String?
  var replacementContext: String? = nil
  var hostBundleId: String? = nil
}

/// Delivery metadata survives the keyboard controller being recreated during
/// the app handoff. A result can only replace the unchanged original context.
struct LLMResult: Codable, Sendable {
  let text: String
  let replacementContext: String?
  let hostBundleId: String?
}

struct LLMBridge: Sendable {

  static func writeRequest(_ request: LLMRequest) {
    guard let url = requestFileURL else { return }
    do {
      let data = try JSONEncoder().encode(request)
      try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    } catch { }
  }

  static func readRequest() -> LLMRequest? {
    guard let url = requestFileURL else { return nil }
    guard let data = try? Data(contentsOf: url) else {
      return nil
    }
    return try? JSONDecoder().decode(LLMRequest.self, from: data)
  }

  static func writeResult(_ text: String, replacing original: String? = nil, hostBundleId: String? = nil) {
    guard let url = resultFileURL else { return }
    do {
      let result = LLMResult(text: text, replacementContext: original, hostBundleId: hostBundleId)
      try JSONEncoder().encode(result).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    } catch { }
  }

  static func readResult() -> String? {
    self.readDelivery()?.text
  }

  static func readDelivery() -> LLMResult? {
    guard let url = resultFileURL else { return nil }
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(LLMResult.self, from: data)
  }

  static func clearRequest() {
    guard let url = requestFileURL else { return }
    try? FileManager.default.removeItem(at: url)
  }

  static func clearResult() {
    guard let url = resultFileURL else { return }
    try? FileManager.default.removeItem(at: url)
  }

  private static let requestFileName = "llm_request.json"
  private static let resultFileName = "llm_result.txt"

  private static var requestFileURL: URL? {
    AppGroup.containerURL?.appendingPathComponent(requestFileName)
  }

  private static var resultFileURL: URL? {
    AppGroup.containerURL?.appendingPathComponent(resultFileName)
  }
}
