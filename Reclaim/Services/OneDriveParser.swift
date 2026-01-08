//
//  OneDriveParser.swift
//  Reclaim
//
//  Created by Dan O'Connor on 12/3/25.
//

import Foundation

struct OneDriveParser {
    struct GraphResponse: Codable, Sendable {
        let value: [GraphFile]
        let nextLink: String?

        private enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }
    }

    struct GraphPhoto: Codable, Sendable {
        let takenDateTime: String?
    }

    struct GraphFile: Codable, Sendable {
        let id: String
        let name: String
        let size: Int64?
        let file: FileInfo?
        let fileSystemInfo: FileSystemInfo?
        let downloadUrl: String?
        let photo: GraphPhoto?
        let folder: FolderInfo?
        let bundle: BundleInfo?
        let children: [GraphFile]?
        let childrenNextLink: String?

        private enum CodingKeys: String, CodingKey {
            case id, name, size, file, fileSystemInfo, photo, folder, bundle
            case downloadUrl = "@microsoft.graph.downloadUrl"
            case children
            case childrenNextLink = "children@odata.nextLink"
        }

        struct FileInfo: Codable, Sendable {
            let hashes: Hashes?

            struct Hashes: Codable, Sendable {
                let quickXorHash: String?
                let sha1Hash: String?
                let sha256Hash: String?
            }
        }

        struct FileSystemInfo: Codable, Sendable {
            let createdDateTime: String?
            let lastModifiedDateTime: String?
        }

        struct FolderInfo: Codable, Sendable {
            let childCount: Int?
        }

        struct BundleInfo: Codable, Sendable {
            let childCount: Int?
            let bundleType: String?

            private enum CodingKeys: String, CodingKey {
                case childCount
                case bundleType
            }
        }
    }
    
    // nonisolated(unsafe): Static lazy properties are initialized once (thread-safe by Swift).
    // Thread-safe because: ISO8601DateFormatter is thread-safe for reading operations,
    // and these formatters are never mutated after initialization.
    private nonisolated(unsafe) static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    nonisolated static func parseDate(_ value: String?) -> Date? {
        guard let value = value else { return nil }
        return isoWithFractional.date(from: value) ?? iso.date(from: value)
    }
    
    nonisolated static func makeOneDriveFile(from graphFile: GraphFile, startDate: Date? = nil, endDate: Date? = nil) -> OneDriveFile? {
        guard graphFile.file != nil else { return nil }

        let takenDate = parseDate(graphFile.photo?.takenDateTime)
        let createdDate = takenDate ?? parseDate(graphFile.fileSystemInfo?.createdDateTime)
        let modifiedDate = parseDate(graphFile.fileSystemInfo?.lastModifiedDateTime)

        if let start = startDate {
            guard let created = createdDate, created >= start else { return nil }
        }
        if let end = endDate {
            guard let created = createdDate, created <= end else { return nil }
        }

        let hashValue: String?
        let hashAlgorithm: OneDriveHashAlgorithm?
        if let v = graphFile.file?.hashes?.sha256Hash { hashValue = v; hashAlgorithm = .sha256 }
        else if let v = graphFile.file?.hashes?.quickXorHash { hashValue = v; hashAlgorithm = .quickXor }
        else if let v = graphFile.file?.hashes?.sha1Hash { hashValue = v; hashAlgorithm = .sha1 }
        else { hashValue = nil; hashAlgorithm = nil }

        let fileSize = graphFile.size ?? 0

        return OneDriveFile(
            id: graphFile.id,
            name: graphFile.name,
            size: fileSize,
            createdDateTime: createdDate,
            lastModifiedDateTime: modifiedDate,
            downloadUrl: graphFile.downloadUrl,
            hashValue: hashValue,
            hashAlgorithm: hashAlgorithm
        )
    }
}
