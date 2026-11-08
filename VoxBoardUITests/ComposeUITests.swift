import XCTest

// Run against a fresh development install with local models preloaded.
// These tests create and clear a sample draft; do not run on a user's working draft.
@MainActor
final class ComposeUITests: XCTestCase {
  func testComposePolishCopyShareAndPersistence() throws {
    self.continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let editor = app.textViews["compose.draft"]
    XCTAssertTrue(editor.waitForExistence(timeout: 15))
    XCTAssertEqual(editor.value as? String ?? "", "", "Use a fresh installation with no saved draft.")
    editor.tap()
    editor.typeText("hello Maria we will meet at 18:30 tomorrow please bring 2 books")
    app.buttons["Done"].tap()
    let polish = app.buttons["compose.polish"]
    self.reveal(polish, in: app)
    try XCTSkipUnless(polish.isEnabled, "Preload a local text model before this device test.")
    polish.tap()
    let completed = NSPredicate(format: "label CONTAINS %@", "Polished on-device")
    expectation(for: completed, evaluatedWith: app.staticTexts["compose.status"])
    waitForExpectations(timeout: 90)
    let polished = try XCTUnwrap(editor.value as? String)
    XCTAssertTrue(polished.contains("Maria"))
    XCTAssertTrue(polished.contains("18:30"))
    XCTAssertTrue(polished.contains("2"))
    let copy = app.buttons["compose.copy"]
    self.reveal(copy, in: app)
    copy.tap()
    XCTAssertTrue(copy.label.contains("Copied"))
    app.buttons["compose.share"].tap()
    XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5)
      || app.buttons["Copy"].waitForExistence(timeout: 5))
    // Relaunch also dismisses the share sheet, without choosing a destination or sending.
    app.terminate()
    app.launch()
    XCTAssertTrue(editor.waitForExistence(timeout: 15))
    XCTAssertEqual(editor.value as? String, polished)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "VoxBoard on-device composed message"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    let clear = app.buttons["compose.clear"]
    self.reveal(clear, in: app)
    clear.tap()
    XCTAssertEqual(editor.value as? String ?? "", "")
  }

  private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0 ..< 4 {
      if element.isHittable { return }
      app.swipeUp()
    }
  }
}
