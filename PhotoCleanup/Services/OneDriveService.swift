//
//  OneDriveService.swift
//  PhotoCleanup
//
//  Created by Dan O'Connor on 11/8/25.
//

import Foundation
import Combine
import MSAL

@MainActor
class OneDriveService: ObservableObject, OneDriveServiceProtocol {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var oneDriveFiles: [OneDriveFile] = []
    
    private var accessToken: String?
    private let clientId = "46827a6b-71c9-48b9-b721-7abec6bab34d" // TODO: Replace with your Azure AD App (Client) ID
    private let scopes = ["Files.Read", "User.Read"] // Adjust scopes as needed
    private lazy var redirectUri: String = "msauth.com.danoconnor.PhotoCleanup://auth"
    private var msalApp: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?
    private var tokenExpiration: Date?

    init() {
        do {
            let authorityURL = URL(string: "https://login.microsoftonline.com/consumers")!
            let authority = try MSALAADAuthority(url: authorityURL)
            let config = MSALPublicClientApplicationConfig(clientId: clientId, redirectUri: redirectUri, authority: authority)
            self.msalApp = try MSALPublicClientApplication(configuration: config)
        } catch {
            print("MSAL initialization failed: \(error)")
        }
    }
    
    // MARK: - Authentication
    
    func authenticate() async throws {
        guard let msalApp = msalApp else { throw OneDriveError.notImplemented }

        // Try silent first if we have an account
        if let account = try await getAccount(msalApp: msalApp) {
            do {
                let tokenResult = try await acquireSilentToken(app: msalApp, account: account)
                applyTokenResult(tokenResult)
                return
            } catch {
                // Silent failed; fall through to interactive
            }
        }

        // Interactive sign-in
        let tokenResult = try await acquireInteractiveToken(app: msalApp)
        applyTokenResult(tokenResult)
    }
    
    func signOut() {
        accessToken = nil
        isAuthenticated = false
        oneDriveFiles = []
        tokenExpiration = nil

        if let account = currentAccount, let app = msalApp {
            do {
                try app.remove(account)
            } catch {
                print("Failed to remove MSAL account: \(error)")
            }
        }
        currentAccount = nil
    }
    
    // MARK: - Fetch Files
    
    func fetchPhotosFromOneDrive(startDate: Date? = nil, endDate: Date? = nil) async throws {
        let token: String
        if let existing = accessToken, let exp = tokenExpiration, exp.timeIntervalSinceNow > 60 { // token valid >= 60s
            token = existing
        } else {
            // Attempt silent refresh if possible
            if let msalApp = msalApp, let account = currentAccount {
                do {
                    let result = try await acquireSilentToken(app: msalApp, account: account)
                    applyTokenResult(result)
                    token = result.accessToken
                } catch {
                    throw OneDriveError.notAuthenticated
                }
            } else {
                throw OneDriveError.notAuthenticated
            }
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let files = try await fetchPhotosFromSpecialView(token: token, startDate: startDate, endDate: endDate)
            self.oneDriveFiles = files
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    private func fetchPhotosFromSpecialView(token: String, startDate: Date?, endDate: Date?) async throws -> [OneDriveFile] {
        let selectFields = "id,name,size,photo,file,fileSystemInfo,@microsoft.graph.downloadUrl,folder,bundle"
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/drive/special/photos/children")
        components?.queryItems = [
            URLQueryItem(name: "$select", value: selectFields)
        ]

        guard let initialURL = components?.url else { throw OneDriveError.invalidURL }
        var currentURL = initialURL
        var allFiles: [OneDriveFile] = []
        var seenFileIds = Set<String>()
        var visitedContainers = Set<String>()

        let decoder = JSONDecoder()

        func fetchDescendants(for itemId: String) async throws -> [OneDriveFile] {
            guard !visitedContainers.contains(itemId) else { return [] }
            visitedContainers.insert(itemId)

            var childComponents = URLComponents(string: "https://graph.microsoft.com/v1.0/me/drive/items/\(itemId)/children")
            childComponents?.queryItems = [
                URLQueryItem(name: "$select", value: selectFields)
            ]

            guard let initialChildURL = childComponents?.url else { throw OneDriveError.invalidURL }
            var childURL = initialChildURL
            var collected: [OneDriveFile] = []

            while true {
                var request = URLRequest(url: childURL)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OneDriveError.invalidResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw OneDriveError.httpError(statusCode: httpResponse.statusCode)
                }

                let responseObj = try decoder.decode(OneDriveParser.GraphResponse.self, from: data)

                for child in responseObj.value {
                    if let file = OneDriveParser.makeOneDriveFile(from: child, startDate: startDate, endDate: endDate) {
                        if seenFileIds.insert(file.id).inserted {
                            collected.append(file)
                        }
                    } else if child.folder != nil || child.bundle != nil {
                        let nested = try await fetchDescendants(for: child.id)
                        collected.append(contentsOf: nested)
                    }
                }

                if let next = responseObj.nextLink, let nextURL = URL(string: next) {
                    childURL = nextURL
                    continue
                } else {
                    break
                }
            }

            return collected
        }

        while true {
            var request = URLRequest(url: currentURL)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OneDriveError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw OneDriveError.httpError(statusCode: httpResponse.statusCode)
            }

            let responseObj = try decoder.decode(OneDriveParser.GraphResponse.self, from: data)

            for graphFile in responseObj.value {
                if let file = OneDriveParser.makeOneDriveFile(from: graphFile, startDate: startDate, endDate: endDate) {
                    if seenFileIds.insert(file.id).inserted {
                        allFiles.append(file)
                    }
                } else if graphFile.folder != nil || graphFile.bundle != nil {
                    let nested = try await fetchDescendants(for: graphFile.id)
                    allFiles.append(contentsOf: nested)
                }
            }

            if let next = responseObj.nextLink, let nextURL = URL(string: next) {
                currentURL = nextURL
                continue
            } else {
                break
            }
        }

        // Sort client-side because the photos view rejects server-side ordering.
        let sortedFiles = allFiles.sorted { lhs, rhs in
            let lhsDate = lhs.createdDateTime ?? Date.distantPast
            let rhsDate = rhs.createdDateTime ?? Date.distantPast

            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id < rhs.id
        }

        return sortedFiles
    }
}

