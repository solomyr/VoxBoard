import SwiftUI

@main
struct VoxBoardWatchApp: App {
  var body: some Scene {
    WindowGroup {
      NavigationStack { DictationView() }
    }
  }
}
