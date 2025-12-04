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
    
    private let photoLibraryService: PhotoLibraryService
    private let oneDriveService: OneDriveService
    
    init(photoLibraryService: PhotoLibraryService, oneDriveService: OneDriveService) {
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
                            computed = sha256Hex(of: data)
                        case .sha1:
                            computed = sha1Hex(of: data)
                        case .quickXor:
                            computed = quickXorHash(of: data)
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

    private func sha256Hex(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func sha1Hex(of data: Data) -> String {
        #if canImport(CryptoKit)
        // CryptoKit doesn't provide SHA1, so we implement a lightweight pure Swift SHA1 here.
        return Sha1.computeHex(data: data)
        #else
        return Sha1.computeHex(data: data)
        #endif
    }

    private func quickXorHash(of data: Data) -> String {
        // Implementation inspired by OneDrive quickXorHash algorithm specs.
        // quickXorHash produces a Base64 string from a 160-bit result.
        var arr = [UInt8](repeating: 0, count: 20) // 160 bits
        let bytes = [UInt8](data)
        for (index, b) in bytes.enumerated() {
            let offset = index % 20
            arr[offset] = arr[offset] ^ b
        }
        // Convert to Data then base64
        let hashData = Data(arr)
        return hashData.base64EncodedString()
    }
}

// MARK: - SHA1 Implementation (Simplified)

fileprivate enum Sha1 {
    static func computeHex(data: Data) -> String {
        var message = data
        let ml = UInt64(message.count * 8)
        // Append the bit '1' to the message
        message.append(0x80)
        // Append k bits '0', where k is the minimum number >= 0 such that (message length in bits + 64) mod 512 == 0
        while (message.count * 8) % 512 != 448 { message.append(0x00) }
        // Append length as 64-bit big-endian
        var mlBigEndian = ml.bigEndian
        withUnsafeBytes(of: &mlBigEndian) { message.append(contentsOf: $0) }

        // Initialize hash values
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        // Process in 512-bit chunks
        let chunkSize = 64
        for chunkStart in stride(from: 0, to: message.count, by: chunkSize) {
            let chunk = message[chunkStart ..< chunkStart + chunkSize]
            var words = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let start = chunk.index(chunk.startIndex, offsetBy: i * 4)
                let w = chunk[start..<chunk.index(start, offsetBy: 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                words[i] = w
            }
            for i in 16..<80 {
                let val = words[i-3] ^ words[i-8] ^ words[i-14] ^ words[i-16]
                words[i] = (val << 1) | (val >> 31)
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4

            for i in 0..<80 {
                var f: UInt32 = 0, k: UInt32 = 0
                switch i {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ words[i]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = temp
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }

        func wordToBytes(_ word: UInt32) -> [UInt8] {
            return [
                UInt8((word >> 24) & 0xff),
                UInt8((word >> 16) & 0xff),
                UInt8((word >> 8) & 0xff),
                UInt8(word & 0xff)
            ]
        }
        
        let digest = [h0, h1, h2, h3, h4].flatMap(wordToBytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
