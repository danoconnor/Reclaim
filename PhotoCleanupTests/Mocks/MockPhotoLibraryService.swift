//
//  MockPhotoLibraryService.swift
//  PhotoCleanupTests
//
//  Created by Dan O'Connor on 12/3/25.
//

import Foundation
import Photos
@testable import PhotoCleanup

class MockPhotoLibraryService: PhotoLibraryServiceProtocol {
    var fetchNonFavoritePhotosResult: [PhotoItem] = []
    var getPhotoDataResult: Data = Data()
    var deletePhotosCalled = false
    var deletedPhotos: [PhotoItem] = []
    var fetchNonFavoritePhotosCalled = false
    
    func fetchNonFavoritePhotos(startDate: Date?, endDate: Date?) async throws -> [PhotoItem] {
        fetchNonFavoritePhotosCalled = true
        return fetchNonFavoritePhotosResult
    }
    
    func getPhotoData(for photoItem: PhotoItem) async throws -> Data {
        return getPhotoDataResult
    }
    
    func deletePhotos(_ photoItems: [PhotoItem]) async throws {
        deletePhotosCalled = true
        deletedPhotos = photoItems
    }
}
