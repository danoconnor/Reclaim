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

        switch sensitivity {
        case .low:
            return candidatesByName(for: photo, byName: byName).first

        case .medium:
            for candidate in candidatesByName(for: photo, byName: byName) {
                if candidate.size == photo.fileSize { return candidate }
            }
            return nil

        case .high:
            // First check size to narrow down candidates before doing any I/O
            if let candidates = bySize[photo.fileSize] {
                let candidatesWithHash = candidates.filter { $0.hashValue != nil && $0.hashAlgorithm != nil }
                if !candidatesWithHash.isEmpty {
                    let neededAlgorithms = Set(candidatesWithHash.compactMap { $0.hashAlgorithm })

                    // Stream photo data one chunk at a time to avoid loading the full file into memory
                    var sha256Hasher: HashUtils.StreamingSHA256? = neededAlgorithms.contains(.sha256) ? HashUtils.StreamingSHA256() : nil
                    var sha1Hasher: HashUtils.StreamingSHA1? = neededAlgorithms.contains(.sha1) ? HashUtils.StreamingSHA1() : nil
                    var quickXorHasher: HashUtils.StreamingQuickXor? = neededAlgorithms.contains(.quickXor) ? HashUtils.StreamingQuickXor() : nil

                    for try await chunk in photoLibraryService.streamPhotoData(for: photo) {
                        sha256Hasher?.update(chunk)
                        sha1Hasher?.update(chunk)
                        quickXorHasher?.update(chunk)
                    }

                    var hashCache: [HashAlgorithm: String] = [:]
                    if var h = sha256Hasher { hashCache[.sha256] = h.finalize() }
                    if var h = sha1Hasher { hashCache[.sha1] = h.finalize() }
                    if var h = quickXorHasher { hashCache[.quickXor] = h.finalize() }

                    for candidate in candidatesWithHash {
                        guard let algo = candidate.hashAlgorithm, let remoteHash = candidate.hashValue,
                              let localHash = hashCache[algo] else { continue }
                        if localHash.caseInsensitiveCompare(remoteHash) == .orderedSame {
                            return candidate
                        }
                    }
                }
            }
            return nil
        }
    }

    // Shared formatter — DateFormatter is thread-safe on iOS 7+ per Apple docs.
    private static let oneDriveDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd_HHmmssSSS"
        return f
    }()

    nonisolated private func candidatesByName(for photo: PhotoItem, byName: [String: [OneDriveFile]]) -> [OneDriveFile] {
        var candidateNames = Set<String>([photo.filename])
        candidateNames.formUnion(candidateOneDriveNames(for: photo))
        var result: [OneDriveFile] = []
        var seen = Set<String>()
        for name in candidateNames {
            guard let matches = byName[name] else { continue }
            for file in matches where seen.insert(file.id).inserted {
                result.append(file)
            }
        }
        return result
    }

    nonisolated private func candidateOneDriveNames(for photo: PhotoItem) -> Set<String> {
        guard let date = photo.creationDate ?? photo.modificationDate else { return [] }

        let dateString = Self.oneDriveDateFormatter.string(from: date)

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
