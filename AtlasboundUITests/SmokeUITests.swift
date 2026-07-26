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
        // Avoid first-run permission races; CI also grants via simctl.
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()

        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            let buttons = ["Allow While Using App", "Allow Once", "Allow", "OK"]
            for title in buttons where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        // Nudge the app so the interruption monitor can fire.
        app.tap()
        dismissLocationAlertIfNeeded()
    }

    func testLaunchShowsTabBar() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 12), "Tab bar should appear after launch")
        XCTAssertTrue(tabBar.buttons["Map"].exists || tabBar.buttons["Activity"].exists)
    }

    func testActivityTabListsTypes() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12))
        let activityTab = app.tabBars.buttons["Activity"]
        XCTAssertTrue(activityTab.waitForExistence(timeout: 5))
        activityTab.tap()

        XCTAssertTrue(
            app.navigationBars["Activity"].waitForExistence(timeout: 8)
                || app.staticTexts["Activity"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["Walk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Run"].exists)
        XCTAssertTrue(app.staticTexts["Drive"].exists)
    }

    func testProgressTabShowsExplorerSection() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12))
        let progressTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progressTab.waitForExistence(timeout: 5))
        progressTab.tap()

        XCTAssertTrue(
            app.navigationBars["Progress"].waitForExistence(timeout: 8)
                || app.staticTexts["Progress"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts["Discovery XP"].waitForExistence(timeout: 5)
                || app.staticTexts["Explorer"].waitForExistence(timeout: 2)
        )
    }

    func testOpenSettingsFromMapIfAvailable() throws {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12))
        app.tabBars.buttons["Map"].tap()

        let settings = firstExisting(
            app.buttons["settingsButton"],
            app.buttons["Settings"],
            app.descendants(matching: .any)["settingsButton"]
        )

        guard settings.waitForExistence(timeout: 10) else {
            // MapKit / location denial can hide map chrome on some simulators — Activity tab still covers smoke.
            throw XCTSkip("Map settings control not available in this simulator session")
        }

        settings.tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 5)
                || app.staticTexts["Reveal width"].waitForExistence(timeout: 3)
        )

        let done = firstExisting(app.buttons["settingsDone"], app.buttons["Done"])
        if done.waitForExistence(timeout: 3) {
            done.tap()
        }
    }

    private func firstExisting(_ elements: XCUIElement...) -> XCUIElement {
        elements.first ?? app.buttons.firstMatch
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
            if button.waitForExistence(timeout: 1.0) {
                button.tap()
                return
            }
        }
        for title in allowButtons {
            let button = app.alerts.buttons[title]
            if button.waitForExistence(timeout: 0.3) {
                button.tap()
                return
            }
        }
    }
}
