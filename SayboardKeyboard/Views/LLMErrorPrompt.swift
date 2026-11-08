
import SwiftUI

enum LLMError {
  case openAppSettings
  case polishFailed
  case noTextBeforeCursor

  var icon: String {
    switch self {
    case .openAppSettings: "gearshape"
    case .polishFailed: "exclamationmark.bubble"
    case .noTextBeforeCursor: "character.cursor.ibeam"
    }
  }

  var message: LocalizedStringKey {
    switch self {
    case .openAppSettings:
      "Open the VoxBoard app to change settings, then return here to continue dictating."
    case .polishFailed:
      "Polishing did not finish. Your original text has been kept. Review it before sending."
    case .noTextBeforeCursor:
      "To use AI actions, make sure the text field has text and the cursor is after it"
    }
  }

  var buttonTitle: LocalizedStringKey {
    switch self {
    case .openAppSettings: "OK"
    case .polishFailed: "OK"
    case .noTextBeforeCursor: "OK"
    }
  }
}

struct LLMErrorPrompt: View {

  let error: LLMError

  @ObservedObject var keyboardState: KeyboardState

  var body: some View {
    VStack(spacing: 12.kbScaled) {
      Image(systemName: self.error.icon)
        .font(.system(size: 40.kbScaled))
        .foregroundStyle(.blue)

      Text(self.error.message)
        .font(.subheadline.weight(.semibold))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32.kbScaled)

      Button {
        withAnimation(.easeOut(duration: 0.12)) { self.keyboardState.llmError = nil }
      } label: {
        Text(self.error.buttonTitle)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 20.kbScaled)
          .frame(minHeight: 40.kbScaled)
          .background(.blue, in: Capsule())
      }
      .padding(.horizontal, 32.kbScaled)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
