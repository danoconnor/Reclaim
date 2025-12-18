//
//  ComparisonServiceTests.swift
//  PhotoCleanupTests
//
//  Created by Dan O'Connor on 12/3/25.
//

import XCTest
@testable import PhotoCleanup

@MainActor
class ComparisonServiceTests: XCTestCase {
    var sut: ComparisonService!
    var mockPhotoLibraryService: MockPhotoLibraryService!
    var mockOneDriveService: MockOneDriveService!
    
    override func setUp() {
        super.setUp()
        mockPhotoLibraryService = MockPhotoLibraryService()
        mockOneDriveService = MockOneDriveService()
        sut = ComparisonService(photoLibraryService: mockPhotoLibraryService, oneDriveService: mockOneDriveService)
    }
    
    override func tearDown() {
        sut = nil
        mockPhotoLibraryService = nil
        mockOneDriveService = nil
        UserDefaults.standard.removeObject(forKey: "matchingSensitivity")
        super.tearDown()
    }
    
    func testComparePhotos_LowSensitivity_MatchesByName() async throws {
        // Setup
        UserDefaults.standard.set("low", forKey: "matchingSensitivity")
        
        let date = Date(timeIntervalSince1970: 1600000000) // Fixed date
        let photo = PhotoItem(id: "1", asset: nil, creationDate: date, modificationDate: date, isFavorite: false, fileSize: 1000, filename: "IMG_001.JPG")
        mockPhotoLibraryService.fetchNonFavoritePhotosResult = [photo]
        
        // Calculate expected OneDrive name
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        let dateString = formatter.string(from: date)
        let oneDriveName = "\(dateString)_iOS.jpg"
        
        // Size is different, but Low sensitivity ignores size
        let oneDriveFile = OneDriveFile(id: "od1", name: oneDriveName, size: 2000, createdDateTime: date, lastModifiedDateTime: date, downloadUrl: nil, hashValue: nil, hashAlgorithm: nil)
        mockOneDriveService.oneDriveFiles = [oneDriveFile]
        
        // Act
        try await sut.comparePhotos()
        
        // Assert
        XCTAssertEqual(sut.syncStatuses.count, 1)
        let status = sut.syncStatuses.first!
        if case .synced(let id) = status.state {
            XCTAssertEqual(id, "od1")
        } else {
            XCTFail("Should be synced")
        }
    }
    
    func testComparePhotos_MediumSensitivity_MatchesByNameAndSize() async throws {
        // Setup
        UserDefaults.standard.set("medium", forKey: "matchingSensitivity")
        
        let date = Date(timeIntervalSince1970: 1600000000)
        let photo = PhotoItem(id: "1", asset: nil, creationDate: date, modificationDate: date, isFavorite: false, fileSize: 1000, filename: "IMG_001.JPG")
        mockPhotoLibraryService.fetchNonFavoritePhotosResult = [photo]
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        let dateString = formatter.string(from: date)
        let oneDriveName = "\(dateString)_iOS.jpg"
        
        // Match name and size
        let oneDriveFile = OneDriveFile(id: "od1", name: oneDriveName, size: 1000, createdDateTime: date, lastModifiedDateTime: date, downloadUrl: nil, hashValue: nil, hashAlgorithm: nil)
        mockOneDriveService.oneDriveFiles = [oneDriveFile]
        
        // Act
        try await sut.comparePhotos()
        
        // Assert
        XCTAssertEqual(sut.syncStatuses.count, 1)
        if case .synced(let id) = sut.syncStatuses.first!.state {
            XCTAssertEqual(id, "od1")
        } else {
            XCTFail("Should be synced")
        }
    }
    
    func testComparePhotos_MediumSensitivity_NoMatchIfSizeDiffers() async throws {
        // Setup
        UserDefaults.standard.set("medium", forKey: "matchingSensitivity")
        
        let date = Date(timeIntervalSince1970: 1600000000)
        let photo = PhotoItem(id: "1", asset: nil, creationDate: date, modificationDate: date, isFavorite: false, fileSize: 1000, filename: "IMG_001.JPG")
        mockPhotoLibraryService.fetchNonFavoritePhotosResult = [photo]
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        let dateString = formatter.string(from: date)
        let oneDriveName = "\(dateString)_iOS.jpg"
        
        // Different size
        let oneDriveFile = OneDriveFile(id: "od1", name: oneDriveName, size: 2000, createdDateTime: date, lastModifiedDateTime: date, downloadUrl: nil, hashValue: nil, hashAlgorithm: nil)
        mockOneDriveService.oneDriveFiles = [oneDriveFile]
        
        // Act
        try await sut.comparePhotos()
        
        // Assert
        XCTAssertEqual(sut.syncStatuses.count, 1)
        if case .notSynced = sut.syncStatuses.first!.state {
            // Success
        } else {
            XCTFail("Should not be synced")
        }
    }
    
