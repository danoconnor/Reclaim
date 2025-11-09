//
//  DeletionService.swift
//  PhotoCleanup
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
    
    private let photoLibraryService: PhotoLibraryService
    
    init(photoLibraryService: PhotoLibraryService) {
        self.photoLibraryService = photoLibraryService
    }
    
    // MARK: - Deletion
    
    func deletePhotos(_ photos: [PhotoItem], dryRun: Bool = false) async throws -> DeletionResult {
        guard !photos.isEmpty else {
            throw DeletionError.noPhotosToDelete
        }
        
        isDeleting = true
        deletionProgress = 0.0
        errorMessage = nil
        deletedCount = 0
        
        var successfulDeletions: [PhotoItem] = []
        var failedDeletions: [(PhotoItem, Error)] = []
        
        let totalPhotos = Double(photos.count)
        
        if dryRun {
            // Dry run - just log what would be deleted
            for (index, photo) in photos.enumerated() {
                let entry = DeletionLogEntry(
                    photo: photo,
                    timestamp: Date(),
                    success: true,
                    dryRun: true
                )
                deletionLog.append(entry)
                successfulDeletions.append(photo)
                
                deletionProgress = Double(index + 1) / totalPhotos
            }
        } else {
            // Actual deletion
            for (index, photo) in photos.enumerated() {
                do {
                    // Delete individual photo
                    try await photoLibraryService.deletePhotos([photo])
                    
                    let entry = DeletionLogEntry(
                        photo: photo,
                        timestamp: Date(),
                        success: true,
                        dryRun: false
                    )
                    deletionLog.append(entry)
                    successfulDeletions.append(photo)
                    deletedCount += 1
                    
                } catch {
                    let entry = DeletionLogEntry(
                        photo: photo,
                        timestamp: Date(),
                        success: false,
                        dryRun: false,
                        errorMessage: error.localizedDescription
                    )
                    deletionLog.append(entry)
                    failedDeletions.append((photo, error))
                }
                
                deletionProgress = Double(index + 1) / totalPhotos
            }
        }
        
        isDeleting = false
        
        return DeletionResult(
            totalAttempted: photos.count,
            successfulDeletions: successfulDeletions,
            failedDeletions: failedDeletions,
            dryRun: dryRun
        )
    }
    
    // MARK: - Batch Deletion with Safety
    
    func deleteBatch(_ photos: [PhotoItem], batchSize: Int = 10) async throws -> DeletionResult {
        guard !photos.isEmpty else {
            throw DeletionError.noPhotosToDelete
        }
        
        isDeleting = true
        deletionProgress = 0.0
        deletedCount = 0
        errorMessage = nil
        
        var allSuccessful: [PhotoItem] = []
        var allFailed: [(PhotoItem, Error)] = []
        
        let batches = photos.chunked(into: batchSize)
        let totalBatches = Double(batches.count)
        
        for (batchIndex, batch) in batches.enumerated() {
            do {
                try await photoLibraryService.deletePhotos(batch)
                
                for photo in batch {
                    let entry = DeletionLogEntry(
                        photo: photo,
                        timestamp: Date(),
                        success: true,
                        dryRun: false
                    )
                    deletionLog.append(entry)
                    allSuccessful.append(photo)
                    deletedCount += 1
                }
                
            } catch {
                // If batch fails, try individual deletions
                for photo in batch {
                    do {
                        try await photoLibraryService.deletePhotos([photo])
                        
                        let entry = DeletionLogEntry(
                            photo: photo,
                            timestamp: Date(),
                            success: true,
                            dryRun: false
                        )
                        deletionLog.append(entry)
                        allSuccessful.append(photo)
                        deletedCount += 1
                        
                    } catch let individualError {
                        let entry = DeletionLogEntry(
                            photo: photo,
                            timestamp: Date(),
                            success: false,
                            dryRun: false,
                            errorMessage: individualError.localizedDescription
                        )
                        deletionLog.append(entry)
                        allFailed.append((photo, individualError))
                    }
                }
            }
            
            deletionProgress = Double(batchIndex + 1) / totalBatches
        }
        
        isDeleting = false
        
        return DeletionResult(
            totalAttempted: photos.count,
            successfulDeletions: allSuccessful,
            failedDeletions: allFailed,
            dryRun: false
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
            let dryRunIndicator = entry.dryRun ? " (Dry Run)" : ""
            
            csv += "\"\(timestamp)\",\"\(filename)\",\(size),\"\(status)\(dryRunIndicator)\",\"\(error)\"\n"
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
    let dryRun: Bool
    
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
    let dryRun: Bool
    let errorMessage: String?
    
    init(photo: PhotoItem, timestamp: Date, success: Bool, dryRun: Bool, errorMessage: String? = nil) {
        self.photo = photo
        self.timestamp = timestamp
        self.success = success
        self.dryRun = dryRun
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

