//
//  PhotoLibraryService.swift
//  PhotoCleanup
//
//  Created by Dan O'Connor on 11/8/25.
//

import Photos
import UIKit
import Combine

@MainActor
class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var photos: [PhotoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
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
    
    func fetchAllPhotos() async throws {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw PhotoLibraryError.notAuthorized
        }
        
        isLoading = true
        errorMessage = nil
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var photoItems: [PhotoItem] = []
        fetchResult.enumerateObjects { asset, _, _ in
            photoItems.append(PhotoItem(asset: asset))
        }

        self.photos = photoItems
        isLoading = false
    }
    
    func fetchNonFavoritePhotos() async throws -> [PhotoItem] {
        try await fetchAllPhotos()
        return photos.filter { !$0.isFavorite }
    }
    
    // MARK: - Delete Photos
    
    func deletePhotos(_ photoItems: [PhotoItem]) async throws {
        guard authorizationStatus == .authorized else {
            throw PhotoLibraryError.notAuthorized
        }
        
        let assets = photoItems.map { $0.asset }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        }
    }
    
    // MARK: - Get Photo Data
    
    func getPhotoData(for photoItem: PhotoItem) async throws -> Data {
        let asset = photoItem.asset
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
    
    func getThumbnail(for photoItem: PhotoItem, size: CGSize) async throws -> UIImage {
        let asset = photoItem.asset
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
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
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photo library access not authorized. Please enable access in Settings."
        case .failedToFetchData:
            return "Failed to fetch photo data."
        }
    }
}

