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
    private let lock = NSLock()
    
    private var _fetchNonFavoritePhotosResult: [PhotoItem] = []
    var fetchNonFavoritePhotosResult: [PhotoItem] {
        get { lock.withLock { _fetchNonFavoritePhotosResult } }
        set { lock.withLock { _fetchNonFavoritePhotosResult = newValue } }
    }
    
    private var _getPhotoDataResult: Data = Data()
    var getPhotoDataResult: Data {
        get { lock.withLock { _getPhotoDataResult } }
        set { lock.withLock { _getPhotoDataResult = newValue } }
    }
    
    private var _deletePhotosCalled = false
    var deletePhotosCalled: Bool {
        get { lock.withLock { _deletePhotosCalled } }
        set { lock.withLock { _deletePhotosCalled = newValue } }
    }
    
    private var _deletedPhotos: [PhotoItem] = []
    var deletedPhotos: [PhotoItem] {
        get { lock.withLock { _deletedPhotos } }
        set { lock.withLock { _deletedPhotos = newValue } }
    }
    
    private var _fetchNonFavoritePhotosCalled = false
    var fetchNonFavoritePhotosCalled: Bool {
        get { lock.withLock { _fetchNonFavoritePhotosCalled } }
        set { lock.withLock { _fetchNonFavoritePhotosCalled = newValue } }
    }
    
    func fetchNonFavoritePhotos(startDate: Date?, endDate: Date?) async throws -> [PhotoItem] {
        self.fetchNonFavoritePhotosCalled = true
        return self.fetchNonFavoritePhotosResult
    }
    
    func getPhotoData(for photoItem: PhotoItem) async throws -> Data {
        return self.getPhotoDataResult
    }
    
    func deletePhotos(_ photoItems: [PhotoItem]) async throws {
        self.deletePhotosCalled = true
        self.deletedPhotos = photoItems
    }
}
