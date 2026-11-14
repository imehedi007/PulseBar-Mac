import XCTest

final class PulseBarUITests: XCTestCase {
    @MainActor
    func testMenuBarPopoverAndPause() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let status = app.statusItems.firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        status.click()
        let pause = app.buttons["PauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        let original = pause.label
        pause.click()
        XCTAssertTrue(pause.wait(for: \.label, toEqual: original == "Pause" ? "Resume" : "Pause", timeout: 5))
        pause.click()
        XCTAssertTrue(pause.wait(for: \.label, toEqual: original, timeout: 5))
        app.buttons["Settings"].click()
        XCTAssertTrue(app.checkBoxes["Launch at login"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restore Defaults"].exists)
    }
}
