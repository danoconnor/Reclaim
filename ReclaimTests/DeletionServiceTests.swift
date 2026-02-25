//
//  DeletionServiceTests.swift
//  ReclaimTests
//
//  Created by Dan O'Connor on 12/3/25.
//

import XCTest
@testable import Reclaim

@MainActor
class DeletionServiceTests: XCTestCase {
    var sut: DeletionService!
    var mockPhotoLibraryService: MockPhotoLibraryService!
    
    override func setUp() {
        super.setUp()
        mockPhotoLibraryService = MockPhotoLibraryService()
        sut = DeletionService(photoLibraryService: mockPhotoLibraryService)
    }
    
    override func tearDown() {
        sut = nil
        mockPhotoLibraryService = nil
        super.tearDown()
    }
    
    func testDeletePhotos_Success() async throws {
        // Setup
        let photo = PhotoItem(id: "1", asset: nil, creationDate: Date(), modificationDate: Date(), isFavorite: false, fileSize: 1000, filename: "IMG_001.JPG")
        
        // Act
        let result = try await sut.deletePhotos([photo])
        
        // Assert
        XCTAssertTrue(mockPhotoLibraryService.deletePhotosCalled)
        XCTAssertEqual(mockPhotoLibraryService.deletedPhotos.count, 1)
        XCTAssertEqual(mockPhotoLibraryService.deletedPhotos.first?.id, "1")
        XCTAssertEqual(result.successfulDeletions.count, 1)
    }
    
    func testDeletePhotos_MultiplPhotos_Success() async throws {
        // Setup
        let photos = (0..<25).map { i in
            PhotoItem(id: "\(i)", asset: nil, creationDate: Date(), modificationDate: Date(), isFavorite: false, fileSize: 1000, filename: "IMG_\(i).JPG")
        }
        
        // Act
        let result = try await sut.deletePhotos(photos)
        
        // Assert
        XCTAssertEqual(result.successfulDeletions.count, 25)
        XCTAssertEqual(result.failedDeletions.count, 0)
        XCTAssertEqual(mockPhotoLibraryService.deletedPhotos.count, 25)
    }
    
    func testExportDeletionLog_Format() {
        // Setup
        let photo = PhotoItem(id: "1", asset: nil, creationDate: Date(), modificationDate: Date(), isFavorite: false, fileSize: 1000, filename: "IMG_001.JPG")
        let entry = DeletionLogEntry(photo: photo, timestamp: Date(), success: true)
        sut.deletionLog = [entry]
        
        // Act
        let csv = sut.exportDeletionLog()
        
        // Assert
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3) // Header + 1 row + empty line
        XCTAssertEqual(lines[0], "Timestamp,Filename,Size,Status,Error")
        XCTAssertTrue(lines[1].contains("IMG_001.JPG"))
        XCTAssertTrue(lines[1].contains("Success"))
    }
}
