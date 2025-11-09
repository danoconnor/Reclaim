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
    
    func fetchPhotosFromOneDrive(folderPath: String = "/Pictures") async throws {
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
            
            let files = try await fetchFilesFromGraphAPI(folderPath: folderPath, token: token)
            self.oneDriveFiles = files
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    private func fetchFilesFromGraphAPI(folderPath: String, token: String) async throws -> [OneDriveFile] {
        var allFiles: [OneDriveFile] = []

        // Percent-encode each path segment to handle spaces and unicode
        let encodedPath = folderPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderPath

        // Use $select to request only fields we need and include the download URL and image facet
        var endpoint = "https://graph.microsoft.com/v1.0/me/drive/root:\(encodedPath):/children?$select=id,name,size,createdDateTime,lastModifiedDateTime,file,image,@microsoft.graph.downloadUrl&$top=200"

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
            let image: ImageFacet?
            let downloadUrl: String?

            private enum CodingKeys: String, CodingKey {
                case id, name, size, createdDateTime, lastModifiedDateTime, file, image
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

            struct ImageFacet: Codable {
                let width: Int?
                let height: Int?
            }
        }

        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()

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

            let pageFiles = responseObj.value.compactMap { graphFile -> OneDriveFile? in
                // Prefer server-side image facet; fall back to extension check
                let isImageByFacet = graphFile.image != nil
                let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff"]
                let fileExtension = (graphFile.name as NSString).pathExtension.lowercased()
                let isImageByExtension = imageExtensions.contains(fileExtension)
                guard isImageByFacet || isImageByExtension else { return nil }

                let created = graphFile.createdDateTime.flatMap { iso.date(from: $0) }
                let modified = graphFile.lastModifiedDateTime.flatMap { iso.date(from: $0) }

                // Determine which hash algorithm value we have (priority: sha256, quickXor, sha1)
                let hashValue: String?
                let hashAlgorithm: OneDriveHashAlgorithm?
                if let v = graphFile.file?.hashes?.sha256Hash { hashValue = v; hashAlgorithm = .sha256 }
                else if let v = graphFile.file?.hashes?.quickXorHash { hashValue = v; hashAlgorithm = .quickXor }
                else if let v = graphFile.file?.hashes?.sha1Hash { hashValue = v; hashAlgorithm = .sha1 }
                else { hashValue = nil; hashAlgorithm = nil }

                return OneDriveFile(
                    id: graphFile.id,
                    name: graphFile.name,
                    size: graphFile.size,
                    createdDateTime: created,
                    lastModifiedDateTime: modified,
                    downloadUrl: graphFile.downloadUrl,
                    hashValue: hashValue,
                    hashAlgorithm: hashAlgorithm
                )
            }

            allFiles.append(contentsOf: pageFiles)

            if let next = responseObj.nextLink {
                endpoint = next
                continue
            } else {
                break
            }
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

