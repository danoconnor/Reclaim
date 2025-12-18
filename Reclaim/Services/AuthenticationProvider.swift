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

protocol AuthenticationProvider {
    func initialize() throws
    func getAccount() async throws -> Any?
    func acquireSilentToken(account: Any) async throws -> AuthToken
    func acquireInteractiveToken() async throws -> AuthToken
    func remove(account: Any) throws
}

class MSALAuthenticationProvider: AuthenticationProvider {
    private var msalApp: MSALPublicClientApplication?
    private let clientId = "46827a6b-71c9-48b9-b721-7abec6bab34d"
    private let scopes = ["Files.Read"]
    private lazy var redirectUri: String = "msauth.com.danoconnor.Reclaim://auth"
    
    func initialize() throws {
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
        
        #if os(iOS)
        let rootVC = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController ?? UIViewController()
        let webParameters = MSALWebviewParameters(authPresentationViewController: rootVC)
        #elseif os(macOS)
        // Assuming this code is shared, but the project seems to be iOS focused based on imports.
        // Keeping it simple for now as per existing OneDriveService
        let webParameters = MSALWebviewParameters(authPresentationViewController: UIViewController())
        #else
        let webParameters = MSALWebviewParameters(authPresentationViewController: UIViewController())
        #endif

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
    
    func remove(account: Any) throws {
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
