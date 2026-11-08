import Foundation
import Testing
@testable import Sayboard

@Suite("VoxBoard composition")
struct VoxBoardFlowTests {
  @Test
  func `the app registers the same dictation link used by the keyboard`() throws {
    let types = try #require(Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]])
    let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    #expect(schemes.contains(Sayboard.DeepLink.scheme))
  }
  @Test
  func `a fresh install enables automatic ready to send cleanup`() throws {
    let name = "app.voxboard.tests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = SharedSettings(defaults: defaults)
    #expect(settings.llmEnabled)
    #expect(settings.defaultLLMActionSelection == .preset(.readyToSend))
    #expect(settings.retentionPolicy == .past24Hours)
    settings.llmEnabled = false
    settings.defaultLLMActionSelection = .none
    #expect(!settings.llmEnabled)
    #expect(settings.defaultLLMActionSelection == .none)
  }

  @Test
  func `a message and its original survive a restart and clear together`() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ComposeDraftStore(directory: directory)
    let draft = ComposeDraft(text: "Здравей! Meet me at 18:30. 你好 👋", original: "здравей meet me at 18:30 你好 👋")
    try store.save(draft)
    #expect(try ComposeDraftStore(directory: directory).load() == draft)
    try store.save(ComposeDraft(text: "", original: ""))
    #expect(try store.load() == nil)
  }

  @Test
  func `every Whisper variant has its tokenizer available without a download`() throws {
    for variant in [Sayboard.ModelVariant.whisperTiny, .whisperBase, .whisperSmall, .whisperTurbo] {
      let folder = try #require(WhisperKitTranscriptionService.tokenizerFolder(for: variant))
      let json = try Data(contentsOf: folder.appendingPathComponent("tokenizer.json"))
      #expect(!json.isEmpty)
    }
  }

  @Test
  func `bundled model catalog is complete and uses checksummed HTTPS archives`() async throws {
    let manifest = try await ManifestFetcher.fetch()
    for variant in Sayboard.ModelVariant.allCases {
      let entry = try #require(manifest.entry(for: variant))
      #expect(entry.engine == variant.engine)
      #expect(entry.url.scheme == "https")
      #expect(entry.sha256.count == 64)
      #expect(entry.sizeBytes > 0)
    }
    for variant in Sayboard.LLMModelVariant.allCases {
      let entry = try #require(manifest.llmEntry(for: variant))
      #expect(entry.url.scheme == "https")
      #expect(entry.sha256.count == 64)
      #expect(entry.isLoadableByThisBuild)
    }
  }
}
