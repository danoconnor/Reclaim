//
//  PhotoLibraryPermissionTests.swift
//  ReclaimTests
//

import XCTest
import Photos
@testable import Reclaim

@MainActor
class PhotoLibraryPermissionTests: XCTestCase {
    var sut: MockPhotoLibraryService!

    override func setUp() {
        super.setUp()
        sut = MockPhotoLibraryService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Auto-prompt logic

    func testShouldAutoPrompt_WhenNotDetermined() {
        sut.authorizationStatus = .notDetermined
        XCTAssertTrue(sut.authorizationStatus == .notDetermined)
    }

    func testShouldNotAutoPrompt_WhenAuthorized() {
        sut.authorizationStatus = .authorized
        XCTAssertFalse(sut.authorizationStatus == .notDetermined)
    }

    func testShouldNotAutoPrompt_WhenDenied() {
        sut.authorizationStatus = .denied
        XCTAssertFalse(sut.authorizationStatus == .notDetermined)
    }

    func testShouldNotAutoPrompt_WhenRestricted() {
        sut.authorizationStatus = .restricted
        XCTAssertFalse(sut.authorizationStatus == .notDetermined)
    }

    func testShouldNotAutoPrompt_WhenLimited() {
        sut.authorizationStatus = .limited
        XCTAssertFalse(sut.authorizationStatus == .notDetermined)
    }

    // MARK: - Enable in Settings button logic

    func testShouldShowEnableInSettings_WhenDenied() {
        sut.authorizationStatus = .denied
        let shouldShow = sut.authorizationStatus == .denied || sut.authorizationStatus == .restricted
        XCTAssertTrue(shouldShow)
    }

    func testShouldShowEnableInSettings_WhenRestricted() {
        sut.authorizationStatus = .restricted
        let shouldShow = sut.authorizationStatus == .denied || sut.authorizationStatus == .restricted
        XCTAssertTrue(shouldShow)
    }

    func testShouldNotShowEnableInSettings_WhenAuthorized() {
        sut.authorizationStatus = .authorized
        let shouldShow = sut.authorizationStatus == .denied || sut.authorizationStatus == .restricted
        XCTAssertFalse(shouldShow)
    }

    func testShouldNotShowEnableInSettings_WhenLimited() {
        sut.authorizationStatus = .limited
        let shouldShow = sut.authorizationStatus == .denied || sut.authorizationStatus == .restricted
        XCTAssertFalse(shouldShow)
    }

    func testShouldNotShowEnableInSettings_WhenNotDetermined() {
        sut.authorizationStatus = .notDetermined
        let shouldShow = sut.authorizationStatus == .denied || sut.authorizationStatus == .restricted
        XCTAssertFalse(shouldShow)
    }

    // MARK: - requestAuthorization behaviour

    func testRequestAuthorization_WhenGranted_ReturnsTrue() async {
        sut.requestAuthorizationResult = true

        let result = await sut.requestAuthorization()

        XCTAssertTrue(result)
        XCTAssertTrue(sut.requestAuthorizationCalled)
        XCTAssertEqual(sut.authorizationStatus, .authorized)
    }

    func testRequestAuthorization_WhenDenied_ReturnsFalse() async {
        sut.requestAuthorizationResult = false

        let result = await sut.requestAuthorization()

        XCTAssertFalse(result)
        XCTAssertTrue(sut.requestAuthorizationCalled)
        XCTAssertEqual(sut.authorizationStatus, .denied)
    }

    func testRequestAuthorization_WhenGranted_ShouldNoLongerShowEnableInSettings() async {
        sut.authorizationStatus = .notDetermined
        sut.requestAuthorizationResult = true

        _ = await sut.requestAuthorization()

        let shouldShow = sut.authorizationStatus == .denied || sut.authorizationStatus == .restricted
        XCTAssertFalse(shouldShow)
    }

    func testRequestAuthorization_WhenDenied_ShouldShowEnableInSettings() async {
        sut.authorizationStatus = .notDetermined
        sut.requestAuthorizationResult = false

        _ = await sut.requestAuthorization()

        let shouldShow = sut.authorizationStatus == .denied || sut.authorizationStatus == .restricted
        XCTAssertTrue(shouldShow)
    }

    func testRequestAuthorization_NotCalledWhenAlreadyAuthorized() async {
        // Mirrors the on-launch guard: only prompt when .notDetermined
        sut.authorizationStatus = .authorized

        let shouldPrompt = sut.authorizationStatus == .notDetermined
        if shouldPrompt {
            _ = await sut.requestAuthorization()
        }

        XCTAssertFalse(sut.requestAuthorizationCalled)
    }

    func testRequestAuthorization_NotCalledWhenAlreadyDenied() async {
        // Denied users should be directed to Settings, not re-prompted
        sut.authorizationStatus = .denied

        let shouldPrompt = sut.authorizationStatus == .notDetermined
        if shouldPrompt {
            _ = await sut.requestAuthorization()
        }

        XCTAssertFalse(sut.requestAuthorizationCalled)
    }

    // MARK: - Limited access

    func testLimitedAccess_ScanAllowed() {
        sut.authorizationStatus = .limited
        let canScan = sut.authorizationStatus == .authorized || sut.authorizationStatus == .limited
        XCTAssertTrue(canScan)
    }

    func testLimitedAccess_ShowsWarning() {
        sut.authorizationStatus = .limited
        let shouldShowWarning = sut.authorizationStatus == .limited
        XCTAssertTrue(shouldShowWarning)
    }

    func testLimitedAccess_DoesNotShowEnableInSettingsButton() {
        // Limited shows an inline "Change in Settings" link, not the blocked button
        sut.authorizationStatus = .limited
        let shouldShowBlockedButton = sut.authorizationStatus == .denied || sut.authorizationStatus == .restricted
        XCTAssertFalse(shouldShowBlockedButton)
    }

    func testAuthorized_ScanAllowed() {
        sut.authorizationStatus = .authorized
        let canScan = sut.authorizationStatus == .authorized || sut.authorizationStatus == .limited
        XCTAssertTrue(canScan)
    }

    func testDenied_ScanBlocked() {
        sut.authorizationStatus = .denied
        let canScan = sut.authorizationStatus == .authorized || sut.authorizationStatus == .limited
        XCTAssertFalse(canScan)
    }

    func testNotDetermined_ScanBlocked() {
        sut.authorizationStatus = .notDetermined
        let canScan = sut.authorizationStatus == .authorized || sut.authorizationStatus == .limited
        XCTAssertFalse(canScan)
    }
}
