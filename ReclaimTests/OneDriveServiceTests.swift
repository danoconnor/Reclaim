//
//  OneDriveServiceTests.swift
//  ReclaimTests
//
//  Created by Dan O'Connor on 12/17/25.
//

import XCTest
@testable import Reclaim

class MockAuthenticationProvider: AuthenticationProvider {
    var shouldFailInitialize = false
    var mockAccount: Any?
    var mockToken: AuthToken?
    var shouldFailSilentToken = false
    var shouldFailInteractiveToken = false
    
    var initializeCalled = false
    var getAccountCalled = false
    var acquireSilentTokenCalled = false
    var acquireInteractiveTokenCalled = false
    var removeCalled = false
    
    var getAccountExpectation: XCTestExpectation?
    
    func initialize() throws {
        initializeCalled = true
        if shouldFailInitialize {
            throw NSError(domain: "MockError", code: -1, userInfo: nil)
        }
    }
    
    func getAccount() async throws -> Any? {
        getAccountCalled = true
        getAccountExpectation?.fulfill()
        return mockAccount
    }
    
    func acquireSilentToken(account: Any) async throws -> AuthToken {
        acquireSilentTokenCalled = true
        if shouldFailSilentToken {
            throw NSError(domain: "MockError", code: -1, userInfo: nil)
        }
        if let token = mockToken {
            return token
        }
        throw NSError(domain: "MockError", code: -1, userInfo: nil)
    }
    
    func acquireInteractiveToken() async throws -> AuthToken {
        acquireInteractiveTokenCalled = true
        if shouldFailInteractiveToken {
            throw NSError(domain: "MockError", code: -1, userInfo: nil)
        }
        if let token = mockToken {
            return token
        }
        throw NSError(domain: "MockError", code: -1, userInfo: nil)
    }
    
    func remove(account: Any) throws {
        removeCalled = true
    }
}

@MainActor
class OneDriveServiceTests: XCTestCase {
    var service: OneDriveService!
    var mockAuthProvider: MockAuthenticationProvider!
    
    override func setUp() {
        super.setUp()
        mockAuthProvider = MockAuthenticationProvider()
        service = OneDriveService(authProvider: mockAuthProvider)
    }
    
    override func tearDown() {
        service = nil
        mockAuthProvider = nil
        super.tearDown()
    }
    
    func testInit_CallsInitialize() {
        XCTAssertTrue(mockAuthProvider.initializeCalled)
    }
    
    func testInit_CallsRestoreSession() async throws {
        let expectation = XCTestExpectation(description: "restoreSession calls getAccount")
        mockAuthProvider.getAccountExpectation = expectation
        
        // Re-initialize service to trigger the Task in init
        service = OneDriveService(authProvider: mockAuthProvider)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertTrue(mockAuthProvider.getAccountCalled, "restoreSession should be called on init, which calls getAccount")
    }
    
    func testRestoreSession_Success() async {
        // Given
        mockAuthProvider.mockAccount = "MockAccount"
        mockAuthProvider.mockToken = AuthToken(accessToken: "token", expiresOn: Date().addingTimeInterval(3600), account: "MockAccount")
        
        // When
        await service.restoreSession()
        
        // Then
        XCTAssertTrue(mockAuthProvider.getAccountCalled)
        XCTAssertTrue(mockAuthProvider.acquireSilentTokenCalled)
        XCTAssertTrue(service.isAuthenticated)
    }
    
    func testRestoreSession_NoAccount() async {
        // Given
        mockAuthProvider.mockAccount = nil
        
        // When
        await service.restoreSession()
        
        // Then
        XCTAssertTrue(mockAuthProvider.getAccountCalled)
        XCTAssertFalse(mockAuthProvider.acquireSilentTokenCalled)
        XCTAssertFalse(service.isAuthenticated)
    }
    
    func testRestoreSession_SilentTokenFailure() async {
        // Given
        mockAuthProvider.mockAccount = "MockAccount"
        mockAuthProvider.shouldFailSilentToken = true
        
        // When
        await service.restoreSession()
        
        // Then
        XCTAssertTrue(mockAuthProvider.getAccountCalled)
        XCTAssertTrue(mockAuthProvider.acquireSilentTokenCalled)
        XCTAssertFalse(service.isAuthenticated)
    }
    
    func testAuthenticate_Success() async throws {
        // Given
        mockAuthProvider.mockAccount = "MockAccount"
        mockAuthProvider.mockToken = AuthToken(accessToken: "token", expiresOn: Date().addingTimeInterval(3600), account: "MockAccount")
        
        // When
        try await service.authenticate()
        
        // Then
        XCTAssertTrue(service.isAuthenticated)
    }
    
    func testAuthenticate_InteractiveFallback() async throws {
        // Given
        mockAuthProvider.mockAccount = nil
        mockAuthProvider.mockToken = AuthToken(accessToken: "token", expiresOn: Date().addingTimeInterval(3600), account: "MockAccount")
        
        // When
        try await service.authenticate()
        
        // Then
        XCTAssertTrue(mockAuthProvider.acquireInteractiveTokenCalled)
        XCTAssertTrue(service.isAuthenticated)
    }
}
