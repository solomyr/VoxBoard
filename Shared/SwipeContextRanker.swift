import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Picks the swipe candidate that fits the sentence, using Apple's on-device
/// language model (Apple Intelligence). Runs out of process, so it does not
/// count against the keyboard's memory limit. Returns nil whenever the model is
/// unavailable, does not support the language, or takes too long.
enum SwipeContextRanker {
  static func choose(context: String, candidates: [String], language: KeyboardLanguage) async -> String? {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      return await self.chooseWithSystemModel(context: context, candidates: candidates, language: language)
    }
    #endif
    return nil
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, *)
  private static func chooseWithSystemModel(context: String, candidates: [String], language: KeyboardLanguage) async -> String? {
    let model = SystemLanguageModel.default
    guard case .available = model.availability, model.supportsLocale(language.locale) else { return nil }
    var seen = Set<String>()
    let options = candidates.filter { seen.insert($0.lowercased(with: language.locale)).inserted }
    guard options.count > 1 else { return nil }
    // Small models judge whole sentences far better than lone words.
    let recent = context.split(separator: " ", omittingEmptySubsequences: true).suffix(12).joined(separator: " ")
    let sentences = options.map { "\(recent) \($0)" }
    let session = LanguageModelSession(
      model: model,
      instructions: "You help a phone keyboard guess what a person typed. Pick the sentence that is the most natural, grammatical and likely thing to write. Answer with that sentence exactly.",
    )
    let schema: GenerationSchema
    do {
      schema = try GenerationSchema(root: DynamicGenerationSchema(name: "Sentence", anyOf: sentences), dependencies: [])
    } catch {
      return nil
    }
    let prompt = "Which of these did the person most likely mean?\n" + sentences.map { "- \($0)" }.joined(separator: "\n")
    do {
      let response = try await session.respond(
        to: prompt, schema: schema, includeSchemaInPrompt: false,
        options: GenerationOptions(samplingMode: .greedy),
      )
      let sentence = try response.content.value(String.self)
      guard let index = sentences.firstIndex(of: sentence) else { return nil }
      return options[index]
    } catch {
      return nil
    }
  }
  #endif
}
