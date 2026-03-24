//
//  ReclaimUITestsLaunchTests.swift
//  ReclaimUITests
//
//  Created by Dan O'Connor on 11/8/25.
//

import XCTest

final class ReclaimUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-Unlocked"]
        app.launch()

        // Wait for demo data to populate
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
