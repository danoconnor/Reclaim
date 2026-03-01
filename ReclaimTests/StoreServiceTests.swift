//
//  StoreServiceTests.swift
//  ReclaimTests
//
//  Created by Dan O'Connor on 2/28/26.
//

import XCTest
@testable import Reclaim

@MainActor
class StoreServiceTests: XCTestCase {
    var sut: MockStoreService!
    
    override func setUp() {
        super.setUp()
        sut = MockStoreService()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Initial State
    
    func testInitialState_IsLocked() {
        XCTAssertFalse(sut.isUnlocked)
        XCTAssertNil(sut.product)
        XCTAssertFalse(sut.isPurchasing)
        XCTAssertNil(sut.errorMessage)
    }
    
    func testInitialState_WithUnlocked() {
        let unlockedService = MockStoreService(isUnlocked: true)
        XCTAssertTrue(unlockedService.isUnlocked)
    }
    
    // MARK: - Purchase
    
    func testPurchase_Success_UnlocksService() async throws {
        XCTAssertFalse(sut.isUnlocked)
        
        try await sut.purchase()
        
        XCTAssertTrue(sut.purchaseCalled)
        XCTAssertTrue(sut.isUnlocked)
    }
    
    func testPurchase_Failure_RemainsLocked() async {
        sut.shouldSucceedPurchase = false
        
        do {
            try await sut.purchase()
            XCTFail("Expected purchase to throw")
        } catch {
            XCTAssertTrue(error is StoreError)
        }
        
        XCTAssertTrue(sut.purchaseCalled)
        XCTAssertFalse(sut.isUnlocked)
    }
    
    // MARK: - Restore
    
    func testRestorePurchase_CallsRestore() async {
        await sut.restorePurchase()
        XCTAssertTrue(sut.restoreCalled)
    }
    
    // MARK: - Load Product
    
    func testLoadProduct_CallsLoad() async {
        await sut.loadProduct()
        XCTAssertTrue(sut.loadProductCalled)
    }
    
    // MARK: - Check Entitlements
    
    func testCheckEntitlements_CallsCheck() async {
        await sut.checkEntitlements()
        XCTAssertTrue(sut.checkEntitlementsCalled)
    }
    
    // MARK: - StoreError Descriptions
    
    func testStoreError_ProductNotFound_HasDescription() {
        let error = StoreError.productNotFound
        XCTAssertEqual(error.errorDescription, "The product could not be found.")
    }
    
    func testStoreError_PurchaseFailed_HasDescription() {
        let error = StoreError.purchaseFailed
        XCTAssertEqual(error.errorDescription, "The purchase could not be completed.")
    }
    
    func testStoreError_VerificationFailed_HasDescription() {
        let error = StoreError.verificationFailed
        XCTAssertEqual(error.errorDescription, "The transaction could not be verified.")
    }
    
    // MARK: - Product ID
    
    func testProductID_IsCorrect() {
        XCTAssertEqual(StoreService.productID, "com.danoconnor.Reclaim.unlockDeletion")
    }
}

// MARK: - Deletion Gating Integration Tests

@MainActor
class DeletionGatingTests: XCTestCase {
    var mockPhotoLibraryService: MockPhotoLibraryService!
    var deletionService: DeletionService!
    var mockStoreService: MockStoreService!
    
    override func setUp() {
        super.setUp()
        mockPhotoLibraryService = MockPhotoLibraryService()
        deletionService = DeletionService(photoLibraryService: mockPhotoLibraryService)
        mockStoreService = MockStoreService()
    }
    
    override func tearDown() {
        deletionService = nil
        mockPhotoLibraryService = nil
        mockStoreService = nil
        super.tearDown()
    }
    
    private func makePhoto(id: String = "1") -> PhotoItem {
        PhotoItem(
            id: id,
            asset: nil,
            creationDate: Date(),
            modificationDate: Date(),
            isFavorite: false,
            fileSize: 5_000_000,
            filename: "IMG_\(id).JPG"
        )
    }
    
    // MARK: - Gating Logic
    
    func testDeletion_WhenUnlocked_Succeeds() async throws {
        mockStoreService.isUnlocked = true
        let photo = makePhoto()
        
        // Simulate what the view does: check isUnlocked, then call deletePhotos
        XCTAssertTrue(mockStoreService.isUnlocked)
        let result = try await deletionService.deletePhotos([photo])
        
        XCTAssertEqual(result.successCount, 1)
        XCTAssertTrue(mockPhotoLibraryService.deletePhotosCalled)
    }
    
    func testDeletion_WhenLocked_ShouldShowPaywall() {
        // Simulate the view's gating logic: if not unlocked, show paywall instead of deleting
        XCTAssertFalse(mockStoreService.isUnlocked)
        
        // The view would present the paywall here instead of calling deletePhotos
        // Verify the store service correctly reports locked state
        let shouldShowPaywall = !mockStoreService.isUnlocked
        XCTAssertTrue(shouldShowPaywall)
    }
    
    func testDeletion_AfterPurchase_Succeeds() async throws {
        // Start locked
        XCTAssertFalse(mockStoreService.isUnlocked)
        
        // Purchase
        try await mockStoreService.purchase()
        XCTAssertTrue(mockStoreService.isUnlocked)
        
        // Now deletion should proceed
        let photo = makePhoto()
        let result = try await deletionService.deletePhotos([photo])
        
        XCTAssertEqual(result.successCount, 1)
        XCTAssertTrue(mockPhotoLibraryService.deletePhotosCalled)
    }
    
    func testDeletion_AfterFailedPurchase_RemainsLocked() async {
        mockStoreService.shouldSucceedPurchase = false
        
        do {
            try await mockStoreService.purchase()
            XCTFail("Expected purchase to throw")
        } catch {
            // Expected
        }
        
        XCTAssertFalse(mockStoreService.isUnlocked)
        
        // Should still show paywall
        let shouldShowPaywall = !mockStoreService.isUnlocked
        XCTAssertTrue(shouldShowPaywall)
    }
    
    func testBulkDeletion_WhenUnlocked_DeletesAllPhotos() async throws {
        mockStoreService.isUnlocked = true
        let photos = (0..<10).map { makePhoto(id: "\($0)") }
        
        let result = try await deletionService.deletePhotos(photos)
        
        XCTAssertEqual(result.successCount, 10)
        XCTAssertEqual(result.failedDeletions.count, 0)
        XCTAssertEqual(mockPhotoLibraryService.deletedPhotos.count, 10)
    }
    
    func testDeletionResult_CalculatesTotalBytesFreed() async throws {
        mockStoreService.isUnlocked = true
        let photos = (0..<3).map { i in
            PhotoItem(
                id: "\(i)",
                asset: nil,
                creationDate: Date(),
                modificationDate: Date(),
                isFavorite: false,
                fileSize: 1_000_000,
                filename: "IMG_\(i).JPG"
            )
        }
        
        let result = try await deletionService.deletePhotos(photos)
        
        XCTAssertEqual(result.totalBytesFreed, 3_000_000)
    }
}
