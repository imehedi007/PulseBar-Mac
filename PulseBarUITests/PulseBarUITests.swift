import XCTest

final class PulseBarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMenuBarPopoverAndPause() throws {
        let app = XCUIApplication()
        app.launch()
        let status = app.statusItems.firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        status.click()

        let pause = app.buttons["PauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))

        // Check top metrics cards
        XCTAssertTrue(app.staticTexts["CPU"].exists)
        XCTAssertTrue(app.staticTexts["RAM"].exists)
        XCTAssertTrue(app.staticTexts["Network"].exists)

        // Pause / Resume cycle
        let original = pause.label
        pause.click()
        XCTAssertTrue(pause.wait(for: \.label, toEqual: original == "Pause" ? "Resume" : "Pause", timeout: 5))
        pause.click()
        XCTAssertTrue(pause.wait(for: \.label, toEqual: original, timeout: 5))
    }

    func testSettingsControlsAndToggles() throws {
        let app = XCUIApplication()
        app.launch()
        let status = app.statusItems.firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        status.click()

        let settingsBtn = app.buttons["Settings"]
        XCTAssertTrue(settingsBtn.waitForExistence(timeout: 5))
        settingsBtn.click()

        // Verify all settings controls appear
        XCTAssertTrue(app.staticTexts["Monitoring"].waitForExistence(timeout: 5))
        let cpuToggle = app.checkBoxes["CPU"]
        let memToggle = app.checkBoxes["Memory"]
        let netToggle = app.checkBoxes["Network"]
        XCTAssertTrue(cpuToggle.exists)
        XCTAssertTrue(memToggle.exists)
        XCTAssertTrue(netToggle.exists)

        // Dropdowns / Popups
        XCTAssertTrue(app.popUpButtons["CleaningDuration"].exists)
        XCTAssertTrue(app.popUpButtons["ClipboardLimit"].exists)

        // CPU threshold section
        XCTAssertTrue(app.staticTexts["CPU thresholds"].exists)

        // Other options
        XCTAssertTrue(app.checkBoxes["Start monitoring automatically"].exists)
        XCTAssertTrue(app.checkBoxes["Launch at login"].exists)

        let restoreBtn = app.buttons["Restore Defaults"]
        XCTAssertTrue(restoreBtn.exists)
        restoreBtn.click()

        // Hide settings
        let hideSettingsBtn = app.buttons["Settings"]
        hideSettingsBtn.click()
    }

    func testKeyboardCleaningAndClipboardToggles() throws {
        let app = XCUIApplication()
        app.launch()
        let status = app.statusItems.firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        status.click()

        // Keyboard cleaning toggle existence
        let cleaningToggle = app.descendants(matching: .any)["KeyboardCleaning"].firstMatch
        XCTAssertTrue(cleaningToggle.waitForExistence(timeout: 5))

        // Clipboard history toggle & status
        let clipboardToggle = app.descendants(matching: .any)["ClipboardHistory"].firstMatch
        XCTAssertTrue(clipboardToggle.waitForExistence(timeout: 5))
        let statusText = app.staticTexts["ClipboardStatusText"]
        XCTAssertTrue(statusText.exists)

        // Open clipboard spotlight panel button
        let openPanelBtn = app.buttons["OpenClipboardPanel"]
        if openPanelBtn.waitForExistence(timeout: 3) {
            openPanelBtn.click()

            let searchField = app.textFields["ClipboardSearchField"]
            if searchField.waitForExistence(timeout: 3) {
                searchField.typeText("Test")
                XCTAssertEqual(searchField.value as? String, "Test")
                app.typeKey(.escape, modifierFlags: [])
            }
        }
    }
}
