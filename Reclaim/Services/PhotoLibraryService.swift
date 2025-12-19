//
//  PhotoLibraryService.swift
//  Reclaim
//
//  Created by Dan O'Connor on 11/8/25.
//

import Photos
import UIKit
import Combine

@MainActor
class PhotoLibraryService: ObservableObject, PhotoLibraryServiceProtocol {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var photos: [PhotoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var loadedPhotoCount: Int = 0
    @Published var totalPhotoCount: Int = 0
    
    init() {
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status == .authorized || status == .limited
    }
    
    // MARK: - Fetch Photos
    
    func fetchAllPhotos(startDate: Date? = nil, endDate: Date? = nil) async throws {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw PhotoLibraryError.notAuthorized
        }
        
        isLoading = true
        errorMessage = nil
        loadedPhotoCount = 0
        totalPhotoCount = 0
        
        // Run fetching and processing on a background thread to avoid blocking the UI
        let photoItems = await Task.detached(priority: .userInitiated) { [weak self] () -> [PhotoItem] in
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            // Apply date range predicate if provided
            if let start = startDate, let end = endDate {
                fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", start as NSDate, end as NSDate)
            } else if let start = startDate {
                fetchOptions.predicate = NSPredicate(format: "creationDate >= %@", start as NSDate)
            } else if let end = endDate {
                fetchOptions.predicate = NSPredicate(format: "creationDate <= %@", end as NSDate)
            }

            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            
            await MainActor.run {
                self?.totalPhotoCount = fetchResult.count
            }

            var items: [PhotoItem] = []
            var processedCount = 0
            
            fetchResult.enumerateObjects { asset, _, _ in
                items.append(PhotoItem(asset: asset))
                processedCount += 1
                
                if processedCount % 50 == 0 {
                    let currentCount = processedCount
                    Task { @MainActor in
                        self?.loadedPhotoCount = currentCount
                    }
                }
            }
            
            let finalCount = processedCount
            Task { @MainActor in
                self?.loadedPhotoCount = finalCount
            }
            
            return items
        }.value

        self.photos = photoItems
        isLoading = false
    }
    
    func fetchNonFavoritePhotos(startDate: Date? = nil, endDate: Date? = nil) async throws -> [PhotoItem] {
        try await fetchAllPhotos(startDate: startDate, endDate: endDate)
        return photos.filter { !$0.isFavorite }
    }
    
    // MARK: - Delete Photos
    
    func deletePhotos(_ photoItems: [PhotoItem]) async throws {
        guard authorizationStatus == .authorized else {
            throw PhotoLibraryError.notAuthorized
        }
        
        let assets = photoItems.compactMap { $0.asset }
        guard !assets.isEmpty else { return }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        }
    }
    
    // MARK: - Get Photo Data
    
    nonisolated func getPhotoData(for photoItem: PhotoItem) async throws -> Data {
        guard let asset = photoItem.asset else {
            throw PhotoLibraryError.assetNotFound
        }
        
        let options = PHImageRequestOptions()
        options.version = .original
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.failedToFetchData)
                }
            }
        }
    }
    
    nonisolated func getThumbnail(for photoItem: PhotoItem, size: CGSize) async throws -> UIImage {
        guard let asset = photoItem.asset else {
            throw PhotoLibraryError.assetNotFound
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.failedToFetchData)
                }
            }
        }
    }
}

// MARK: - Errors

enum PhotoLibraryError: LocalizedError {
    case notAuthorized
    case failedToFetchData
    case assetNotFound
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photo library access not authorized. Please enable access in Settings."
        case .failedToFetchData:
            return "Failed to fetch photo data."
        case .assetNotFound:
            return "Photo asset not found."
        }
    }
}
