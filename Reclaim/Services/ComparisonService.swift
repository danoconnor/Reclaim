//
//  ComparisonService.swift
//  Reclaim
//
//  Created by Dan O'Connor on 11/8/25.
//

import Foundation
import CryptoKit
import Combine

@MainActor
class ComparisonService: ObservableObject {
    @Published var syncStatuses: [SyncStatus] = []
    @Published var isComparing = false
    @Published var comparisonProgress: Double = 0.0
    @Published var errorMessage: String?
    
    private let photoLibraryService: PhotoLibraryServiceProtocol
    private let oneDriveService: OneDriveServiceProtocol
    
    init(photoLibraryService: PhotoLibraryServiceProtocol, oneDriveService: OneDriveServiceProtocol) {
        self.photoLibraryService = photoLibraryService
        self.oneDriveService = oneDriveService
    }
    
    // MARK: - Comparison
    
    func comparePhotos(startDate: Date? = nil, endDate: Date? = nil) async throws {
        isComparing = true
        comparisonProgress = 0.0
        errorMessage = nil
        
        let sensitivity = MatchingSensitivity(rawValue: UserDefaults.standard.string(forKey: "matchingSensitivity") ?? "") ?? .medium
        
        do {
            // Fetch non-favorite photos from local library with date range filter
            let localPhotos = try await photoLibraryService.fetchNonFavoritePhotos(startDate: startDate, endDate: endDate)
            comparisonProgress = 0.2
            
            // Fetch photos from OneDrive with date range filter
            try await oneDriveService.fetchPhotosFromOneDrive(startDate: startDate, endDate: endDate)
            let oneDriveFiles = oneDriveService.oneDriveFiles
            comparisonProgress = 0.4

            // Build lookup structures for efficient matching
            let oneDriveFilesByName = Dictionary(grouping: oneDriveFiles, by: { $0.name })
            let oneDriveFilesBySize = Dictionary(grouping: oneDriveFiles, by: { $0.size })
            
            let totalPhotos = Double(localPhotos.count)
            var completedCount = 0
            
            // Use TaskGroup for concurrent comparison
            let newSyncStatuses = await withTaskGroup(of: SyncStatus?.self) { group in
                for photo in localPhotos {
                    group.addTask {
                        // Capture necessary data for the task
                        let matchedFile = (try? await self.findMatch(
                            for: photo,
                            in: oneDriveFiles,
                            byName: oneDriveFilesByName,
                            bySize: oneDriveFilesBySize,
                            sensitivity: sensitivity
                        )) ?? nil
                        
                        let state: SyncState
                        if let matched = matchedFile {
                            state = .synced(oneDriveFileId: matched.id)
                        } else {
                            state = .notSynced
                        }
                        
                        return SyncStatus(
                            id: photo.id,
                            photoItem: photo,
                            state: state,
                            matchedOneDriveFile: matchedFile,
                            lastChecked: Date()
                        )
                    }
                }
                
                var results: [SyncStatus] = []
                for await status in group {
                    if let status = status {
                        results.append(status)
                    }
                    completedCount += 1
                    
                    // Update progress periodically on main actor
                    if completedCount % 10 == 0 || completedCount == localPhotos.count {
                        let progress = 0.4 + (0.6 * Double(completedCount) / totalPhotos)
                        await MainActor.run {
                            self.comparisonProgress = progress
                        }
                    }
                }
                return results
            }
            
            self.syncStatuses = newSyncStatuses
            comparisonProgress = 1.0
            isComparing = false
            
        } catch {
            isComparing = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    nonisolated private func findMatch(
        for photo: PhotoItem,
        in oneDriveFiles: [OneDriveFile],
        byName: [String: [OneDriveFile]],
        bySize: [Int64: [OneDriveFile]],
        sensitivity: MatchingSensitivity
    ) async throws -> OneDriveFile? {

        let photoFileName = photo.filename
        var candidateNames = Set<String>([photoFileName])
        candidateNames.formUnion(candidateOneDriveNames(for: photo))

        var candidatesByName: [OneDriveFile] = []
        var seenCandidateIds = Set<String>()
        for name in candidateNames {
            guard let matches = byName[name] else { continue }
            for file in matches where seenCandidateIds.insert(file.id).inserted {
                candidatesByName.append(file)
            }
        }

        switch sensitivity {
        case .low:
            // Filename only
            return candidatesByName.first
            
        case .medium:
            // Filename + Size
            for candidate in candidatesByName {
                if candidate.size == photo.fileSize {
                    return candidate
                }
            }
            return nil
            
        case .high:
            // File Hash
            // First check size to narrow down candidates
            if let candidates = bySize[photo.fileSize] {
                let candidatesWithHash = candidates.filter { $0.hashValue != nil && $0.hashAlgorithm != nil }
                if !candidatesWithHash.isEmpty {
                    var localHashes: [OneDriveHashAlgorithm: String] = [:]

                    func localHash(for algorithm: OneDriveHashAlgorithm) async throws -> String {
                        if let existing = localHashes[algorithm] { return existing }
                        
                        // Fetch data (on MainActor via service)
                        let data = try await photoLibraryService.getPhotoData(for: photo)
                        
                        // Compute hash in background to avoid blocking MainActor
                        let computed = await Task.detached(priority: .userInitiated) {
                            switch algorithm {
                            case .sha256:
                                return HashUtils.sha256Hex(of: data)
                            case .sha1:
                                return HashUtils.sha1Hex(of: data)
                            case .quickXor:
                                return HashUtils.quickXorHash(of: data)
                            }
                        }.value
                        
                        localHashes[algorithm] = computed
                        return computed
                    }

                    for candidate in candidatesWithHash {
                        if let algo = candidate.hashAlgorithm, let remoteHash = candidate.hashValue {
                            let local = try await localHash(for: algo)
                            if local.caseInsensitiveCompare(remoteHash) == .orderedSame {
                                return candidate
                            }
                        }
                    }
                }
            }
            return nil
        }
    }

    nonisolated private func candidateOneDriveNames(for photo: PhotoItem) -> Set<String> {
        guard let date = photo.creationDate ?? photo.modificationDate else { return [] }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        let dateString = formatter.string(from: date)

        let fileExtension = (photo.filename as NSString).pathExtension
        let hasExtension = !fileExtension.isEmpty
        let lowercasedExtension = fileExtension.lowercased()

        var names: Set<String> = []

        func appendNames(using base: String) {
            guard !base.isEmpty else { return }
            if hasExtension {
                names.insert("\(base)_iOS.\(lowercasedExtension)")
                if lowercasedExtension != fileExtension {
                    names.insert("\(base)_iOS.\(fileExtension)")
                }
            } else {
                names.insert("\(base)_iOS")
            }
        }
        
        appendNames(using: dateString)
        
        return names
    }
    
    // MARK: - Statistics
    
    var totalPhotos: Int {
        syncStatuses.count
    }
    
    var syncedPhotosCount: Int {
        syncStatuses.filter { status in
            if case .synced = status.state {
                return true
            }
            return false
        }.count
    }
    
    var deletablePhotosCount: Int {
        syncStatuses.filter { $0.canDelete }.count
    }
    
    var totalDeletableSize: Int64 {
        syncStatuses
            .filter { $0.canDelete }
            .reduce(0) { $0 + $1.photoItem.fileSize }
    }
    
    func getDeletablePhotos() -> [PhotoItem] {
        syncStatuses
            .filter { $0.canDelete }
            .map { $0.photoItem }
    }
}

