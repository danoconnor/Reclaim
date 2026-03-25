//
//  DemoDataProvider.swift
//  Reclaim
//
//  Created for UI testing and screenshots.
//

#if DEBUG
import Foundation
import Photos

/// Provides demo data for UI tests and App Store screenshots
@MainActor
enum DemoDataProvider {
    
    /// Checks whether the app was launched in UI test demo mode
    static var isUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestMode")
    }
    
    /// Checks whether the deletion feature should appear unlocked
    static var isUnlocked: Bool {
        ProcessInfo.processInfo.arguments.contains("-Unlocked")
    }

    /// Returns the photo library authorization status to simulate
    static var photoAuthorizationStatus: PHAuthorizationStatus {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-PhotoAccessDenied") { return .denied }
        if args.contains("-PhotoAccessLimited") { return .limited }
        return .authorized
    }
    
    // MARK: - Demo Service Factory
    
    /// Creates a full set of pre-configured services for demo/screenshot mode
    static func createDemoServices() -> (
        photoLibraryService: PhotoLibraryService,
        oneDriveService: OneDriveService,
        comparisonService: ComparisonService,
        deletionService: DeletionService,
        storeService: StoreService
    ) {
        let demoPhotos = generateDemoPhotos()
        let syncStatuses = generateDemoSyncStatuses(from: demoPhotos)
        
        let photoService = PhotoLibraryService.demo(photoCount: demoPhotos.count, authorizationStatus: photoAuthorizationStatus)
        let oneDriveService = OneDriveService.demo(fileCount: demoPhotos.count + 3_840)
        let comparisonService = ComparisonService.demo(
            photoLibraryService: photoService,
            oneDriveService: oneDriveService,
            syncStatuses: syncStatuses
        )
        let deletionService = DeletionService(photoLibraryService: photoService)
        let storeService = StoreService.demo(isUnlocked: isUnlocked)
        
        return (photoService, oneDriveService, comparisonService, deletionService, storeService)
    }
    
    // MARK: - Demo Data Generation
    
    /// Total number of demo photos to generate — large enough to look impressive in screenshots
    private static let demoPhotoCount = 5_127
    
    private static func generateDemoPhotos() -> [PhotoItem] {
        let calendar = Calendar.current
        let now = Date()
        
        // Extensions cycle across photos for visual variety
        let extensions = ["HEIC", "HEIC", "HEIC", "JPG", "HEIC", "HEIC", "JPG", "HEIC"]
        
        // Seeded RNG so screenshots are deterministic across runs
        var rng = SeededRandomNumberGenerator(seed: 42)
        
        return (0..<demoPhotoCount).map { index in
            let ext = extensions[index % extensions.count]
            let filename = String(format: "IMG_%04d.%@", index + 1, ext)
            let daysAgo = index / 5  // ~5 photos per day, spanning ~1025 days
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            
            // Random file size between 1.5 MB and 12 MB (typical HEIC/JPG range)
            let fileSize = Int64.random(in: 1_500_000...12_000_000, using: &rng)
            
            return PhotoItem(
                id: "demo-photo-\(index)",
                asset: nil,
                creationDate: date,
                modificationDate: date,
                isFavorite: false,
                fileSize: fileSize,
                filename: filename
            )
        }
    }
    
    /// Deterministic PRNG so demo data is identical across launches
    private struct SeededRandomNumberGenerator: RandomNumberGenerator {
        private var state: UInt64
        
        init(seed: UInt64) {
            state = seed
        }
        
        mutating func next() -> UInt64 {
            // xorshift64
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }
    
    private static func generateDemoSyncStatuses(from photos: [PhotoItem]) -> [SyncStatus] {
        photos.enumerated().map { index, photo in
            let oneDriveFile = OneDriveFile(
                id: "onedrive-\(index)",
                name: photo.filename,
                size: photo.fileSize,
                createdDateTime: photo.creationDate,
                lastModifiedDateTime: photo.modificationDate,
                downloadUrl: nil,
                hashValue: nil,
                hashAlgorithm: nil
            )
            
            return SyncStatus(
                id: photo.id,
                photoItem: photo,
                state: .synced(oneDriveFileId: oneDriveFile.id),
                matchedOneDriveFile: oneDriveFile,
                lastChecked: Date()
            )
        }
    }
}
#endif
