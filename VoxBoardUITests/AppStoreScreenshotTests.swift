import XCTest

/// Captures App Store screenshots. Run on an iPhone 6.9" and an iPad 13" simulator.
@MainActor
final class AppStoreScreenshotTests: XCTestCase {
  func testCaptureAppStoreScreenshots() throws {
    self.continueAfterFailure = true
    let app = XCUIApplication()
    app.launch()

    // 1. Compose with a polished message (download the suggested models first).
    self.tab("Compose", app)
    let downloads = app.buttons.matching(NSPredicate(format: "label == %@", "Download"))
    for _ in 0 ..< 8 where downloads.count > 0 {
      let button = downloads.firstMatch
      if !button.isHittable { app.swipeUp() }
      if button.isHittable { button.tap() }
      sleep(1)
    }
    app.swipeDown()
    let record = app.buttons["compose.record"]
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: record)
    let textHint = app.staticTexts["Download a text model above to enable polishing. Dictation works on its own."]
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: textHint)
    waitForExpectations(timeout: 900)
    let draft = app.textViews["compose.draft"]
    if draft.waitForExistence(timeout: 10) {
      if app.buttons["compose.clear"].exists { app.buttons["compose.clear"].tap() }
      draft.tap()
      draft.typeText("Hi Maria! I'll be there at 6:30 tonight. Could you save me a seat near the window? Thanks!")
      if app.buttons["Done"].exists { app.buttons["Done"].tap() }
    }
    self.snap(app, "01-compose")

    // 2-5. The VoxBoard keyboard: swipe suggestions, one-handed, Bulgarian.
    self.tab("Settings", app)
    let keyboardSettings = app.buttons["settings.keyboard"]
    for _ in 0 ..< 5 where !keyboardSettings.isHittable { app.swipeUp() }
    keyboardSettings.tap()
    app.buttons["keyboard.preview.open"].tap()
    XCTAssertTrue(app.buttons["typing.languages"].waitForExistence(timeout: 5))
    self.language("en", app)
    for key in "see you" { app.buttons[key == " " ? "typing.space" : "typing.key.\(key)"].firstMatch.tap() }
    let start = app.buttons["typing.key.t"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let middle = app.buttons["typing.key.o"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: middle, withVelocity: 500, thenHoldForDuration: 0.05)
    sleep(1)
    self.snap(app, "02-swipe")
    app.buttons["typing.oneHanded.toggle"].tap()
    self.snap(app, "03-one-handed")
    app.buttons["typing.oneHanded.toggle"].tap()
    if app.buttons["Clear preview"].exists { app.buttons["Clear preview"].tap() }
    self.language("bg-phonetic", app)
    for key in "здравей" { app.buttons["typing.key.\(key)"].firstMatch.tap() }
    self.snap(app, "04-bulgarian")
    self.language("en", app)

    // 5. History of recordings.
    app.navigationBars.buttons.firstMatch.tap()
    app.navigationBars.buttons.firstMatch.tap()
    self.tab("History", app)
    sleep(1)
    self.snap(app, "05-history")

    // 6. Local models.
    self.tab("Models", app)
    sleep(1)
    self.snap(app, "06-models")
  }

  private func tab(_ name: String, _ app: XCUIApplication) {
    let bar = app.tabBars.buttons[name]
    (bar.exists ? bar : app.buttons[name].firstMatch).tap()
  }

  private func language(_ code: String, _ app: XCUIApplication) {
    app.buttons["typing.languages"].tap()
    app.buttons["typing.language.\(code)"].tap()
  }

  private func snap(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
