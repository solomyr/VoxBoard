import SwiftUI

struct FeedbackSection: View {
  var body: some View {
    Section {
      Text("VoxBoard is an independent open-source fork of AltBoard.")
      if let url = SupportLinks.upstreamURL {
        Link("Upstream source and license", destination: url)
      }
    } header: {
      Text("Open Source")
    } footer: {
      Text("VoxBoard processes voice and text on your device. Model downloads require an internet connection.")
    }
  }
}
