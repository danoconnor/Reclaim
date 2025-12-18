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
    var fetchPhotosFromOneDriveCalled = false
    
    func fetchPhotosFromOneDrive(startDate: Date?, endDate: Date?) async throws {
        fetchPhotosFromOneDriveCalled = true
    }
}
