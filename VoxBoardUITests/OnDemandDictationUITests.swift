import XCTest

@MainActor
final class OnDemandDictationUITests: XCTestCase {
  func testBackgroundIntentProbe() throws {
    self.continueAfterFailure = false
    XCUIApplication().terminate()
    let host = XCUIApplication(bundleIdentifier: "dev.voxboard.keyboardfixture")
    host.launch()
    defer { XCUIApplication().terminate(); host.terminate() }
    XCTAssertTrue(host.textViews["fixture.text"].waitForExistence(timeout: 10))
    host.textViews["fixture.text"].tap()
    self.selectVoxBoard(in: host)
    let probe = host.buttons["typing.backgroundProbe"]
    XCTAssertTrue(probe.waitForExistence(timeout: 5))
    probe.tap()
    let ranInApp = NSPredicate(format: "value == %@", "app.voxboard")
    expectation(for: ranInApp, evaluatedWith: probe)
    waitForExpectations(timeout: 12)
    XCTAssertEqual(host.state, .runningForeground)
  }

  func testKeyboardMicProbe() throws {
    self.continueAfterFailure = false
    XCUIApplication().terminate()
    let host = XCUIApplication(bundleIdentifier: "dev.voxboard.keyboardfixture")
    host.launch()
    defer { host.terminate() }
    XCTAssertTrue(host.textViews["fixture.text"].waitForExistence(timeout: 10))
    host.textViews["fixture.text"].tap()
    self.selectVoxBoard(in: host)
    let probe = host.buttons["typing.micProbe"]
    XCTAssertTrue(probe.waitForExistence(timeout: 5))
    probe.tap()
    let done = NSPredicate(format: "NOT (value IN %@)", ["idle", "running"])
    expectation(for: done, evaluatedWith: probe)
    waitForExpectations(timeout: 10)
    let attachment = XCTAttachment(screenshot: host.screenshot())
    attachment.lifetime = .keepAlways
    add(attachment)
    print("MICPROBE RESULT: \(probe.value as? String ?? "nil") hostState=\(host.state.rawValue)")
  }

  func testKeyboardContextModelProbe() throws {
    self.continueAfterFailure = false
    let host = XCUIApplication(bundleIdentifier: "dev.voxboard.keyboardfixture")
    host.launch()
    defer { host.terminate() }
    XCTAssertTrue(host.textViews["fixture.text"].waitForExistence(timeout: 10))
    host.textViews["fixture.text"].tap()
    self.selectVoxBoard(in: host)
    let probe = host.buttons["typing.contextProbe"]
    XCTAssertTrue(probe.waitForExistence(timeout: 5))
    probe.tap()
    expectation(for: NSPredicate(format: "NOT (value IN %@)", ["idle", "running"]), evaluatedWith: probe)
    waitForExpectations(timeout: 30)
    print("CONTEXTPROBE RESULT: \(probe.value as? String ?? "nil")")
  }

