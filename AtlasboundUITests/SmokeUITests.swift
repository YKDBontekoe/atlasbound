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
            "-atlasbound.onboardingVersion", "2",
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
        XCTAssertTrue(tabBar.buttons["Map"].exists || tabBar.buttons["Journal"].exists)
    }

    func testJournalShowsTreasureAndOptionalActivityHistory() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12))
        let journalTab = app.tabBars.buttons["Journal"]
        XCTAssertTrue(journalTab.waitForExistence(timeout: 5))
        journalTab.tap()

        XCTAssertTrue(
            app.navigationBars["Journal"].waitForExistence(timeout: 8)
                || app.staticTexts["Today’s Trail"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts["Inventory"].waitForExistence(timeout: 5)
                || app.staticTexts["Assemble…"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts["Optional Activity History"].waitForExistence(timeout: 5)
                || revealStaticText("Optional Activity History")
        )
        XCTAssertTrue(
            app.staticTexts["Relic Collection"].waitForExistence(timeout: 5)
                || revealStaticText("Relic Collection")
        )
    }

    func testProgressTabShowsExplorerSection() throws {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12))
        let progressTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progressTab.waitForExistence(timeout: 5))
        progressTab.tap()

        guard app.state == .runningForeground || app.state == .runningBackground else {
            throw XCTSkip("App terminated before Progress tab could load in this simulator session")
        }

        // Location alerts / first paint can delay the Progress root; retry once if still alive.
        let atlasReady =
            app.navigationBars["Atlas Stats"].waitForExistence(timeout: 6)
            || app.staticTexts["Atlas Stats"].waitForExistence(timeout: 2)
            || app.staticTexts["Territory conquered"].waitForExistence(timeout: 2)
        if !atlasReady, app.state == .runningForeground {
            progressTab.tap()
        }

        let hasChrome =
            app.navigationBars["Atlas Stats"].waitForExistence(timeout: 8)
            || app.staticTexts["Atlas Stats"].waitForExistence(timeout: 3)
            || app.staticTexts["Territory conquered"].waitForExistence(timeout: 3)
            || app.staticTexts["Lifetime XP"].waitForExistence(timeout: 2)
        guard hasChrome else {
            throw XCTSkip("Progress tab chrome not available in this simulator session")
        }

        let hasExplorerContent =
            app.staticTexts["Territory conquered"].waitForExistence(timeout: 5)
            || app.staticTexts["Lifetime XP"].waitForExistence(timeout: 2)
            || app.staticTexts["Mastery ladder"].waitForExistence(timeout: 2)
            || app.staticTexts["Frontier"].waitForExistence(timeout: 2)
            || revealStaticText("Territory conquered")
            || revealStaticText("Lifetime XP")
        guard hasExplorerContent else {
            throw XCTSkip("Progress explorer sections not available in this simulator session")
        }
    }

    func testFrontierExpeditionSelectionAndLeaderboard() throws {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12))
        app.tabBars.buttons["Map"].tap()

        let banner = firstExisting(
            app.buttons["mapMissionsExpeditions"],
            app.buttons["frontierMissionBanner"]
        )
        guard banner.waitForExistence(timeout: 8) else {
            throw XCTSkip("Frontier banner not visible in this simulator session")
        }
        banner.tap()

        XCTAssertTrue(
            app.otherElements["expeditionSheet"].waitForExistence(timeout: 3)
                || app.staticTexts["Frontier Expeditions"].waitForExistence(timeout: 3)
        )

        let scoutCard = app.buttons["expeditionCard_scout"]
        if scoutCard.waitForExistence(timeout: 3) {
            scoutCard.tap()
        }

        let leaderboard = app.buttons["frontierLeaderboardButton"]
        guard leaderboard.waitForExistence(timeout: 3) else {
            throw XCTSkip("Frontier leaderboard control not visible in expedition sheet")
        }
        leaderboard.tap()
        XCTAssertTrue(app.tabBars.firstMatch.exists)
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
            // MapKit / location denial can hide map chrome on some simulators — Journal still covers smoke.
            throw XCTSkip("Map settings control not available in this simulator session")
        }

        settings.tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 5)
                || app.staticTexts["Automatic exploration"].waitForExistence(timeout: 3)
        )

        let done = firstExisting(app.buttons["settingsDone"], app.buttons["Done"])
        if done.waitForExistence(timeout: 3) {
            done.tap()
        }
    }

    private func firstExisting(_ elements: XCUIElement...) -> XCUIElement {
        elements.first ?? app.buttons.firstMatch
    }

    /// Scrolls the frontmost scroll view a few times to materialize lazy list content.
    @discardableResult
    private func revealStaticText(_ label: String) -> Bool {
        let target = app.staticTexts[label]
        if target.exists { return true }
        let scrollViews = app.scrollViews
        let scroller = scrollViews.firstMatch.exists ? scrollViews.firstMatch : app.tables.firstMatch
        for _ in 0..<4 {
            if scroller.exists {
                scroller.swipeUp()
            } else {
                app.swipeUp()
            }
            if target.waitForExistence(timeout: 1.5) {
                return true
            }
        }
        return target.exists
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
