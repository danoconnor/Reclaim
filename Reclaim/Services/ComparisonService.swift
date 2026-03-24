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
    enum ComparisonPhase: Equatable {
        case idle
        case fetchingData
        case comparing
        case hashing
        
        var description: String {
            switch self {
            case .idle: return ""
            case .fetchingData: return "Fetching photos from device and OneDrive..."
            case .comparing: return "Comparing photos..."
            case .hashing: return "Computing file hashes..."
            }
        }
    }

    @Published var syncStatuses: [SyncStatus] = []
    @Published var isComparing = false
    @Published var currentPhase: ComparisonPhase = .idle
    @Published var comparisonProgress: Double = 0.0
    @Published var hashingCompletedCount: Int = 0
    @Published var hashingTotalCount: Int = 0
    @Published var errorMessage: String?
    
    private let photoLibraryService: PhotoLibraryServiceProtocol
    private let oneDriveService: OneDriveServiceProtocol
    
    init(photoLibraryService: PhotoLibraryServiceProtocol, oneDriveService: OneDriveServiceProtocol) {
        self.photoLibraryService = photoLibraryService
        self.oneDriveService = oneDriveService
    }
    
    #if DEBUG
    /// Creates a demo ComparisonService with pre-configured sync statuses for UI tests/screenshots
    static func demo(photoLibraryService: PhotoLibraryServiceProtocol, oneDriveService: OneDriveServiceProtocol, syncStatuses: [SyncStatus]) -> ComparisonService {
        let service = ComparisonService(photoLibraryService: photoLibraryService, oneDriveService: oneDriveService)
        service.syncStatuses = syncStatuses
        return service
    }
    #endif
    
    // MARK: - Comparison
    
    func comparePhotos(startDate: Date? = nil, endDate: Date? = nil) async throws {
        isComparing = true
        currentPhase = .fetchingData
        comparisonProgress = 0.0
        errorMessage = nil
        
        // Default to high sensitivity if not set
        // Note: this is not currently user-configurable in the UI, but can be set via UserDefaults for testing purposes
        // Leaving the sensitivity switching logic in place in case we want to add UI controls for this in the future
        let sensitivity = MatchingSensitivity(rawValue: UserDefaults.standard.string(forKey: "matchingSensitivity") ?? "") ?? .high
        
        do {
            // Fetch data concurrently - no longer need to pre-compute hashes
            async let localPhotosTask = photoLibraryService.fetchNonFavoritePhotos(startDate: startDate, endDate: endDate)
            async let oneDriveFetchTask = oneDriveService.fetchPhotosFromOneDrive(startDate: startDate, endDate: endDate)
            
            let (localPhotos, oneDriveFiles) = try await (localPhotosTask, oneDriveFetchTask)
            
            comparisonProgress = 0.0
            currentPhase = .comparing

            // Build lookup structures for efficient matching
            let oneDriveFilesByName = Dictionary(grouping: oneDriveFiles, by: { $0.name })
            let oneDriveFilesBySize = Dictionary(grouping: oneDriveFiles, by: { $0.size })
            
            let totalPhotos = Double(localPhotos.count)
            
            let newSyncStatuses: [SyncStatus]
            
            if sensitivity == .high {
                // For high sensitivity, use BatchProcessor to limit concurrency
                // and avoid loading too many full-resolution images into memory at once.
                currentPhase = .hashing
                hashingCompletedCount = 0
                hashingTotalCount = localPhotos.count
                let maxConcurrency = 4
                
                let results = await BatchProcessor.process(
                    items: localPhotos,
                    batchSize: maxConcurrency,
                    transform: { photo -> SyncStatus in
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
                    },
                    onBatchComplete: { count in
                        let progress = Double(count) / totalPhotos
                        Task { @MainActor in
                            self.comparisonProgress = progress
                            self.hashingCompletedCount = count
                        }
                    }
                )
                
                newSyncStatuses = results
            } else {
                // For low/medium sensitivity, no I/O needed — use TaskGroup for fast concurrent comparison
                var completedCount = 0
                
                newSyncStatuses = await withTaskGroup(of: SyncStatus?.self) { group in
                    for photo in localPhotos {
                        group.addTask {
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
                    let updateInterval = max(10, Int(totalPhotos / 100))
                    
                    for await status in group {
                        if let status = status {
                            results.append(status)
                        }
                        completedCount += 1
                        
                        if completedCount % updateInterval == 0 || completedCount == localPhotos.count {
                            let progress = Double(completedCount) / totalPhotos
                            await MainActor.run {
                                self.comparisonProgress = progress
                            }
                        }
                    }
                    return results
                }
            }
            
            self.syncStatuses = newSyncStatuses
            comparisonProgress = 1.0
            isComparing = false
            currentPhase = .idle
            
        } catch {
            isComparing = false
            currentPhase = .idle
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
            // File Hash — compute on demand using the algorithm OneDrive used
            // First check size to narrow down candidates
            if let candidates = bySize[photo.fileSize] {
                let candidatesWithHash = candidates.filter { $0.hashValue != nil && $0.hashAlgorithm != nil }
                if !candidatesWithHash.isEmpty {
                    // Load photo data once for all candidate comparisons
                    let data = try await photoLibraryService.getPhotoData(for: photo)
                    
                    // Group candidates by algorithm to avoid recomputing the same hash
                    var hashCache: [HashAlgorithm: String] = [:]
                    
                    for candidate in candidatesWithHash {
                        guard let algo = candidate.hashAlgorithm, let remoteHash = candidate.hashValue else {
                            continue
                        }
                        
                        // Compute hash on demand, caching per algorithm
                        let localHash: String
                        if let cached = hashCache[algo] {
                            localHash = cached
                        } else {
                            localHash = await Task.detached(priority: .userInitiated) {
                                switch algo {
                                case .sha256:
                                    return HashUtils.sha256Hex(of: data)
                                case .sha1:
                                    return HashUtils.sha1Hex(of: data)
                                case .quickXor:
                                    return HashUtils.quickXorHash(of: data)
                                }
                            }.value
                            hashCache[algo] = localHash
                        }
                        
                        if localHash.caseInsensitiveCompare(remoteHash) == .orderedSame {
                            return candidate
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
