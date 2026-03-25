//
//  ReclaimUITests.swift
//  ReclaimUITests
//
//  Created by Dan O'Connor on 11/8/25.
//

import XCTest

// MARK: - Screenshot Tests for App Store Submission

final class ScreenshotTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Helpers
    
    /// Launches the app in demo mode with pre-populated data
    @MainActor
    private func launchInDemoMode(unlocked: Bool = true) {
        app.launchArguments = ["-UITestMode"]
        if unlocked {
            app.launchArguments.append("-Unlocked")
        }
        app.launch()
    }
    
    /// Takes a screenshot and attaches it to the test results with `.keepAlways` lifetime
    private func takeScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    // MARK: - Screenshot Tests
    
    @MainActor
    func testMainDashboardScreenshot() throws {
        launchInDemoMode(unlocked: true)
        
        // Verify we're on the main dashboard
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5), "Main dashboard should show 'Reclaim' title")
        
        // Verify statistics are visible (check the "Statistics" header text as a reliable indicator)
        let statsHeader = app.staticTexts["Statistics"]
        XCTAssertTrue(statsHeader.waitForExistence(timeout: 5), "Statistics section should be visible with demo data")
        
        // Verify key buttons are present
        XCTAssertTrue(app.buttons["reviewPhotosButton"].exists, "Review Photos button should exist")
        XCTAssertTrue(app.buttons["deleteAllButton"].exists, "Delete All button should exist")
        
        // Take the App Store screenshot
        takeScreenshot(name: "01_MainDashboard")
    }
    
    @MainActor
    func testMainDashboardLockedScreenshot() throws {
        launchInDemoMode(unlocked: false)
        
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        
        // Verify lock icon is shown on delete button (the button should still exist)
        XCTAssertTrue(app.buttons["deleteAllButton"].waitForExistence(timeout: 3))
        
        takeScreenshot(name: "01b_MainDashboard_Locked")
    }
    
    @MainActor
    func testPhotoReviewScreenshot() throws {
        launchInDemoMode(unlocked: true)
        
        // Wait for the main screen to load
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        
        // Tap Review Photos button to open the photo review sheet
        let reviewButton = app.buttons["reviewPhotosButton"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5), "Review Photos button should exist")
        reviewButton.tap()
        
        // Wait for the photo review sheet to appear
        let reviewTitle = app.staticTexts["Review Photos"]
        XCTAssertTrue(reviewTitle.waitForExistence(timeout: 5), "Photo Review screen should appear")
        
        // Wait for photo grid to populate with placeholder thumbnails
        let photoGrid = app.otherElements["photoGrid"]
        XCTAssertTrue(photoGrid.waitForExistence(timeout: 5), "Photo grid should be visible")
        
        // Let thumbnails render
        Thread.sleep(forTimeInterval: 2.0)
        
        takeScreenshot(name: "02_PhotoReview")
    }
    
    @MainActor
    func testPhotoReviewWithSelectionScreenshot() throws {
        launchInDemoMode(unlocked: true)
        
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        
        let reviewButton = app.buttons["reviewPhotosButton"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
        reviewButton.tap()
        
        let reviewTitle = app.staticTexts["Review Photos"]
        XCTAssertTrue(reviewTitle.waitForExistence(timeout: 5))
        
        // Select all photos to show the selection state
        let selectAllButton = app.buttons["selectAllButton"]
        XCTAssertTrue(selectAllButton.waitForExistence(timeout: 3))
        selectAllButton.tap()
        
        // Wait for selection UI to update
        Thread.sleep(forTimeInterval: 1.0)
        
        takeScreenshot(name: "02b_PhotoReview_Selected")
    }
    
    @MainActor
    func testSettingsScreenshot() throws {
        launchInDemoMode(unlocked: true)
        
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        
        // Tap settings gear button
        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3), "Settings button should exist")
        settingsButton.tap()
        
        // Wait for Settings sheet to appear
        let settingsTitle = app.staticTexts["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 5), "Settings screen should appear")
        
        takeScreenshot(name: "03_Settings")
    }
    
    @MainActor
    func testPaywallScreenshot() throws {
        // Launch in LOCKED mode so tapping delete triggers the paywall
        launchInDemoMode(unlocked: false)
        
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        
        // Tap the delete button which should trigger the paywall when locked
        let deleteButton = app.buttons["deleteAllButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "Delete All button should exist")
        deleteButton.tap()
        
        // Wait for the paywall to appear
        let unlockTitle = app.staticTexts["Unlock Deletion"]
        XCTAssertTrue(unlockTitle.waitForExistence(timeout: 5), "Paywall should appear with 'Unlock Deletion' title")
        
        // Wait for product price to load (StoreKit in sandbox/demo)
        Thread.sleep(forTimeInterval: 2.0)
        
        takeScreenshot(name: "04_Paywall")
    }
}

// MARK: - Functional UI Tests

