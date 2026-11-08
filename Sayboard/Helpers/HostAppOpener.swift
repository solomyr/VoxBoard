import UIKit

enum HostAppOpener {
  @MainActor
  static func open(bundleId: String) -> Bool {
    // AltBoard's automatic return path uses undocumented Launch Services.
    // Keep the names explicit and fail gracefully if iOS changes the API.
    guard !bundleId.isEmpty, bundleId != "app.voxboard", bundleId != "app.voxboard.keyboard",
      bundleId != "com.apple.springboard",
      let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type
    else { return false }
    let getter = NSSelectorFromString("defaultWorkspace")
    guard cls.responds(to: getter),
      let workspace = cls.perform(getter)?.takeUnretainedValue() as? NSObject
    else { return false }
    let selector = NSSelectorFromString("openApplicationWithBundleID:")
    guard workspace.responds(to: selector) else { return false }
    typealias OpenApplication = @convention(c) (NSObject, Selector, NSString) -> Bool
    let open = unsafeBitCast(workspace.method(for: selector), to: OpenApplication.self)
    return open(workspace, selector, bundleId as NSString)
  }
}
