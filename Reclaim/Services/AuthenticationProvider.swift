//
//  AuthenticationProvider.swift
//  Reclaim
//
//  Created by Dan O'Connor on 12/17/25.
//

import Foundation
import MSAL
import UIKit

struct AuthToken {
    let accessToken: String
    let expiresOn: Date?
    let account: Any
}

protocol AuthenticationProvider: Sendable {
    nonisolated func initialize() throws
    func getAccount() async throws -> Any?
    func acquireSilentToken(account: Any) async throws -> AuthToken
    func acquireInteractiveToken() async throws -> AuthToken
    nonisolated func remove(account: Any) throws
}

final class MSALAuthenticationProvider: AuthenticationProvider, @unchecked Sendable {
    // nonisolated(unsafe): This property is written once during initialize() and then only read.
    // Thread-safe because: MSAL library guarantees thread-safety, and we never mutate after init.
    private nonisolated(unsafe) var msalApp: MSALPublicClientApplication?
    private let clientId = "46827a6b-71c9-48b9-b721-7abec6bab34d"
    private let scopes = ["Files.Read"]
    private let redirectUri: String = "msauth.com.danoconnor.Reclaim://auth"
    
    nonisolated init() {}
    
    nonisolated func initialize() throws {
        let authorityURL = URL(string: "https://login.microsoftonline.com/consumers")!
        let authority = try MSALAADAuthority(url: authorityURL)
        let config = MSALPublicClientApplicationConfig(clientId: clientId, redirectUri: redirectUri, authority: authority)
        self.msalApp = try MSALPublicClientApplication(configuration: config)
    }
    
    func getAccount() async throws -> Any? {
        guard let app = msalApp else { return nil }
        let allAccounts = try app.allAccounts()
        return allAccounts.first
    }
    
    func acquireSilentToken(account: Any) async throws -> AuthToken {
        guard let app = msalApp, let msalAccount = account as? MSALAccount else {
            throw OneDriveError.notImplemented // Or appropriate error
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let parameters = MSALSilentTokenParameters(scopes: scopes, account: msalAccount)
            app.acquireTokenSilent(with: parameters) { result, error in
                if let error = error { continuation.resume(throwing: error); return }
                guard let result = result else { continuation.resume(throwing: OneDriveError.invalidResponse); return }
                continuation.resume(returning: self.mapResult(result))
            }
        }
    }
    
    func acquireInteractiveToken() async throws -> AuthToken {
        guard let app = msalApp else { throw OneDriveError.notImplemented }
        
        let presentingVC = await MainActor.run {
            let rootVC = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .first?
                .keyWindow?
                .rootViewController

            // Walk up the presentation chain to find the topmost visible VC,
            // otherwise presenting fails silently on iPad.
            var topVC = rootVC
            while let presented = topVC?.presentedViewController {
                topVC = presented
            }

            return topVC ?? UIViewController()
        }

        let webParameters = MSALWebviewParameters(authPresentationViewController: presentingVC)

        let interactiveParameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParameters)
        interactiveParameters.promptType = .selectAccount

        return try await withCheckedThrowingContinuation { continuation in
            app.acquireToken(with: interactiveParameters) { result, error in
                if let error = error { continuation.resume(throwing: error); return }
                guard let result = result else { continuation.resume(throwing: OneDriveError.invalidResponse); return }
                continuation.resume(returning: self.mapResult(result))
            }
        }
    }
    
    nonisolated func remove(account: Any) throws {
        guard let app = msalApp, let msalAccount = account as? MSALAccount else { return }
        try app.remove(msalAccount)
    }
    
    private func mapResult(_ result: MSALResult) -> AuthToken {
        return AuthToken(
            accessToken: result.accessToken,
            expiresOn: result.expiresOn,
            account: result.account
        )
    }
}
