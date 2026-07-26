import XCTest

final class SmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryM",
        ]
        app.launch()
        dismissLocationAlertIfNeeded()
    }

    func testLaunchShowsMapChrome() {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8), "Settings gear should appear on map")

        let activityPicker = app.buttons["activityPickerButton"]
        XCTAssertTrue(activityPicker.waitForExistence(timeout: 5), "Activity picker entry should exist")
    }

    func testOpenActivityPickerAndClose() {
        let activityPicker = app.buttons["activityPickerButton"]
        XCTAssertTrue(activityPicker.waitForExistence(timeout: 8))
        activityPicker.tap()

        let walk = app.staticTexts["Walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: 5), "Activity list should show Walk")
        XCTAssertTrue(app.staticTexts["Cycle"].exists)

        let close = app.buttons["activityPickerClose"]
        if close.waitForExistence(timeout: 2) {
            close.tap()
        } else {
            app.buttons["Close"].tap()
        }

        XCTAssertTrue(app.buttons["activityPickerButton"].waitForExistence(timeout: 5))
    }

    func testOpenSettingsSheet() {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reveal width"].waitForExistence(timeout: 3))

        let done = app.buttons["settingsDone"]
        if done.waitForExistence(timeout: 2) {
            done.tap()
        } else {
            app.buttons["Done"].tap()
        }
    }

    func testActivityTabListsTypes() {
        let activityTab = app.tabBars.buttons["Activity"]
        XCTAssertTrue(activityTab.waitForExistence(timeout: 8))
        activityTab.tap()

        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Walk"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Run"].exists)
        XCTAssertTrue(app.staticTexts["Drive"].exists)
    }

    private func dismissLocationAlertIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButtons = [
            "Allow While Using App",
            "Allow Once",
            "Allow",
        ]
        for title in allowButtons {
            let button = springboard.buttons[title]
            if button.waitForExistence(timeout: 1.5) {
                button.tap()
                return
            }
        }

        // Also try in-app alert variants.
        for title in allowButtons {
            let button = app.alerts.buttons[title]
            if button.waitForExistence(timeout: 0.5) {
                button.tap()
                return
            }
        }
    }
}
