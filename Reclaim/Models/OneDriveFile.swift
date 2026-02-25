//
//  OneDriveFile.swift
//  Reclaim
//
//  Created by Dan O'Connor on 11/8/25.
//

import Foundation

struct OneDriveFile: Identifiable, Hashable, Sendable {
    let id: String // OneDrive item ID
    let name: String
    let size: Int64
    let createdDateTime: Date?
    let lastModifiedDateTime: Date?
    let downloadUrl: String?
    let hashValue: String? // Hash value from Graph (sha256/sha1/quickXorHash)
    let hashAlgorithm: HashAlgorithm? // Which algorithm produced hashValue
    
    nonisolated init(id: String, name: String, size: Int64, createdDateTime: Date?, lastModifiedDateTime: Date?, downloadUrl: String?, hashValue: String?, hashAlgorithm: HashAlgorithm?) {
        self.id = id
        self.name = name
        self.size = size
        self.createdDateTime = createdDateTime
        self.lastModifiedDateTime = lastModifiedDateTime
        self.downloadUrl = downloadUrl
        self.hashValue = hashValue
        self.hashAlgorithm = hashAlgorithm
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: OneDriveFile, rhs: OneDriveFile) -> Bool { lhs.id == rhs.id }
}