final class ReclaimUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-Unlocked"]
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Navigation Tests
    
    @MainActor
    func testMainScreenLoads() throws {
        app.launch()
        
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5), "Main screen should load with 'Reclaim' title")
        
        // Verify core UI elements exist
        XCTAssertTrue(app.buttons["settingsButton"].exists, "Settings button should be visible")
        XCTAssertTrue(app.buttons["scanButton"].exists, "Scan button should be visible")
        XCTAssertTrue(app.buttons["reviewPhotosButton"].exists, "Review button should be visible")
        XCTAssertTrue(app.buttons["deleteAllButton"].exists, "Delete All button should be visible")
    }
    
    @MainActor
    func testStatisticsVisible() throws {
        app.launch()
        
        // Wait for demo data to populate
        let statsHeader = app.staticTexts["Statistics"]
        XCTAssertTrue(statsHeader.waitForExistence(timeout: 5), "Statistics section should be visible")
        
        // Verify all four stat cards are present using their accessibility identifiers
        XCTAssertTrue(app.otherElements["stat_localPhotos"].waitForExistence(timeout: 3), "Local Photos stat card should exist")
        XCTAssertTrue(app.otherElements["stat_oneDrivePhotos"].exists, "OneDrive Photos stat card should exist")
        XCTAssertTrue(app.otherElements["stat_canDelete"].exists, "Can Delete stat card should exist")
        XCTAssertTrue(app.otherElements["stat_spaceToFree"].exists, "Space to Free stat card should exist")
    }
    
    @MainActor
    func testOpenSettings() throws {
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        app.buttons["settingsButton"].tap()

        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 5), "Settings screen should appear")

        // Check row-level content unique to Settings rather than section headers,
        // which are not reliably accessible in SwiftUI's collection-view-backed Form on iOS 18
        XCTAssertTrue(app.staticTexts["Favorites"].waitForExistence(timeout: 3), "Favorites row should exist (Protection section)")
        XCTAssertTrue(app.buttons["Restore Purchase"].waitForExistence(timeout: 3), "Restore Purchase button should exist (Purchases section)")

        // Close settings
        app.buttons["settingsDoneButton"].tap()
        XCTAssertTrue(navTitle.waitForExistence(timeout: 3), "Should return to main screen")
    }
    
    @MainActor
    func testOpenPhotoReview() throws {
        app.launch()
        
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        
        let reviewButton = app.buttons["reviewPhotosButton"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 3))
        reviewButton.tap()
        
        // Verify photo review screen appears
        let reviewTitle = app.staticTexts["Review Photos"]
        XCTAssertTrue(reviewTitle.waitForExistence(timeout: 5), "Photo Review screen should appear")
        
        // Verify selection controls exist
        XCTAssertTrue(app.buttons["selectAllButton"].exists, "Select All button should exist")
        XCTAssertTrue(app.buttons["deselectAllButton"].exists, "Deselect All button should exist")
    }
    
    @MainActor
    func testPhotoReviewSelectAllDeselectAll() throws {
        app.launch()
        
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        app.buttons["reviewPhotosButton"].tap()
        
        let reviewTitle = app.staticTexts["Review Photos"]
        XCTAssertTrue(reviewTitle.waitForExistence(timeout: 5))
        
        // Tap Select All
        app.buttons["selectAllButton"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        
        // Verify selected count changed (should show non-zero)
        let selectedCount = app.staticTexts["selectedCount"]
        XCTAssertTrue(selectedCount.exists, "Selected count label should exist")
        XCTAssertFalse(selectedCount.label.contains("0 selected"), "Should have some photos selected after Select All")
        
        // Tap Deselect All
        app.buttons["deselectAllButton"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        
        // Verify back to 0
        XCTAssertTrue(selectedCount.label.contains("0 selected"), "Should show 0 selected after Deselect All")
    }
    
    @MainActor
    func testPhotoReviewDismiss() throws {
        app.launch()
        
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        
        app.buttons["reviewPhotosButton"].tap()
        
        let reviewTitle = app.staticTexts["Review Photos"]
        XCTAssertTrue(reviewTitle.waitForExistence(timeout: 5))
        
        // Dismiss via Cancel button
        app.buttons["Cancel"].tap()
        
        // Should return to main screen
        XCTAssertTrue(navTitle.waitForExistence(timeout: 3), "Should return to main screen after cancel")
    }
    
    @MainActor
    func testPaywallAppearsWhenLocked() throws {
        // Reset to locked state
        app.launchArguments = ["-UITestMode"]  // No -Unlocked
        app.launch()
        
        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        
        // Tap delete (locked) should show paywall
        app.buttons["deleteAllButton"].tap()
        
        let unlockTitle = app.staticTexts["Unlock Deletion"]
        XCTAssertTrue(unlockTitle.waitForExistence(timeout: 5), "Paywall should appear")
        
        // Verify paywall elements
        XCTAssertTrue(app.buttons["paywallCancelButton"].exists, "Cancel button should exist on paywall")
        XCTAssertTrue(app.buttons["paywallRestoreButton"].exists, "Restore Purchase button should exist")
        
        // Dismiss paywall
        app.buttons["paywallCancelButton"].tap()
        XCTAssertTrue(navTitle.waitForExistence(timeout: 3), "Should return to main screen")
    }
    
    @MainActor
    func testSettingsDateFilterOptions() throws {
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        app.buttons["settingsButton"].tap()

        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 5))

        // Check for row-level content — section headers are not reliably accessible
        // in SwiftUI's collection-view-backed Form on iOS 18
        XCTAssertTrue(app.staticTexts["Date Range"].waitForExistence(timeout: 3), "Date Range picker should exist")
    }

    // MARK: - Photo Access: Denied

    @MainActor
    func testPhotoAccessDenied_ShowsEnableInSettingsButton() throws {
        app.launchArguments = ["-UITestMode", "-Unlocked", "-PhotoAccessDenied"]
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        XCTAssertTrue(
            app.buttons["enablePhotoAccessButton"].waitForExistence(timeout: 3),
            "Enable Photo Access in Settings button should appear when access is denied"
        )
    }

    @MainActor
    func testPhotoAccessDenied_DoesNotShowAllowButton() throws {
        app.launchArguments = ["-UITestMode", "-Unlocked", "-PhotoAccessDenied"]
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        XCTAssertFalse(
            app.buttons["allowPhotoAccessButton"].exists,
            "Old 'Allow Photo Access' button should not appear"
        )
    }

    @MainActor
    func testPhotoAccessDenied_ScanButtonDisabled() throws {
        app.launchArguments = ["-UITestMode", "-Unlocked", "-PhotoAccessDenied"]
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        let scanButton = app.buttons["scanButton"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 3))
        XCTAssertFalse(scanButton.isEnabled, "Scan button should be disabled when photo access is denied")
    }

    @MainActor
    func testPhotoAccessDenied_StatusShowsDenied() throws {
        app.launchArguments = ["-UITestMode", "-Unlocked", "-PhotoAccessDenied"]
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        XCTAssertTrue(
            app.staticTexts["Denied"].waitForExistence(timeout: 3),
            "Status section should show 'Denied' for photo library"
        )
    }

    // MARK: - Photo Access: Limited

    @MainActor
    func testPhotoAccessLimited_ShowsWarningBanner() throws {
        app.launchArguments = ["-UITestMode", "-Unlocked", "-PhotoAccessLimited"]
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        XCTAssertTrue(
            app.otherElements["limitedAccessWarning"].waitForExistence(timeout: 3),
            "Limited access warning banner should be visible"
        )
    }

    @MainActor
    func testPhotoAccessLimited_ScanButtonEnabled() throws {
        app.launchArguments = ["-UITestMode", "-Unlocked", "-PhotoAccessLimited"]
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        let scanButton = app.buttons["scanButton"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scanButton.isEnabled, "Scan button should be enabled when photo access is limited")
    }

    @MainActor
    func testPhotoAccessLimited_DoesNotShowEnableInSettingsButton() throws {
        app.launchArguments = ["-UITestMode", "-Unlocked", "-PhotoAccessLimited"]
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        XCTAssertFalse(
            app.buttons["enablePhotoAccessButton"].exists,
            "Blocked access button should not appear for limited access"
        )
    }

    @MainActor
    func testPhotoAccessLimited_StatusShowsLimited() throws {
        app.launchArguments = ["-UITestMode", "-Unlocked", "-PhotoAccessLimited"]
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        XCTAssertTrue(
            app.staticTexts["Limited"].waitForExistence(timeout: 3),
            "Status section should show 'Limited' for photo library"
        )
    }

    @MainActor
    func testPhotoAccessLimited_WarningBannerContainsSettingsLink() throws {
        app.launchArguments = ["-UITestMode", "-Unlocked", "-PhotoAccessLimited"]
        app.launch()

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))

        XCTAssertTrue(
            app.buttons["Change in Settings"].waitForExistence(timeout: 3),
            "Warning banner should contain a 'Change in Settings' link"
        )
    }
}

// MARK: - Screenshot Tests for Permission States

extension ScreenshotTests {

    @MainActor
    private func launchWithPhotoAccess(_ access: String, unlocked: Bool = true) {
        app.launchArguments = ["-UITestMode", access]
        if unlocked { app.launchArguments.append("-Unlocked") }
        app.launch()
    }

    @MainActor
    func testPhotoAccessDeniedScreenshot() throws {
        launchWithPhotoAccess("-PhotoAccessDenied")

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["enablePhotoAccessButton"].waitForExistence(timeout: 3))

        takeScreenshot(name: "05_PhotoAccessDenied")
    }

    @MainActor
    func testPhotoAccessLimitedScreenshot() throws {
        launchWithPhotoAccess("-PhotoAccessLimited")

        let navTitle = app.navigationBars["Reclaim"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["limitedAccessWarning"].waitForExistence(timeout: 3))

        takeScreenshot(name: "06_PhotoAccessLimited")
    }
}