// MARK: - Errors

enum OneDriveError: LocalizedError {
    case notAuthenticated
    case notImplemented
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with OneDrive. Please sign in."
        case .notImplemented:
            return "OneDrive authentication not yet implemented. MSAL integration required."
        case .invalidURL:
            return "Invalid URL for OneDrive request."
        case .invalidResponse:
            return "Invalid response from OneDrive."
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .downloadFailed:
            return "Failed to download file from OneDrive."
        }
    }
}

// MARK: - MSAL Helpers
extension OneDriveService {
    private func getAccount(msalApp: MSALPublicClientApplication) async throws -> MSALAccount? {
        let allAccounts = try msalApp.allAccounts()
        return allAccounts.first
    }

    private func acquireSilentToken(app: MSALPublicClientApplication, account: MSALAccount) async throws -> MSALResult {
        try await withCheckedThrowingContinuation { continuation in
            let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)
            app.acquireTokenSilent(with: parameters) { result, error in
                if let error = error { continuation.resume(throwing: error); return }
                guard let result = result else { continuation.resume(throwing: OneDriveError.invalidResponse); return }
                continuation.resume(returning: result)
            }
        }
    }

    private func acquireInteractiveToken(app: MSALPublicClientApplication) async throws -> MSALResult {
        #if os(iOS)
        let rootVC = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController ?? UIViewController()
        let webParameters = MSALWebviewParameters(authPresentationViewController: rootVC)
        #elseif os(macOS)
        let rootVC = NSApplication.shared.keyWindow?.contentViewController ?? NSViewController()
        let webParameters = MSALWebviewParameters(authPresentationViewController: rootVC)
        #else
        let webParameters = MSALWebviewParameters(authPresentationViewController: UIViewController())
        #endif

        let interactiveParameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParameters)
        interactiveParameters.promptType = .selectAccount

        return try await withCheckedThrowingContinuation { continuation in
            app.acquireToken(with: interactiveParameters) { result, error in
                if let error = error { continuation.resume(throwing: error); return }
                guard let result = result else { continuation.resume(throwing: OneDriveError.invalidResponse); return }
                continuation.resume(returning: result)
            }
        }
    }

    private func applyTokenResult(_ result: MSALResult) {
        self.accessToken = result.accessToken
        self.tokenExpiration = result.expiresOn
        self.currentAccount = result.account
        self.isAuthenticated = true
    }
}