  func testSwipeInInstalledKeyboard() throws {
    self.continueAfterFailure = true
    let host = XCUIApplication(bundleIdentifier: "dev.voxboard.keyboardfixture")
    host.launch()
    defer { host.terminate() }
    XCTAssertTrue(host.textViews["fixture.text"].waitForExistence(timeout: 10))
    host.buttons["Clear test text"].tap()
    host.textViews["fixture.text"].tap()
    self.selectVoxBoard(in: host)
    host.buttons["typing.languages"].tap()
    host.buttons["typing.language.en"].tap()
    host.buttons["typing.key.h"].tap()
    print("SWIPETEST after tap: \(host.textViews["fixture.text"].value as? String ?? "nil")")
    for (from, to) in [("t", "o"), ("o", "n"), ("i", "s")] {
      let start = host.buttons["typing.key.\(from)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      let end = host.buttons["typing.key.\(to)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 300, thenHoldForDuration: 0.05)
      sleep(2)
      print("SWIPETEST after \(from)\(to): \(host.textViews["fixture.text"].value as? String ?? "nil")")
    }
    let attachment = XCTAttachment(screenshot: host.screenshot())
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testOneHandedAndLanguageButtonsInInstalledKeyboard() throws {
    self.continueAfterFailure = true
    let host = XCUIApplication(bundleIdentifier: "dev.voxboard.keyboardfixture")
    host.launch()
    defer { host.terminate() }
    XCTAssertTrue(host.textViews["fixture.text"].waitForExistence(timeout: 10))
    host.textViews["fixture.text"].tap()
    self.selectVoxBoard(in: host)
    let toggle = host.buttons["typing.oneHanded.toggle"]
    print("BTNTEST toggle frame \(toggle.frame) hittable \(toggle.isHittable)")
    toggle.tap()
    let expand = host.buttons["typing.oneHanded.move"]
    print("BTNTEST after toggle: expand exists \(expand.waitForExistence(timeout: 3)) frame \(expand.frame)")
    let q1 = host.buttons["typing.key.q"].frame
    host.buttons["typing.oneHanded.move"].tap(); sleep(1)
    print("BTNTEST move: q before \(q1) after \(host.buttons["typing.key.q"].frame)")
    let shot = XCTAttachment(screenshot: host.screenshot()); shot.lifetime = .keepAlways; add(shot)
    expand.tap()
    sleep(1)
    print("BTNTEST after expand tap: expand exists \(expand.exists)")
    if expand.exists {
      toggle.tap(); sleep(1)
      print("BTNTEST after toggle again: expand exists \(expand.exists)")
    }
    host.buttons["typing.languages"].tap()
    if host.buttons["typing.oneHanded.left"].waitForExistence(timeout: 2) { host.buttons["typing.oneHanded.left"].tap() }
    sleep(1)
    print("BTNTEST left mode: expand \(expand.exists) frame \(expand.frame)")
    expand.tap(); sleep(1)
    print("BTNTEST right-strip expand tap: expand exists \(expand.exists)")
    if expand.exists { host.buttons["typing.oneHanded.toggle"].tap(); sleep(1) }
    let languages = host.buttons["typing.languages"]
    print("BTNTEST languages frame \(languages.frame)")
    languages.tap()
    print("BTNTEST picker opened \(host.buttons["typing.language.en"].waitForExistence(timeout: 2))")
    add(XCTAttachment(screenshot: host.screenshot()))
    if host.buttons["typing.language.en"].exists { host.buttons["typing.language.en"].tap() }
  }

  func testKeyboardHandsOffOnceThenRecordsInPlace() throws {
    self.continueAfterFailure = false
    let app = XCUIApplication()
    app.terminate()
    let host = XCUIApplication(bundleIdentifier: "dev.voxboard.keyboardfixture")
    host.launch()
    defer { app.terminate(); host.terminate() }
    XCTAssertTrue(host.textViews["fixture.text"].waitForExistence(timeout: 10))
    host.textViews["fixture.text"].tap()
    self.selectVoxBoard(in: host)
    XCTAssertTrue(host.staticTexts["Mic off"].waitForExistence(timeout: 10))

    for attempt in 1 ... 2 {
      let mic = host.buttons["typing.microphone"]
      mic.tap()
      let recording = host.buttons.matching(identifier: "typing.microphone")
        .matching(NSPredicate(format: "label == %@", "Stop dictation")).firstMatch
      XCTAssertTrue(recording.waitForExistence(timeout: 15), "Recording did not start (attempt \(attempt)).")
      if attempt > 1 {
        // With the session ready, the keyboard records in place: VoxBoard never comes forward.
        XCTAssertNotEqual(app.state, .runningForeground, "Second recording switched apps.")
        XCTAssertEqual(host.state, .runningForeground)
      }
      let settled = NSPredicate { _, _ in
        MainActor.assumeIsolated {
          host.state == .runningForeground && recording.exists && recording.isHittable
            && host.staticTexts["VoxBoard test field"].isHittable
        }
      }
      XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 10), .completed)
      let attachment = XCTAttachment(screenshot: host.screenshot())
      attachment.name = "Keyboard recording \(attempt)"
      attachment.lifetime = .keepAlways
      add(attachment)
      recording.tap()
      let finished = host.staticTexts["typing.status"]
      let ready = NSPredicate(format: "label == %@", "Mic active")
      expectation(for: ready, evaluatedWith: finished)
      waitForExpectations(timeout: 90)
      XCTAssertEqual(host.buttons["typing.microphone"].label, "Start dictation")
    }

