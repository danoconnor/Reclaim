//
//  OneDriveService.swift
//  Reclaim
//
//  Created by Dan O'Connor on 11/8/25.
//

import Foundation
import Combine

@MainActor
class OneDriveService: ObservableObject, OneDriveServiceProtocol {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var oneDriveFiles: [OneDriveFile] = []
    @Published var fetchProgress: Double = 0.0
    @Published var fetchedCount: Int = 0
    @Published var totalCount: Int = 0
    
    private var accessToken: String?
    private var authProvider: AuthenticationProvider
    private var currentAccount: Any?
    private var tokenExpiration: Date?

    init(authProvider: AuthenticationProvider = MSALAuthenticationProvider()) {
        self.authProvider = authProvider
        do {
            try self.authProvider.initialize()
            Task {
                await restoreSession()
            }
        } catch {
            print("Auth provider initialization failed: \(error)")
        }
    }
    
    // MARK: - Authentication
    
    func restoreSession() async {
        // Try silent authentication if we have an account
        do {
            if let account = try await authProvider.getAccount() {
                let tokenResult = try await authProvider.acquireSilentToken(account: account)
                applyTokenResult(tokenResult)
            }
        } catch {
            print("Silent authentication failed during restore: \(error)")
            // Do not fall back to interactive here
        }
    }
    
    func authenticate() async throws {
        // Try silent first if we have an account
        if let account = try await authProvider.getAccount() {
            do {
                let tokenResult = try await authProvider.acquireSilentToken(account: account)
                applyTokenResult(tokenResult)
                return
            } catch {
                // Silent failed; fall through to interactive
            }
        }

        // Interactive sign-in
        let tokenResult = try await authProvider.acquireInteractiveToken()
        applyTokenResult(tokenResult)
    }
    
    func signOut() {
        accessToken = nil
        isAuthenticated = false
        oneDriveFiles = []
        tokenExpiration = nil

        if let account = currentAccount {
            do {
                try authProvider.remove(account: account)
            } catch {
                print("Failed to remove account: \(error)")
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
            if let account = currentAccount {
                do {
                    let result = try await authProvider.acquireSilentToken(account: account)
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
        fetchProgress = 0.0
        fetchedCount = 0
        totalCount = 0
        
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
        // 1. Get initial count from root folder
        var totalItemsToFetch = 0
        var processedItems = 0
        
        let rootURL = URL(string: "https://graph.microsoft.com/v1.0/me/drive/special/photos")!
        var rootRequest = URLRequest(url: rootURL)
        rootRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: rootRequest)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let rootItem = try JSONDecoder().decode(OneDriveParser.GraphFile.self, from: data)
                if let count = rootItem.folder?.childCount {
                    totalItemsToFetch = count
                }
            }
        } catch {
            print("Failed to fetch root item count: \(error)")
        }
        
        // Ensure we have at least 1 to avoid division by zero
        if totalItemsToFetch == 0 { totalItemsToFetch = 1 }

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

        func updateProgress() {
            processedItems += 1
            // Throttle updates to avoid blocking the main thread
            if processedItems % 10 == 0 || processedItems >= totalItemsToFetch {
                self.fetchProgress = min(Double(processedItems) / Double(totalItemsToFetch), 1.0)
                self.fetchedCount = processedItems
                self.totalCount = totalItemsToFetch
            }
        }

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
                    updateProgress()
                    
                    if let file = OneDriveParser.makeOneDriveFile(from: child, startDate: startDate, endDate: endDate) {
                        if seenFileIds.insert(file.id).inserted {
                            collected.append(file)
                        }
                    } else if child.folder != nil || child.bundle != nil {
                        if let folder = child.folder, let count = folder.childCount {
                            totalItemsToFetch += count
                            self.totalCount = totalItemsToFetch
                        } else if let bundle = child.bundle, let count = bundle.childCount {
                            totalItemsToFetch += count
                            self.totalCount = totalItemsToFetch
                        }
                        
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
                updateProgress()
                
                if let file = OneDriveParser.makeOneDriveFile(from: graphFile, startDate: startDate, endDate: endDate) {
                    if seenFileIds.insert(file.id).inserted {
                        allFiles.append(file)
                    }
                } else if graphFile.folder != nil || graphFile.bundle != nil {
                    if let folder = graphFile.folder, let count = folder.childCount {
                        totalItemsToFetch += count
                        self.totalCount = totalItemsToFetch
                    } else if let bundle = graphFile.bundle, let count = bundle.childCount {
                        totalItemsToFetch += count
                        self.totalCount = totalItemsToFetch
                    }
                    
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

    private func applyTokenResult(_ result: AuthToken) {
        self.accessToken = result.accessToken
        self.tokenExpiration = result.expiresOn
        self.currentAccount = result.account
        self.isAuthenticated = true
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

