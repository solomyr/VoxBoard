import Foundation

struct ComposeDraft: Codable, Equatable {
  var text: String
  var original: String
}

struct ComposeDraftStore {
  init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
    self.fileURL = directory.appendingPathComponent("compose-draft.json")
  }

  let fileURL: URL

  func load() throws -> ComposeDraft? {
    guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return nil }
    return try JSONDecoder().decode(ComposeDraft.self, from: Data(contentsOf: self.fileURL))
  }

  func save(_ draft: ComposeDraft) throws {
    if draft.text.isEmpty, draft.original.isEmpty {
      if FileManager.default.fileExists(atPath: self.fileURL.path) {
        try FileManager.default.removeItem(at: self.fileURL)
      }
      return
    }
    try FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(draft).write(to: self.fileURL, options: [.atomic, .completeFileProtection])
  }
}
