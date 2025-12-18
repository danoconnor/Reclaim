//
//  ServiceProtocols.swift
//  PhotoCleanup
//
//  Created by Dan O'Connor on 12/3/25.
//

import Foundation
import Combine
import Photos
import UIKit

protocol PhotoLibraryServiceProtocol: AnyObject {
    @MainActor func fetchNonFavoritePhotos(startDate: Date?, endDate: Date?) async throws -> [PhotoItem]
    func getPhotoData(for photoItem: PhotoItem) async throws -> Data
    @MainActor func deletePhotos(_ photoItems: [PhotoItem]) async throws
}

@MainActor
protocol OneDriveServiceProtocol: AnyObject {
    var oneDriveFiles: [OneDriveFile] { get }
    func fetchPhotosFromOneDrive(startDate: Date?, endDate: Date?) async throws
}
