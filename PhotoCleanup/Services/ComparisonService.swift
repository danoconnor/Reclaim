//
//  ComparisonService.swift
//  PhotoCleanup
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

    private static let oneDriveUTCFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        return formatter
    }()
    
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
            
            var newSyncStatuses: [SyncStatus] = []
            let totalPhotos = Double(localPhotos.count)
            
            // Compare each local photo
            for (index, photo) in localPhotos.enumerated() {
                let matchedFile = try await findMatch(
                    for: photo,
                    in: oneDriveFiles,
                    byName: oneDriveFilesByName,
                    bySize: oneDriveFilesBySize,
                    sensitivity: sensitivity
                )
                
                let state: SyncState
                if let matched = matchedFile {
                    state = .synced(oneDriveFileId: matched.id)
                } else {
                    state = .notSynced
                }
                
                let syncStatus = SyncStatus(
                    id: photo.id,
                    photoItem: photo,
                    state: state,
                    matchedOneDriveFile: matchedFile,
                    lastChecked: Date()
                )
                
                newSyncStatuses.append(syncStatus)
                
                // Update progress periodically to avoid blocking UI
                if index % 20 == 0 || index == localPhotos.count - 1 {
                    comparisonProgress = 0.4 + (0.6 * Double(index + 1) / totalPhotos)
                    // Yield to main thread to allow UI updates
                    await Task.yield()
                }
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
    
    private func findMatch(
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
                        let data = try await photoLibraryService.getPhotoData(for: photo)
                        let computed: String
                        switch algorithm {
                        case .sha256:
                            computed = HashUtils.sha256Hex(of: data)
                        case .sha1:
                            computed = HashUtils.sha1Hex(of: data)
                        case .quickXor:
                            computed = HashUtils.quickXorHash(of: data)
                        }
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

    private func candidateOneDriveNames(for photo: PhotoItem) -> Set<String> {
        guard let date = photo.creationDate ?? photo.modificationDate else { return [] }

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

        appendNames(using: Self.oneDriveUTCFormatter.string(from: date))

        return names
    }
    
    // MARK: - Hash Computation
    
    func computeHash(for photo: PhotoItem) async throws -> String {
        let data = try await photoLibraryService.getPhotoData(for: photo)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
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

    // MARK: - Hash Helpers

    // Hash implementations moved to HashUtils.swift
}

