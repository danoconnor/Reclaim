//
//  PhotoItem.swift
//  PhotoCleanup
//
//  Created by Dan O'Connor on 11/8/25.
//

import Foundation
import Photos

struct PhotoItem: Identifiable, Hashable {
    let id: String // PHAsset localIdentifier
    let asset: PHAsset
    let creationDate: Date?
    let modificationDate: Date?
    let isFavorite: Bool
    let fileSize: Int64
    let filename: String
    
    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.isFavorite = asset.isFavorite
        
        // Get file size from resources
        let resources = PHAssetResource.assetResources(for: asset)
        self.fileSize = resources.first?.value(forKey: "fileSize") as? Int64 ?? 0
        self.filename = resources.first?.originalFilename ?? "Unknown"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id
    }
}
