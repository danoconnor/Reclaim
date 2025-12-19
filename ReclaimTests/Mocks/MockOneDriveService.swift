//
//  MockOneDriveService.swift
//  ReclaimTests
//
//  Created by Dan O'Connor on 12/3/25.
//

import Foundation
@testable import Reclaim

class MockOneDriveService: OneDriveServiceProtocol {
    var oneDriveFiles: [OneDriveFile] = []
    var fetchProgress: Double = 0.0
    var fetchedCount: Int = 0
    var totalCount: Int = 0
    var fetchPhotosFromOneDriveCalled = false
    
    func fetchPhotosFromOneDrive(startDate: Date?, endDate: Date?) async throws {
        fetchPhotosFromOneDriveCalled = true
    }
}
