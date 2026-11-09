import XCTest

@MainActor
final class TypingKeyboardUITests: XCTestCase {
  func testTypingLanguagesShiftNumbersAndAccents() throws {
    self.continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    self.openPreview(in: app)
    self.chooseLanguage("en", in: app)
    for key in ["h", "e", "l", "l", "o"] { app.buttons["typing.key.\(key)"].firstMatch.tap() }
    app.buttons["typing.space"].tap()
    self.chooseLanguage("bg-phonetic", in: app)
    for key in ["з", "д", "р", "а", "в", "е", "й"] { app.buttons["typing.key.\(key)"].firstMatch.tap() }
    XCTAssertEqual(app.staticTexts["keyboard.preview.text"].label, "Hello здравей")
    app.buttons["typing.shift"].tap()
    app.buttons["typing.key.щ"].tap()
    XCTAssertEqual(app.staticTexts["keyboard.preview.text"].label, "Hello здравейЩ")
    app.buttons["typing.delete"].tap()
    app.buttons["typing.numbers"].tap()
    for key in ["1", "2", "3"] { app.buttons["typing.key.\(key)"].tap() }
    XCTAssertEqual(app.staticTexts["keyboard.preview.text"].label, "Hello здравей123")
    self.chooseLanguage("bg-bds", in: app)
    XCTAssertTrue(app.buttons["typing.key.й"].exists)
    self.chooseLanguage("fr", in: app)
    app.buttons["typing.key.e"].press(forDuration: 1)
    app.buttons["é"].tap()
    XCTAssertEqual(app.staticTexts["keyboard.preview.text"].label, "Hello здравей123é")
    self.chooseLanguage("bg-phonetic", in: app)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "VoxBoard Bulgarian typing keyboard"
    attachment.lifetime = .keepAlways
    add(attachment)
    self.chooseLanguage("en", in: app)
  }

