//
//  MockOneDriveService.swift
//  PhotoCleanupTests
//
//  Created by Dan O'Connor on 12/3/25.
//

import Foundation
@testable import PhotoCleanup

class MockOneDriveService: OneDriveServiceProtocol {
    var oneDriveFiles: [OneDriveFile] = []
    var fetchPhotosFromOneDriveCalled = false
    
    func fetchPhotosFromOneDrive(startDate: Date?, endDate: Date?) async throws {
        fetchPhotosFromOneDriveCalled = true
    }
}
