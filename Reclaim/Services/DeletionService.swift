//
//  DeletionService.swift
//  Reclaim
//
//  Created by Dan O'Connor on 11/8/25.
//

import Foundation
import Combine

@MainActor
class DeletionService: ObservableObject {
    @Published var isDeleting = false
    @Published var deletionProgress: Double = 0.0
    @Published var deletedCount = 0
    @Published var errorMessage: String?
    @Published var deletionLog: [DeletionLogEntry] = []
    
    private let photoLibraryService: PhotoLibraryServiceProtocol
    
    init(photoLibraryService: PhotoLibraryServiceProtocol) {
        self.photoLibraryService = photoLibraryService
    }
    
    // MARK: - Deletion
    
    func deletePhotos(_ photos: [PhotoItem]) async throws -> DeletionResult {
        guard !photos.isEmpty else {
            throw DeletionError.noPhotosToDelete
        }
        
        isDeleting = true
        deletionProgress = 0.0
        deletedCount = 0
        errorMessage = nil
        
        // Delete all photos in a single call so iOS shows only one confirmation prompt
        do {
            try await photoLibraryService.deletePhotos(photos)
        } catch {
            isDeleting = false
            deletionProgress = 0.0
            deletedCount = 0
            throw error
        }
        
        for photo in photos {
            let entry = DeletionLogEntry(
                photo: photo,
                timestamp: Date(),
                success: true
            )
            deletionLog.append(entry)
            deletedCount += 1
        }
        deletionProgress = 1.0
        
        isDeleting = false
        
        return DeletionResult(
            totalAttempted: photos.count,
            successfulDeletions: photos,
            failedDeletions: []
        )
    }
    
    // MARK: - Export Log
    
    func exportDeletionLog() -> String {
        var csv = "Timestamp,Filename,Size,Status,Error\n"
        
        for entry in deletionLog {
            let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
            let filename = entry.photo.filename
            let size = entry.photo.fileSize
            let status = entry.success ? "Success" : "Failed"
            let error = entry.errorMessage ?? ""
            
            csv += "\"\(timestamp)\",\"\(filename)\",\(size),\"\(status)\",\"\(error)\"\n"
        }
        
        return csv
    }
    
    func clearLog() {
        deletionLog.removeAll()
        deletedCount = 0
    }
}

// MARK: - Supporting Types

struct DeletionResult {
    let totalAttempted: Int
    let successfulDeletions: [PhotoItem]
    let failedDeletions: [(PhotoItem, Error)]
    
    var successCount: Int {
        successfulDeletions.count
    }
    
    var failureCount: Int {
        failedDeletions.count
    }
    
    var successRate: Double {
        guard totalAttempted > 0 else { return 0.0 }
        return Double(successCount) / Double(totalAttempted)
    }
    
    var totalBytesFreed: Int64 {
        successfulDeletions.reduce(0) { $0 + $1.fileSize }
    }
}

struct DeletionLogEntry: Identifiable {
    let id = UUID()
    let photo: PhotoItem
    let timestamp: Date
    let success: Bool
    let errorMessage: String?
    
    init(photo: PhotoItem, timestamp: Date, success: Bool, errorMessage: String? = nil) {
        self.photo = photo
        self.timestamp = timestamp
        self.success = success
        self.errorMessage = errorMessage
    }
}

enum DeletionError: LocalizedError {
    case noPhotosToDelete
    case deletionInProgress
    
    var errorDescription: String? {
        switch self {
        case .noPhotosToDelete:
            return "No photos selected for deletion."
        case .deletionInProgress:
            return "A deletion operation is already in progress."
        }
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

