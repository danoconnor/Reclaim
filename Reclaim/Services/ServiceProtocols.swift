//
//  ServiceProtocols.swift
//  Reclaim
//
//  Created by Dan O'Connor on 12/3/25.
//

import Foundation
import Combine
import Photos
import StoreKit
import UIKit

protocol PhotoLibraryServiceProtocol: AnyObject {
    var loadedPhotoCount: Int { get }
    var totalPhotoCount: Int { get }
    @MainActor func fetchNonFavoritePhotos(startDate: Date?, endDate: Date?) async throws -> [PhotoItem]
    func getPhotoData(for photoItem: PhotoItem) async throws -> Data
    @MainActor func deletePhotos(_ photoItems: [PhotoItem]) async throws
}

@MainActor
protocol OneDriveServiceProtocol: AnyObject {
    var fetchProgress: Double { get }
    var fetchedCount: Int { get }
    var totalCount: Int { get }
    func fetchPhotosFromOneDrive(startDate: Date?, endDate: Date?) async throws -> [OneDriveFile]
}

@MainActor
protocol StoreServiceProtocol: AnyObject, ObservableObject {
    var isUnlocked: Bool { get }
    var product: Product? { get }
    var isPurchasing: Bool { get }
    var errorMessage: String? { get set }
    func loadProduct() async
    func checkEntitlements() async
    func purchase() async throws
    func restorePurchase() async
}
