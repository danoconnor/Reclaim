//
//  StoreService.swift
//  Reclaim
//
//  Created by Dan O'Connor on 2/28/26.
//

import Combine
import Foundation
import StoreKit

@MainActor
class StoreService: ObservableObject {
    static let productID = "com.danoconnor.Reclaim.unlockDeletion"
    
    @Published private(set) var isUnlocked = false
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?
    
    private var transactionListener: Task<Void, Error>?
    
    private var isDemoMode = false
    
    init() {
        transactionListener = listenForTransactions()
    }
    
    #if DEBUG
    /// Creates a demo StoreService with pre-configured state for UI tests/screenshots
    static func demo(isUnlocked: Bool) -> StoreService {
        let service = StoreService()
        service.isDemoMode = true
        service.isUnlocked = isUnlocked
        service.transactionListener?.cancel()
        service.transactionListener = nil
        return service
    }
    #endif
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: - Load Product
    
    func loadProduct() async {
        guard !isDemoMode else { return }
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    // MARK: - Check Entitlements
    
    func checkEntitlements() async {
        guard !isDemoMode else { return }
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                isUnlocked = true
                return
            }
        }
        isUnlocked = false
    }
    
    // MARK: - Purchase
    
    func purchase() async throws {
        guard let product else {
            throw StoreError.productNotFound
        }
        
        isPurchasing = true
        errorMessage = nil
        
        defer { isPurchasing = false }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            isUnlocked = true
            
        case .userCancelled:
            break
            
        case .pending:
            errorMessage = "Purchase is pending approval."
            
        @unknown default:
            throw StoreError.purchaseFailed
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchase() async {
        do {
            try await AppStore.sync()
            await checkEntitlements()
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Transaction Listener
    
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.handleTransactionUpdate(transaction)
                }
            }
        }
    }
    
    private func handleTransactionUpdate(_ transaction: Transaction) {
        guard transaction.productID == Self.productID else { return }
        
        if transaction.revocationDate != nil {
            isUnlocked = false
        } else {
            isUnlocked = true
        }
    }
    
    // MARK: - Verification
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Errors

enum StoreError: LocalizedError {
    case productNotFound
    case purchaseFailed
    case verificationFailed
    
    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "The product could not be found."
        case .purchaseFailed:
            return "The purchase could not be completed."
        case .verificationFailed:
            return "The transaction could not be verified."
        }
    }
}
