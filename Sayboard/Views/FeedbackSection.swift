import SwiftUI

struct FeedbackSection: View {
  var body: some View {
    Section {
      Text("VoxBoard is free software under the GNU GPL v3, built on the open-source AltBoard.")
      if let url = SupportLinks.sourceURL {
        Link("VoxBoard source code", destination: url)
      }
      if let url = SupportLinks.upstreamURL {
        Link("AltBoard (upstream project)", destination: url)
      }
      if let url = SupportLinks.modelsURL {
        Link("Model downloads and licenses", destination: url)
      }
    } header: {
      Text("Open Source")
    } footer: {
      Text("VoxBoard processes voice and text on your device. Model downloads require an internet connection.")
    }
  }
}