    // The keyboard's mic-off button releases the microphone.
    host.buttons["typing.microphoneOff"].tap()
    let off = NSPredicate(format: "label == %@", "Mic off")
    expectation(for: off, evaluatedWith: host.staticTexts["typing.status"])
    waitForExpectations(timeout: 10)
  }

  func testManualCleanupWakesAppWithoutMicrophone() throws {
    self.continueAfterFailure = false
    let app = XCUIApplication()
    app.terminate()
    let host = XCUIApplication(bundleIdentifier: "dev.voxboard.keyboardfixture")
    host.launch()
    defer { app.terminate(); host.terminate() }
    XCTAssertTrue(host.textViews["fixture.text"].waitForExistence(timeout: 10))
    host.textViews["fixture.text"].tap()
    self.selectVoxBoard(in: host)
    XCTAssertTrue(host.staticTexts["Mic off"].waitForExistence(timeout: 10))

    // Manual text cleanup also wakes the main app on demand, without a mic session.
    host.buttons["Clear test text"].tap()
    host.buttons["typing.languages"].tap()
    host.buttons["typing.language.en"].tap()
    if host.buttons["typing.shift"].value as? String != "Lowercase" { host.buttons["typing.shift"].tap() }
    for key in "hello there" {
      host.buttons[key == " " ? "typing.space" : "typing.key.\(key)"].tap()
    }
    XCTAssertEqual(host.textViews["fixture.text"].value as? String, "hello there")
    XCTAssertTrue(host.buttons["typing.polish"].waitForExistence(timeout: 5), "Install the current app build before running cross-app tests.")
    host.buttons["typing.polish"].tap()
    let polished = NSPredicate { _, _ in
      MainActor.assumeIsolated {
        guard host.state == .runningForeground,
          let text = host.textViews["fixture.text"].value as? String else { return false }
        return text.hasPrefix("Hello") && text.trimmingCharacters(in: .punctuationCharacters).lowercased() == "hello there"
          && host.staticTexts["typing.status"].label == "Mic off"
      }
    }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: polished, object: nil)], timeout: 45), .completed)
    host.buttons["typing.languages"].tap()
    host.buttons["typing.language.bg-phonetic"].tap()
  }

  private func selectVoxBoard(in app: XCUIApplication) {
    if app.buttons["typing.microphone"].waitForExistence(timeout: 2) { return }
    let globe = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@", "Next keyboard")).firstMatch
    XCTAssertTrue(globe.exists)
    globe.press(forDuration: 1)
    let name = NSPredicate(format: "label CONTAINS[cd] %@", "VoxBoard")
    let button = app.buttons.matching(name).firstMatch
    if button.waitForExistence(timeout: 3) { button.tap() }
    else { app.staticTexts.matching(name).firstMatch.tap() }
    // If the menu tap did not switch keyboards, cycle with the globe key.
    for _ in 0 ..< 6 where !app.buttons["typing.microphone"].waitForExistence(timeout: 3) {
      let next = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@", "Next keyboard")).firstMatch
      guard next.exists else { break }
      next.tap()
    }
    XCTAssertTrue(app.buttons["typing.microphone"].waitForExistence(timeout: 20))
  }
}