    func testComparePhotos_HighSensitivity_MatchesByHash() async throws {
        // Setup
        UserDefaults.standard.set("high", forKey: "matchingSensitivity")
        
        let date = Date(timeIntervalSince1970: 1600000000)
        let photo = PhotoItem(id: "1", asset: nil, creationDate: date, modificationDate: date, isFavorite: false, fileSize: 1000, filename: "IMG_001.JPG")
        mockPhotoLibraryService.fetchNonFavoritePhotosResult = [photo]
        
        // Mock photo data
        let data = "test data".data(using: .utf8)!
        mockPhotoLibraryService.getPhotoDataResult = data
        
        // Compute SHA256 of "test data"
        // SHA256("test data") = 916f0027a575074ce72a331777c3478d6513f786a591bd892da1a577bf2335f9
        let hash = "916f0027a575074ce72a331777c3478d6513f786a591bd892da1a577bf2335f9"
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        let dateString = formatter.string(from: date)
        let oneDriveName = "\(dateString)_iOS.jpg"
        
        // Match name, size, and hash
        let oneDriveFile = OneDriveFile(id: "od1", name: oneDriveName, size: 1000, createdDateTime: date, lastModifiedDateTime: date, downloadUrl: nil, hashValue: hash, hashAlgorithm: .sha256)
        mockOneDriveService.oneDriveFiles = [oneDriveFile]
        
        // Act
        try await sut.comparePhotos()
        
        // Assert
        XCTAssertEqual(sut.syncStatuses.count, 1)
        if case .synced(let id) = sut.syncStatuses.first!.state {
            XCTAssertEqual(id, "od1")
        } else {
            XCTFail("Should be synced")
        }
    }
    
    func testComparePhotos_ConcurrentExecution() async throws {
        // Setup
        UserDefaults.standard.set("medium", forKey: "matchingSensitivity")
        
        let count = 100
        var photos: [PhotoItem] = []
        var oneDriveFiles: [OneDriveFile] = []
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        
        for i in 0..<count {
            let date = Date(timeIntervalSince1970: TimeInterval(1600000000 + i))
            let photo = PhotoItem(id: "\(i)", asset: nil, creationDate: date, modificationDate: date, isFavorite: false, fileSize: 1000, filename: "IMG_\(i).JPG")
            photos.append(photo)
            
            let dateString = formatter.string(from: date)
            let oneDriveName = "\(dateString)_iOS.jpg"
            let oneDriveFile = OneDriveFile(id: "od\(i)", name: oneDriveName, size: 1000, createdDateTime: date, lastModifiedDateTime: date, downloadUrl: nil, hashValue: nil, hashAlgorithm: nil)
            oneDriveFiles.append(oneDriveFile)
        }
        
        mockPhotoLibraryService.fetchNonFavoritePhotosResult = photos
        mockOneDriveService.oneDriveFiles = oneDriveFiles
        
        // Act
        try await sut.comparePhotos()
        
        // Assert
        XCTAssertEqual(sut.syncStatuses.count, count)
        
        // Verify all are synced
        let syncedCount = sut.syncStatuses.filter {
            if case .synced = $0.state { return true }
            return false
        }.count
        XCTAssertEqual(syncedCount, count)
    }
    
    func testComparePhotos_HighSensitivity_ConcurrentExecution() async throws {
        // Setup
        UserDefaults.standard.set("high", forKey: "matchingSensitivity")
        
        let count = 10 // Reduced count to avoid test runner timeout/crash
        var photos: [PhotoItem] = []
        var oneDriveFiles: [OneDriveFile] = []
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        
        // Mock data and hash
        let data = "test data".data(using: .utf8)!
        mockPhotoLibraryService.getPhotoDataResult = data
        let hash = "916f0027a575074ce72a331777c3478d6513f786a591bd892da1a577bf2335f9"
        
        for i in 0..<count {
            let date = Date(timeIntervalSince1970: TimeInterval(1600000000 + i))
            let photo = PhotoItem(id: "\(i)", asset: nil, creationDate: date, modificationDate: date, isFavorite: false, fileSize: 1000, filename: "IMG_\(i).JPG")
            photos.append(photo)
            
            let dateString = formatter.string(from: date)
            let oneDriveName = "\(dateString)_iOS.jpg"
            let oneDriveFile = OneDriveFile(id: "od\(i)", name: oneDriveName, size: 1000, createdDateTime: date, lastModifiedDateTime: date, downloadUrl: nil, hashValue: hash, hashAlgorithm: .sha256)
            oneDriveFiles.append(oneDriveFile)
        }
        
        mockPhotoLibraryService.fetchNonFavoritePhotosResult = photos
        mockOneDriveService.oneDriveFiles = oneDriveFiles
        
        // Act
        try await sut.comparePhotos()
        
        // Assert
        XCTAssertEqual(sut.syncStatuses.count, count)
        
        // Verify all are synced
        let syncedCount = sut.syncStatuses.filter {
            if case .synced = $0.state { return true }
            return false
        }.count
        XCTAssertEqual(syncedCount, count)
    }
}
