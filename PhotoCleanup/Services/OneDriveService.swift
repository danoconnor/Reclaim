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
class OneDriveService: ObservableObject {
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
    
    func fetchPhotosFromOneDrive(folderPath: String = "/Pictures", startDate: Date? = nil, endDate: Date? = nil) async throws {
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
            // TODO: Implement Microsoft Graph API calls
            // Example endpoint: GET /me/drive/root:/Photos:/children
            // Filter for image files
            
            let files = try await fetchFilesFromGraphAPI(folderPath: folderPath, token: token, startDate: startDate, endDate: endDate)
            self.oneDriveFiles = files
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    private func fetchFilesFromGraphAPI(folderPath: String, token: String, startDate: Date? = nil, endDate: Date? = nil) async throws -> [OneDriveFile] {
        return try await fetchFilesRecursively(folderPath: folderPath, token: token, visitedPaths: [], startDate: startDate, endDate: endDate)
    }
    
    private func fetchFilesRecursively(folderPath: String, token: String, visitedPaths: Set<String>, startDate: Date? = nil, endDate: Date? = nil, depth: Int = 0) async throws -> [OneDriveFile] {
        // Safety: Limit recursion depth to prevent infinite loops
        guard depth < 50 else { return [] }
        
        // Prevent circular references
        guard !visitedPaths.contains(folderPath) else { return [] }
        
        var updatedVisitedPaths = visitedPaths
        updatedVisitedPaths.insert(folderPath)
        
        var allFiles: [OneDriveFile] = []

        // Percent-encode each path segment to handle spaces and unicode
        let encodedPath = folderPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderPath

        // Build OData query parameters
        var queryParams: [String] = []
        
        // $select to request only the fields we need
        queryParams.append("$select=id,name,size,createdDateTime,lastModifiedDateTime,file,folder,image,@microsoft.graph.downloadUrl")
        
        // $filter to limit results by date range (if specified)
        // Include ALL folders (so we can recurse) OR files within the date range
        if let start = startDate, let end = endDate {
            let iso = ISO8601DateFormatter()
            let startStr = iso.string(from: start)
            let endStr = iso.string(from: end)
            // Include folders OR files within date range
            let filterParam = "$filter=folder ne null or (createdDateTime ge \(startStr) and createdDateTime le \(endStr))"
            queryParams.append(filterParam)
        } else if let start = startDate {
            let iso = ISO8601DateFormatter()
            let startStr = iso.string(from: start)
            // Include folders OR files created after start date
            let filterParam = "$filter=folder ne null or createdDateTime ge \(startStr)"
            queryParams.append(filterParam)
        } else if let end = endDate {
            let iso = ISO8601DateFormatter()
            let endStr = iso.string(from: end)
            // Include folders OR files created before end date
            let filterParam = "$filter=folder ne null or createdDateTime le \(endStr)"
            queryParams.append(filterParam)
        }
        
        let queryString = queryParams.joined(separator: "&")
        var endpoint = "https://graph.microsoft.com/v1.0/me/drive/root:\(encodedPath):/children?\(queryString)"

        struct GraphResponse: Codable {
            let value: [GraphFile]
            let nextLink: String?

            private enum CodingKeys: String, CodingKey {
                case value
                case nextLink = "@odata.nextLink"
            }
        }

        struct GraphFile: Codable {
            let id: String
            let name: String
            let size: Int64
            let createdDateTime: String?
            let lastModifiedDateTime: String?
            let file: FileInfo?
            let folder: FolderFacet?
            let image: ImageFacet?
            let downloadUrl: String?

            private enum CodingKeys: String, CodingKey {
                case id, name, size, createdDateTime, lastModifiedDateTime, file, folder, image
                case downloadUrl = "@microsoft.graph.downloadUrl"
            }

            struct FileInfo: Codable {
                let hashes: Hashes?

                struct Hashes: Codable {
                    let quickXorHash: String?
                    let sha1Hash: String?
                    let sha256Hash: String?
                }
            }

            struct FolderFacet: Codable {
                let childCount: Int?
            }

            struct ImageFacet: Codable {
                let width: Int?
                let height: Int?
            }
        }

        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        var subdirectories: [String] = []

        // Paginate through all items in the current directory
        while true {
            guard let url = URL(string: endpoint) else { throw OneDriveError.invalidURL }
            var request = URLRequest(url: url)
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

            let responseObj = try decoder.decode(GraphResponse.self, from: data)

            // Process items: collect image files and identify subdirectories
            for graphFile in responseObj.value {
                // Check if this is a folder
                if graphFile.folder != nil {
                    let subfolderPath = "\(folderPath)/\(graphFile.name)"
                    subdirectories.append(subfolderPath)
                    continue
                }
                
                // Process files: check if it's an image
                let isImageByFacet = graphFile.image != nil
                let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff"]
                let fileExtension = (graphFile.name as NSString).pathExtension.lowercased()
                let isImageByExtension = imageExtensions.contains(fileExtension)
                guard isImageByFacet || isImageByExtension else { continue }

                let created = graphFile.createdDateTime.flatMap { iso.date(from: $0) }
                let modified = graphFile.lastModifiedDateTime.flatMap { iso.date(from: $0) }

                // No need for client-side filtering since we're using OData $filter
                // The server already filtered by date range

                // Determine which hash algorithm value we have (priority: sha256, quickXor, sha1)
                let hashValue: String?
                let hashAlgorithm: OneDriveHashAlgorithm?
                if let v = graphFile.file?.hashes?.sha256Hash { hashValue = v; hashAlgorithm = .sha256 }
                else if let v = graphFile.file?.hashes?.quickXorHash { hashValue = v; hashAlgorithm = .quickXor }
                else if let v = graphFile.file?.hashes?.sha1Hash { hashValue = v; hashAlgorithm = .sha1 }
                else { hashValue = nil; hashAlgorithm = nil }

                let file = OneDriveFile(
                    id: graphFile.id,
                    name: graphFile.name,
                    size: graphFile.size,
                    createdDateTime: created,
                    lastModifiedDateTime: modified,
                    downloadUrl: graphFile.downloadUrl,
                    hashValue: hashValue,
                    hashAlgorithm: hashAlgorithm
                )
                allFiles.append(file)
            }

            if let next = responseObj.nextLink {
                endpoint = next
                continue
            } else {
                break
            }
        }

        // Recursively process subdirectories
        for subfolderPath in subdirectories {
            let subFiles = try await fetchFilesRecursively(
                folderPath: subfolderPath,
                token: token,
                visitedPaths: updatedVisitedPaths,
                startDate: startDate,
                endDate: endDate,
                depth: depth + 1
            )
            allFiles.append(contentsOf: subFiles)
        }

        return allFiles
    }
    
    // MARK: - Download File
    
    func downloadFile(_ file: OneDriveFile) async throws -> Data {
        guard isAuthenticated, let token = accessToken else {
            throw OneDriveError.notAuthenticated
        }
        // If the file has a temporary downloadUrl provided by Graph, use it (no auth header needed).
        if let download = file.downloadUrl, let url = URL(string: download) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw OneDriveError.downloadFailed
            }
            return data
        }

        // Fallback to Graph content endpoint which requires the bearer token
        let endpoint = "https://graph.microsoft.com/v1.0/me/drive/items/\(file.id)/content"
        guard let url = URL(string: endpoint) else {
            throw OneDriveError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw OneDriveError.downloadFailed
        }

        return data
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
