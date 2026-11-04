import XCTest

/// End-to-end tests on the simulator. They also produce the screenshots used in
/// docs/ (exported from the .xcresult by scripts/test-ui.sh).
final class ReaderUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Helpers

    private var deviceTag: String {
        let w = Int(app.windows.firstMatch.frame.width), h = Int(app.windows.firstMatch.frame.height)
        let kind = min(w, h) <= 768 ? "ipad-mini" : (min(w, h) >= 1000 ? "ipad-13in" : "ipad")
        return "\(kind)-\(w > h ? "landscape" : "portrait")"
    }

    private func screenshot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "\(name)-\(deviceTag)"
        a.lifetime = .keepAlways
        add(a)
    }

    private func launch(seed: Bool, reset: Bool = true) {
        var args: [String] = []
        if reset { args.append("-ui-testing") }
        if seed { args.append("-seed-samples") }
        app.launchArguments = args
        app.launch()
    }

    private func waitForBooks(_ names: [String], timeout: TimeInterval = 60) {
        for n in names {
            XCTAssertTrue(app.buttons["book.\(n)"].waitForExistence(timeout: timeout), "book \(n) did not appear")
        }
    }

    private func tapScreen(_ dx: CGFloat, _ dy: CGFloat = 0.5) {
        app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
    }

    private func showChrome() {
        let jump = app.buttons["reader.jump"]
        // Upper-middle: still the "center" tap zone, but clear of any centered status card.
        if !jump.exists { tapScreen(0.5, 0.22) }
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
    }

    private func hideChrome() {
        if app.buttons["reader.jump"].exists { tapScreen(0.5, 0.22) }
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["reader.jump"])
        waitForExpectations(timeout: 5)
    }

    /// Current page number (1-based) read from the toolbar's accessibility value.
    private func currentPage() -> Int {
        showChrome()
        let value = app.buttons["reader.jump"].value as? String ?? ""
        // "第 N 頁，共 M 頁"
        let digits = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return digits.first ?? -1
    }

    private func waitForPage(_ n: Int, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(8)
        var p = -1
        while Date() < deadline {
            p = currentPage()
            if p == n { return }
            usleep(300_000)
        }
        XCTFail("expected page \(n), got \(p)", file: file, line: line)
    }

    private func openBook(_ name: String) {
        let b = app.buttons["book.\(name)"]
        XCTAssertTrue(b.waitForExistence(timeout: 30))
        b.tap()
        let anyPage = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'reader.page.'")).firstMatch
        XCTAssertTrue(anyPage.waitForExistence(timeout: 30), "reader did not open")
    }

    private func waitForPreparation() {
        let prep = app.descendants(matching: .any)["reader.preparing"]
        if prep.exists {
            let gone = NSPredicate(format: "exists == false")
            expectation(for: gone, evaluatedWith: prep)
            waitForExpectations(timeout: 60)
        }
    }

    private func closeReader() {
        showChrome()
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
    }

    // MARK: Tests

    func test01EmptyLibrary() {
        launch(seed: false)
        XCTAssertTrue(app.buttons["library.empty.import"].waitForExistence(timeout: 10))
        screenshot("01-empty-library")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        screenshot("01-empty-library")
    }

    func test02ImportAndLibrary() {
        launch(seed: true)
        waitForBooks(["01 星之旅人 第1卷", "02 城市速寫", "03 長條漫畫"])
        sleep(1)
        screenshot("02-library")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        screenshot("02-library")
    }

    func test03LTRPagingZoomThumbnailsAndProgress() {
        launch(seed: true)
        waitForBooks(["02 城市速寫"])
        openBook("02 城市速寫")
        sleep(1)
        screenshot("03-reader")
        XCTAssertEqual(currentPage(), 1)
        hideChrome()

        // Tap right zone = next (LTR); left zone = previous.
        tapScreen(0.92)
        waitForPage(2)
        hideChrome()
        tapScreen(0.08)
        waitForPage(1)
        hideChrome()
        // First page boundary: previous does nothing.
        tapScreen(0.08)
        waitForPage(1)
        hideChrome()

        // Swipe left = next page.
        app.swipeLeft()
        waitForPage(2)
        hideChrome()

        // Double tap zooms; while zoomed, horizontal drags pan instead of turning.
        let page = app.descendants(matching: .any)["reader.page.1"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.doubleTap()
        sleep(1)
        screenshot("04-reader-zoomed")
        app.swipeLeft()
        app.swipeLeft()
        sleep(1)
        XCTAssertEqual(currentPage(), 2, "panning a zoomed page must not turn the page")
        hideChrome()
        page.doubleTap()
        sleep(1)
        // Pinch in then out.
        page.pinch(withScale: 2.5, velocity: 2)
        sleep(1)
        page.pinch(withScale: 0.3, velocity: -2)
        sleep(1)
        app.swipeLeft()
        waitForPage(3)

        // Thumbnails: jump to page 12.
        app.buttons["reader.thumbnails"].tap()
        let thumb = app.descendants(matching: .any)["thumb.11"]
        XCTAssertTrue(thumb.waitForExistence(timeout: 10))
        sleep(2)
        screenshot("05-thumbnails")
        thumb.tap()
        waitForPage(12)

        // Rapid taps never overshoot the last page.
        hideChrome()
        // (Extra taps: two taps in quick succession may be read as a double tap.)
        for _ in 0..<20 { tapScreen(0.95) }
        sleep(1)
        XCTAssertEqual(currentPage(), 16)
        hideChrome()
        tapScreen(0.08)
        waitForPage(15)

        // Landscape keeps the page.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        XCTAssertEqual(currentPage(), 15)
        hideChrome()
        screenshot("06-reader")

        // Double-page layout in landscape (P1).
        showChrome()
        app.buttons["reader.settings"].tap()
        let layout = app.segmentedControls["settings.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        layout.buttons.element(boundBy: 1).tap()
        app.buttons["readersettings.done"].tap()
        hideChrome()
        tapScreen(0.08); tapScreen(0.08); tapScreen(0.08)
        sleep(1)
        screenshot("07-reader-double-page")
        XCUIDevice.shared.orientation = .portrait
        sleep(1)

        // Progress is saved: reopen lands on the same page.
        let before = currentPage()
        closeReader()
        screenshot("08-library-continue")
        openBook("02 城市速寫")
        XCTAssertEqual(currentPage(), before)
    }

    func test04RTLAndDirectionSwitchKeepsPage() {
        launch(seed: true)
        waitForBooks(["01 星之旅人 第1卷"])
        openBook("01 星之旅人 第1卷")
        waitForPreparation()
        XCTAssertEqual(currentPage(), 1, "RTL books start on their first page, not the last")
        hideChrome()
        // RTL: the left side is "next".
        tapScreen(0.08)
        waitForPage(2)
        hideChrome()
        app.swipeRight()
        waitForPage(3)
        screenshot("09-reader-rtl")
        // Switch to LTR: same content page.
        app.buttons["reader.settings"].tap()
        let ltr = app.buttons["由左至右（美漫、條漫）"]
        XCTAssertTrue(ltr.waitForExistence(timeout: 5))
        ltr.tap()
        app.buttons["readersettings.done"].tap()
        XCTAssertEqual(currentPage(), 3)
        hideChrome()
        tapScreen(0.92)
        waitForPage(4)
        // Jump via page number entry.
        app.buttons["reader.jump"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("25")
        app.alerts.buttons["前往"].tap()
        waitForPage(25)
    }

    func test05ProgressSurvivesBackgroundAndRelaunch() {
        launch(seed: true)
        waitForBooks(["03 長條漫畫"])
        openBook("03 長條漫畫")
        hideChrome()
        tapScreen(0.92); tapScreen(0.92)
        waitForPage(3)
        hideChrome()
        // Go to background (no normal close of the reader), then kill the app.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()
        launch(seed: false, reset: false)
        XCTAssertTrue(app.buttons["library.continue"].waitForExistence(timeout: 15))
        let label = app.buttons["library.continue"].label
        XCTAssertTrue(label.contains("3 / 6"), label)
        app.buttons["library.continue"].tap()
        XCTAssertEqual(currentPage(), 3)
        // Fit width on tall strips: content scrolls vertically.
        app.buttons["reader.settings"].tap()
        app.segmentedControls["settings.fit"].buttons.element(boundBy: 1).tap()
        app.buttons["readersettings.done"].tap()
        hideChrome()
        app.swipeUp()
        sleep(1)
        screenshot("10-reader-fit-width-tall")
    }

    func test06RenameDeleteAndMenu() {
        launch(seed: true)
        waitForBooks(["03 長條漫畫"])
        app.buttons["book.menu.03 長條漫畫"].tap()
        app.buttons["重新命名"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("Webtoon")
        app.alerts.buttons["儲存"].tap()
        XCTAssertTrue(app.buttons["book.Webtoon"].waitForExistence(timeout: 5))
        app.buttons["book.menu.Webtoon"].tap()
        app.buttons["刪除"].tap()
        let confirm = app.sheets.buttons["刪除"].exists ? app.sheets.buttons["刪除"] : app.buttons["刪除"].firstMatch
        confirm.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["book.Webtoon"])
        waitForExpectations(timeout: 10)
        // Search.
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("城市")
        XCTAssertTrue(app.buttons["book.02 城市速寫"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["book.01 星之旅人 第1卷"].exists)
    }

    func test08VerticalScrollMode() {
        launch(seed: true)
        waitForBooks(["03 長條漫畫"])
        openBook("03 長條漫畫")
        showChrome()
        app.buttons["reader.settings"].tap()
        let layout = app.segmentedControls["settings.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        layout.buttons.element(boundBy: 2).tap()
        app.buttons["readersettings.done"].tap()
        XCTAssertEqual(currentPage(), 1)
        hideChrome()
        for _ in 0..<6 { app.swipeUp(velocity: .fast) }
        sleep(1)
        screenshot("11-reader-vertical")
        XCTAssertGreaterThan(currentPage(), 1, "scrolling should advance the logical page")
        // Jump keeps working in vertical mode.
        app.buttons["reader.jump"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("6")
        app.alerts.buttons["前往"].tap()
        waitForPage(6)
    }

    func test07RepeatedOpenClose() {
        launch(seed: true)
        waitForBooks(["01 星之旅人 第1卷", "02 城市速寫"])
        for i in 0..<5 {
            openBook(i % 2 == 0 ? "01 星之旅人 第1卷" : "02 城市速寫")
            waitForPreparation()
            hideChrome()
            for _ in 0..<4 { tapScreen(i % 2 == 0 ? 0.05 : 0.95) }
            closeReader()
        }
        XCTAssertTrue(app.buttons["library.continue"].exists)
    }
}

extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let v = value as? String, !v.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2))
        }
        typeText(text)
    }
}