  func testSwipeTypesAWord() throws {
    self.continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    self.openPreview(in: app)
    self.chooseLanguage("en", in: app)
    let text = app.staticTexts["keyboard.preview.text"]
    let before = text.label
    let start = app.buttons["typing.key.t"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let end = app.buttons["typing.key.o"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 600, thenHoldForDuration: 0.05)
    let typed = NSPredicate(format: "label != %@", before)
    expectation(for: typed, evaluatedWith: text)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(text.label.lowercased().hasSuffix("to "), "Swiped words end with a space: '\(text.label)'")
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Swipe typing"
    attachment.lifetime = .keepAlways
    add(attachment)
    // Delete right after a swipe removes the whole word.
    app.buttons["typing.delete"].tap()
    XCTAssertEqual(text.label, before)
  }

  func testManySwipesInARowEachTypeAWord() throws {
    self.continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    self.openPreview(in: app)
    self.chooseLanguage("en", in: app)
    let text = app.staticTexts["keyboard.preview.text"]
    for round in 1 ... 8 {
      let before = text.label
      let start = app.buttons["typing.key.t"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      let end = app.buttons["typing.key.o"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 600, thenHoldForDuration: 0.05)
      let typed = NSPredicate(format: "label != %@", before)
      expectation(for: typed, evaluatedWith: text)
      waitForExpectations(timeout: 5)
      XCTAssertGreaterThan(text.label.count, before.count, "Swipe \(round) typed nothing")
    }
  }

  /// Swipes that start on keys with accent menus (o, i, a) used to be swallowed.
  func testBackToBackSwipesFromAccentKeys() throws {
    self.continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    self.openPreview(in: app)
    self.chooseLanguage("en", in: app)
    let text = app.staticTexts["keyboard.preview.text"]
    for (from, to) in [("o", "n"), ("i", "s"), ("a", "s"), ("o", "n")] {
      let before = text.label.count
      let start = app.buttons["typing.key.\(from)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      let end = app.buttons["typing.key.\(to)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      start.press(forDuration: 0.01, thenDragTo: end, withVelocity: 800, thenHoldForDuration: 0.02)
      let grew = NSPredicate { _, _ in MainActor.assumeIsolated { text.label.count > before } }
      XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: grew, object: nil)], timeout: 4), .completed,
                     "Swipe from \(from) typed nothing: \(text.label)")
    }
  }

  func testOneHandedModeShrinksKeysToEitherSide() throws {
    self.continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    self.openPreview(in: app)
    self.chooseLanguage("en", in: app)
    let fullWidth = app.buttons["typing.key.p"].frame.maxX
    app.buttons["typing.languages"].tap()
    app.buttons["typing.oneHanded.left"].tap()
    XCTAssertTrue(app.buttons["typing.oneHanded.move"].waitForExistence(timeout: 2))
    XCTAssertLessThan(app.buttons["typing.key.p"].frame.maxX, fullWidth - 40)
    app.buttons["typing.key.h"].tap()
    let left = XCTAttachment(screenshot: app.screenshot())
    left.name = "One-handed left"
    left.lifetime = .keepAlways
    add(left)
    app.buttons["typing.oneHanded.move"].tap()
    XCTAssertGreaterThan(app.buttons["typing.key.q"].frame.minX, 40)
    app.buttons["typing.key.i"].tap()
    XCTAssertTrue(app.staticTexts["keyboard.preview.text"].label.hasSuffix("hi") || app.staticTexts["keyboard.preview.text"].label.hasSuffix("Hi"))
    let right = XCTAttachment(screenshot: app.screenshot())
    right.name = "One-handed right"
    right.lifetime = .keepAlways
    add(right)
    app.buttons["typing.oneHanded.toggle"].tap()
    XCTAssertFalse(app.buttons["typing.oneHanded.move"].exists)
    XCTAssertEqual(app.buttons["typing.key.p"].frame.maxX, fullWidth, accuracy: 1)
  }

  func testInstalledKeyboardTypesAlongsideMicrophone() throws {
    self.continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    self.openPreview(in: app)
    app.switches["keyboard.preview.installed"].tap()
    let editor = app.textViews["keyboard.preview.systemText"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    self.selectInstalledKeyboard(in: app)
    self.chooseLanguage("en", in: app)
    if app.buttons["typing.shift"].value as? String == "Lowercase" { app.buttons["typing.shift"].tap() }
    for key in ["h", "i"] { app.buttons["typing.key.\(key)"].tap() }
    app.buttons["typing.space"].tap()
    self.chooseLanguage("bg-phonetic", in: app)
    for key in ["д", "а"] { app.buttons["typing.key.\(key)"].tap() }
    XCTAssertEqual(editor.value as? String, "Hi да")
    XCTAssertTrue(app.buttons["typing.microphone"].isHittable)
    app.buttons["typing.delete"].tap()
    XCTAssertEqual(editor.value as? String, "Hi д")
    self.chooseLanguage("fr", in: app)
    app.buttons["typing.key.e"].press(forDuration: 1)
    app.buttons["é"].tap()
    XCTAssertEqual(editor.value as? String, "Hi дé")
    self.chooseLanguage("bg-phonetic", in: app)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Installed VoxBoard keyboard with English and Bulgarian"
    attachment.lifetime = .keepAlways
    add(attachment)
    self.chooseLanguage("en", in: app)
  }

  private func selectInstalledKeyboard(in app: XCUIApplication) {
    if app.buttons["typing.microphone"].waitForExistence(timeout: 2) { return }
    let globe = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@", "Next keyboard")).firstMatch
    if globe.exists {
      globe.press(forDuration: 1)
      let keyboard = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@", "VoxBoard")).firstMatch
      if keyboard.waitForExistence(timeout: 3) { keyboard.tap() }
      else {
        let label = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[cd] %@", "VoxBoard")).firstMatch
        if label.exists { label.tap() }
      }
    }
    XCTAssertTrue(app.buttons["typing.microphone"].waitForExistence(timeout: 5), app.debugDescription)
  }

  private func openPreview(in app: XCUIApplication) {
    let tab = app.tabBars.buttons["Settings"]
    let settings = tab.exists ? tab : app.buttons["Settings"].firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 15))
    settings.tap()
    let keyboard = app.buttons["settings.keyboard"]
    for _ in 0 ..< 5 {
      if keyboard.isHittable { break }
      app.swipeUp()
    }
    keyboard.tap()
    app.buttons["keyboard.preview.open"].tap()
    XCTAssertTrue(app.buttons["typing.languages"].waitForExistence(timeout: 5))
  }

  private func chooseLanguage(_ language: String, in app: XCUIApplication) {
    app.buttons["typing.languages"].tap()
    app.buttons["typing.language.\(language)"].tap()
  }
}
