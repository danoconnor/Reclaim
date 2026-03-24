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
    
    #if DEBUG
    /// Creates a demo OneDriveService with pre-configured state for UI tests/screenshots
    static func demo(fileCount: Int) -> OneDriveService {
        let service = OneDriveService(authProvider: DemoAuthenticationProvider())
        service.isAuthenticated = true
        service.fetchedCount = fileCount
        service.totalCount = fileCount
        return service
    }
    #endif
    
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
    
    func fetchPhotosFromOneDrive(startDate: Date? = nil, endDate: Date? = nil) async throws -> [OneDriveFile] {
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
            isLoading = false
            return files
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    private func fetchPhotosFromSpecialView(token: String, startDate: Date?, endDate: Date?) async throws -> [OneDriveFile] {
        // Fetch root folder with expanded children in a single request
        let rootURL = URL(string: "https://graph.microsoft.com/v1.0/me/drive/special/photos?select=name,id,folder&expand=children(select=id,name,size,photo,file,fileSystemInfo,@microsoft.graph.downloadUrl,folder,bundle)")!
        var rootRequest = URLRequest(url: rootURL)
        rootRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: rootRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OneDriveError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let rootItem = try JSONDecoder().decode(OneDriveParser.GraphFile.self, from: data)
        
        // Calculate initial total items
        var totalItemsToFetch = rootItem.folder?.childCount ?? 1
        if totalItemsToFetch == 0 { totalItemsToFetch = 1 }

        actor RecursiveFetcher {
            let token: String
            let startDate: Date?
            let endDate: Date?
            let decoder = JSONDecoder()
            
            private var seenFileIds = Set<String>()
            private var visitedContainers = Set<String>()
            private var totalItemsToFetch: Int
            private var processedItems = 0
            
            let onProgress: (Int, Int) -> Void
            let onTotalUpdate: (Int) -> Void
            
            init(token: String,
                 startDate: Date?,
                 endDate: Date?,
                 totalItems: Int,
                 onProgress: @escaping (Int, Int) -> Void,
                 onTotalUpdate: @escaping (Int) -> Void) {
                self.token = token
                self.startDate = startDate
                self.endDate = endDate
                self.totalItemsToFetch = totalItems
                self.onProgress = onProgress
                self.onTotalUpdate = onTotalUpdate
            }
            
            func markContainerVisited(_ id: String) -> Bool {
                if visitedContainers.contains(id) {
                    return false
                }
                visitedContainers.insert(id)
                return true
            }
            
            func addFile(_ file: OneDriveFile) -> Bool {
                seenFileIds.insert(file.id).inserted
            }
            
            func incrementTotal(by count: Int) {
                totalItemsToFetch += count
                onTotalUpdate(totalItemsToFetch)
            }
            
            func getTotalItems() -> Int {
                totalItemsToFetch
            }
            
            func updateProgress() async {
                processedItems += 1
                if processedItems % 10 == 0 || processedItems >= totalItemsToFetch {
                    onProgress(processedItems, totalItemsToFetch)
                }
            }
            
            func fetchExpandedItem(itemId: String) async throws -> [OneDriveFile] {
                guard markContainerVisited(itemId) else { return [] }

                var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/drive/items/\(itemId)")
                let childSelect = "id,name,size,photo,file,fileSystemInfo,@microsoft.graph.downloadUrl,folder,bundle"
                components?.queryItems = [
                    URLQueryItem(name: "select", value: "id,name,folder,children"),
                    URLQueryItem(name: "expand", value: "children(select=\(childSelect))")
                ]

                guard let url = components?.url else { throw OneDriveError.invalidURL }
                
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    throw OneDriveError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                
                let item = try decoder.decode(OneDriveParser.GraphFile.self, from: data)
                var collected: [OneDriveFile] = []
                
                if let children = item.children {
                    let expandedFiles = try await processChildren(children)
                    collected.append(contentsOf: expandedFiles)
                }
                
                if let nextLink = item.childrenNextLink {
                    let pagedFiles = try await fetchNextLink(nextLink)
                    collected.append(contentsOf: pagedFiles)
                }
                
                return collected
            }
            
            func processChildren(_ children: [OneDriveParser.GraphFile]) async throws -> [OneDriveFile] {
                var collected: [OneDriveFile] = []
                var foldersToFetch: [String] = []
                
                // First pass: collect files and identify folders to fetch
                for child in children {                    
                    if let file = OneDriveParser.makeOneDriveFile(from: child, startDate: startDate, endDate: endDate) {
                        if addFile(file) {
                            await updateProgress()
                            collected.append(file)
                        }
                    } else if child.folder != nil || child.bundle != nil {
                        if let folder = child.folder, let count = folder.childCount {
                            incrementTotal(by: count)
                        } else if let bundle = child.bundle, let count = bundle.childCount {
                            incrementTotal(by: count)
                        }
                        
                        foldersToFetch.append(child.id)
                    }
                }
                
                // Second pass: fetch all folders in parallel
                if !foldersToFetch.isEmpty {
                    let nestedFiles = try await withThrowingTaskGroup(of: [OneDriveFile].self) { group in
                        for folderId in foldersToFetch {
                            group.addTask {
                                try await self.fetchExpandedItem(itemId: folderId)
                            }
                        }
                        
                        var allFiles: [OneDriveFile] = []
                        for try await files in group {
                            allFiles.append(contentsOf: files)
                        }
                        return allFiles
                    }
                    collected.append(contentsOf: nestedFiles)
                }
                
                return collected
            }
            
            func fetchNextLink(_ urlString: String) async throws -> [OneDriveFile] {
                var currentURLString = urlString
                var collected: [OneDriveFile] = []
                
                while true {
                    guard let url = URL(string: currentURLString) else { break }
                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        throw OneDriveError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
                    }
                    
                    let responseObj = try decoder.decode(OneDriveParser.GraphResponse.self, from: data)
                    let pageFiles = try await processChildren(responseObj.value)
                    collected.append(contentsOf: pageFiles)
                    
                    if let next = responseObj.nextLink {
                        currentURLString = next
                    } else {
                        break
                    }
                }
                return collected
            }
        }

        let fetcher = RecursiveFetcher(token: token, startDate: startDate, endDate: endDate, totalItems: totalItemsToFetch, onProgress: { processed, total in
            Task { @MainActor in
                self.fetchProgress = min(Double(processed) / Double(total), 1.0)
                self.fetchedCount = processed
                self.totalCount = total
            }
        }, onTotalUpdate: { total in
            Task { @MainActor in
                self.totalCount = total
            }
        })

        // Process root children directly (already fetched with expand)
        var allFiles: [OneDriveFile] = []
        if let children = rootItem.children {
            let rootFiles = try await fetcher.processChildren(children)
            allFiles.append(contentsOf: rootFiles)
        }
        
        // Handle pagination if present
        if let nextLink = rootItem.childrenNextLink {
            let pagedFiles = try await fetcher.fetchNextLink(nextLink)
            allFiles.append(contentsOf: pagedFiles)
        }

        // Sort client-side because the photos view rejects server-side ordering.
        let sortedFiles = allFiles.sorted { lhs, rhs in
            let lhsDate = lhs.createdDateTime ?? Date.distantPast
            let rhsDate = rhs.createdDateTime ?? Date.distantPast

            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id < rhs.id
        }

        // Make sure the UI knows the final count of files
        Task { @MainActor in
            self.fetchProgress = 1.0
            self.fetchedCount = sortedFiles.count
            self.totalCount = sortedFiles.count
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

