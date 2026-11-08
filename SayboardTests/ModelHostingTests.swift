import CryptoKit
import Foundation
import Testing
@testable import Sayboard

@Suite("Model hosting")
struct ModelHostingTests {
  @Test
  func `every archive is hosted on VoxBoard's Hugging Face mirror`() throws {
    let url = try #require(Bundle.main.url(forResource: "model-manifest", withExtension: "json"))
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(!text.contains("models.sayboard.app"))
    #expect(text.contains("https://huggingface.co/devoar/voxboard-models/resolve/main/"))
  }

  /// Downloads the smallest archive through Hugging Face's redirect and checks its pinned hash.
  @Test
  func `the mirror serves archives that match the pinned checksum`() async throws {
    let manifestURL = try #require(Bundle.main.url(forResource: "model-manifest", withExtension: "json"))
    let manifest = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: manifestURL))
    let entry = try #require(manifest.models["moonshine-tiny-en"])
    let (file, response) = try await URLSession.shared.download(from: entry.url)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    let digest = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    #expect(digest == entry.sha256)
  }
}
