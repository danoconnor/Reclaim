//
//  SyncStatus.swift
//  PhotoCleanup
//
//  Created by Dan O'Connor on 11/8/25.
//

import Foundation

enum SyncState {
    case notChecked
    case checking
    case synced(oneDriveFileId: String)
    case notSynced
    case error(message: String)
}

struct SyncStatus: Identifiable {
    let id: String // Same as PhotoItem.id
    let photoItem: PhotoItem
    var state: SyncState
    var matchedOneDriveFile: OneDriveFile?
    var lastChecked: Date?
    
    var canDelete: Bool {
        // Can only delete if synced and not a favorite
        if case .synced = state {
            return !photoItem.isFavorite
        }
        return false
    }
}
