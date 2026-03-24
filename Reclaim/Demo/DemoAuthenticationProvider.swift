//
//  DemoAuthenticationProvider.swift
//  Reclaim
//
//  Created for UI testing and screenshots.
//

#if DEBUG
import Foundation

/// A no-op AuthenticationProvider used in demo/UI test mode to avoid MSAL initialization
final class DemoAuthenticationProvider: AuthenticationProvider, @unchecked Sendable {
    nonisolated func initialize() throws {
        // No-op in demo mode
    }
    
    func getAccount() async throws -> Any? {
        return nil
    }
    
    func acquireSilentToken(account: Any) async throws -> AuthToken {
        throw OneDriveError.notAuthenticated
    }
    
    func acquireInteractiveToken() async throws -> AuthToken {
        throw OneDriveError.notAuthenticated
    }
    
    nonisolated func remove(account: Any) throws {
        // No-op in demo mode
    }
}
#endif
