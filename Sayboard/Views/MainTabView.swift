import SwiftUI

struct MainTabView: View {
  let isBehindOnboarding: Bool

  @SceneStorage("selectedTab") private var selectedTab = TabID.compose.rawValue
  @ObservedObject private var dictationLaunch = DictationLaunchRequest.shared

  private enum TabID: String {
    case compose
    case history
    case models
    case settings
  }

  var body: some View {
    Group {
      if #available(iOS 18.0, *) {
        self.modernTabs
      } else {
        self.legacyTabs
      }
    }
    .onOpenURL { self.handleDeepLink($0) }
    .onReceive(self.dictationLaunch.$pendingRequest) { request in
      if request != nil { self.selectedTab = TabID.compose.rawValue }
    }
    .onReceive(NotificationCenter.default.publisher(for: .dictationFailedNoModel)) { _ in
      self.selectedTab = TabID.compose.rawValue
    }
    .onReceive(NotificationCenter.default.publisher(for: .dictationFailedNoMic)) { _ in
      self.selectedTab = TabID.compose.rawValue
    }
  }

  @available(iOS 18.0, *)
  private var modernTabs: some View {
    TabView(selection: self.$selectedTab) {
      Tab("Compose", systemImage: "waveform", value: TabID.compose.rawValue) {
        NavigationStack { ComposeView() }
      }
      Tab("History", image: "tab-history", value: TabID.history.rawValue) {
        NavigationStack { HistoryListView() }
      }
      Tab("Models", image: "tab-models", value: TabID.models.rawValue) {
        NavigationStack { ModelsView().equatable() }
      }
      Tab("Settings", image: "tab-settings", value: TabID.settings.rawValue) {
        NavigationStack { SettingsView().equatable() }
      }
    }
  }

  private var legacyTabs: some View {
    TabView(selection: self.$selectedTab) {
      NavigationStack { ComposeView() }
        .tabItem { Label("Compose", systemImage: "waveform") }
        .tag(TabID.compose.rawValue)
      NavigationStack { HistoryListView() }
        .tabItem { Label("History", image: "tab-history") }
        .tag(TabID.history.rawValue)
      NavigationStack { ModelsView().equatable() }
        .tabItem { Label("Models", image: "tab-models") }
        .tag(TabID.models.rawValue)
      NavigationStack { SettingsView().equatable() }
        .tabItem { Label("Settings", image: "tab-settings") }
        .tag(TabID.settings.rawValue)
    }
  }

  private func handleDeepLink(_ url: URL) {
    guard url.scheme == DeepLink.scheme, !self.isBehindOnboarding else { return }
    switch url.host {
    case DeepLink.settingsHost, DeepLink.unlockHost:
      self.selectedTab = TabID.settings.rawValue
    case DeepLink.modelsHost:
      self.selectedTab = TabID.models.rawValue
    case DeepLink.dictateHost, DeepLink.setupMicHost, DeepLink.polishHost:
      self.selectedTab = TabID.compose.rawValue
    default:
      break
    }
  }
}
