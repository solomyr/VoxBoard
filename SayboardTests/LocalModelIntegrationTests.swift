import Foundation
import Testing
import WhisperKit
@testable import Sayboard

// These tests use real model weights, never mocks or network inference.
// Seed the simulator as described in README.md; otherwise they are skipped.
@Suite("Real on-device models", .serialized)
struct LocalModelIntegrationTests {
  @Test(.enabled(if: LLMModelStorageManager.isDownloaded(.qwen35Small)))
  @MainActor
  func `local cleanup preserves multilingual characters and numeric facts`() async throws {
    try await self.checkMultilingualCleanup(variant: .qwen35Small)
  }

  @Test(.enabled(if: LLMModelStorageManager.isDownloaded(.qwen35Large)))
  @MainActor
  func `larger local model preserves multilingual text and numeric facts`() async throws {
    try await self.checkMultilingualCleanup(variant: .qwen35Large)
  }

  @MainActor
  private func checkMultilingualCleanup(variant: Sayboard.LLMModelVariant) async throws {
    let service = LLMInferenceService()
    let path = try #require(LLMModelStorageManager.modelFileURL(for: variant))
    await service.loadModel(variant: variant, path: path.path)
    defer { service.unloadModel() }
    #expect(service.loadState == .loaded)
    let inputs = [
      "hello Maria we will meet at 18:30 tomorrow please bring 2 books",
      "утре ще се видим в 18:30 моля донеси 2 книги",
      "明日の18:30に会いましょう資料を2部持ってきてください",
      "nos vemos mañana a las 18:30 por favor trae 2 libros",
      "نلتقي غدا الساعة 18:30 من فضلك أحضر 2 كتب",
      "Здравей Maria, see you at 18:30, донеси 2 книги",
    ]
    for input in inputs {
      let result = try #require(await service.process(
        systemPrompt: LLMPromptTemplates.systemPrompt(for: .readyToSend, language: nil),
        userText: input,
      ))
      #expect(result.contains("18:30"), "\(result)")
      #expect(result.contains("2"), "\(result)")
      #expect(!result.contains("\u{FFFD}"), "UTF-8 corruption in \(result)")
      if input.contains("книги") { #expect(result.range(of: "[А-Яа-я]", options: .regularExpression) != nil) }
      if input.contains("明日") { #expect(result.contains("明日")) }
      #expect(ReadyToSendValidation.preservesNumbers(original: input, edited: result))
      print("VoxBoard \(variant.displayName): \(input) → \(result)")
    }
  }

  @Test(.enabled(if: (ModelStorageManager.isDownloaded(.whisperTiny) || ModelStorageManager.isDownloaded(.whisperSmall)) && FileManager.default.fileExists(atPath: Self.audioFixture.path)))
  @MainActor
  func `local speech transcription feeds local text cleanup`() async throws {
    URLProtocol.registerClass(OfflineModelTestProtocol.self)
    defer { URLProtocol.unregisterClass(OfflineModelTestProtocol.self) }
    let speech = WhisperKitTranscriptionService()
    let speechVariant: Sayboard.ModelVariant = ModelStorageManager.isDownloaded(.whisperSmall) ? .whisperSmall : .whisperTiny
    let directory = ModelStorageManager.directory(for: speechVariant).appendingPathComponent(speechVariant.rawValue)
    await speech.loadModel(variant: speechVariant, from: directory.path)
    #expect(speech.loadState == .loaded)
    let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: Self.audioFixture.path)
    let transcription = await speech.transcribe(audioSamples: samples)
    await speech.unloadModel()
    guard case .text(let output) = transcription else {
      Issue.record("Speech recognition produced no text: \(transcription)")
      return
    }
    #expect(output.text.lowercased().contains("meeting"), "\(output.text)")
    #expect(output.text.lowercased().contains("tomorrow"), "\(output.text)")
    let textVariant: Sayboard.LLMModelVariant = LLMModelStorageManager.isDownloaded(.qwen35Large) ? .qwen35Large : .qwen35Small
    let model = try #require(LLMModelStorageManager.modelFileURL(for: textVariant))
    let llm = LLMInferenceService()
    await llm.loadModel(variant: textVariant, path: model.path)
    defer { llm.unloadModel() }
    let polished = try #require(await llm.process(
      systemPrompt: LLMPromptTemplates.systemPrompt(for: .readyToSend, language: nil),
      userText: output.text,
    ))
    #expect(polished.lowercased().contains("meeting"))
    #expect(polished.lowercased().contains("tomorrow"))
    print("VoxBoard offline speech-to-text-to-LLM: \(output.text) → \(polished)")
  }

  private static var audioFixture: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("voxboard-test-dictation.aiff")
  }
}

private final class OfflineModelTestProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with _: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
  }
  override func stopLoading() { }
}
