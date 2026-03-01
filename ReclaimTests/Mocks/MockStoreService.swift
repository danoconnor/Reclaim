//
//  MockStoreService.swift
//  ReclaimTests
//
//  Created by Dan O'Connor on 2/28/26.
//

import Combine
import Foundation
import StoreKit
@testable import Reclaim

@MainActor
class MockStoreService: ObservableObject {
    @Published var isUnlocked: Bool
    @Published var product: Product?
    @Published var isPurchasing = false
    @Published var errorMessage: String?
    
    var purchaseCalled = false
    var restoreCalled = false
    var loadProductCalled = false
    var checkEntitlementsCalled = false
    
    /// When true, calling purchase() will set isUnlocked = true
    var shouldSucceedPurchase = true
    
    init(isUnlocked: Bool = false) {
        self.isUnlocked = isUnlocked
    }
    
    func loadProduct() async {
        loadProductCalled = true
    }
    
    func checkEntitlements() async {
        checkEntitlementsCalled = true
    }
    
    func purchase() async throws {
        purchaseCalled = true
        if shouldSucceedPurchase {
            isUnlocked = true
        } else {
            throw StoreError.purchaseFailed
        }
    }
    
    func restorePurchase() async {
        restoreCalled = true
    }
}
