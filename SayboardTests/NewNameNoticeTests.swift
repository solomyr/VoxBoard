import Foundation
import Testing
@testable import Sayboard

@Suite("Announcing the new name once")
struct NewNameNoticeTests {

  @Test
  func `an install set up before the update sees the notice`() throws {
    let notice = try NewNameNotice(defaults: Self.makeDefaults(onboardingCompleted: true))
    notice.settleAtLaunch()
    #expect(notice.isDue)
  }

  @Test
  func `the notice stays across launches until it is dismissed`() throws {
    let notice = try NewNameNotice(defaults: Self.makeDefaults(onboardingCompleted: true))
    notice.settleAtLaunch()
    notice.settleAtLaunch()
    #expect(notice.isDue)
    notice.markDone()
    #expect(!notice.isDue)
  }

  @Test
  func `a new install does not see the notice once its onboarding is finished`() throws {
    let defaults = try Self.makeDefaults(onboardingCompleted: false)
    let notice = NewNameNotice(defaults: defaults)
    notice.settleAtLaunch()
    defaults.set(true, forKey: Self.onboardingCompletedKey)
    notice.settleAtLaunch()
    #expect(!notice.isDue)
  }

  @Test
  func `an install still in its onboarding is not due`() throws {
    let notice = try NewNameNotice(defaults: Self.makeDefaults(onboardingCompleted: false))
    #expect(!notice.isDue)
  }

  private static let onboardingCompletedKey = "hasCompletedOnboarding"

  private static func makeDefaults(onboardingCompleted: Bool) throws -> UserDefaults {
    let suiteName = "app.voxboard.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(onboardingCompleted, forKey: Self.onboardingCompletedKey)
    return defaults
  }
}
