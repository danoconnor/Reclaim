//
//  PaywallView.swift
//  Reclaim
//
//  Created by Dan O'Connor on 2/28/26.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var storeService: StoreService
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()
                
                // Icon
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                // Title
                Text("Unlock Deletion")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Description
                Text("Purchase to unlock the ability to delete synced photos from your device and reclaim your storage space.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                // Features list
                VStack(alignment: .leading, spacing: 12) {
                    featureRow(icon: "trash.fill", text: "Delete synced photos from your device")
                    featureRow(icon: "arrow.clockwise", text: "Bulk delete or selectively review")
                    featureRow(icon: "infinity", text: "One-time purchase, unlocked forever")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // Purchase button
                if let product = storeService.product {
                    Button {
                        Task {
                            do {
                                try await storeService.purchase()
                                if storeService.isUnlocked {
                                    dismiss()
                                }
                            } catch {
                                // Error is set on storeService.errorMessage
                            }
                        }
                    } label: {
                        if storeService.isPurchasing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Purchase for \(product.displayPrice)")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(storeService.isPurchasing)
                    .padding(.horizontal)
                    .accessibilityIdentifier("purchaseButton")
                } else {
                    ProgressView("Loading...")
                }
                
                // Restore button
                Button {
                    Task {
                        await storeService.restorePurchase()
                        if storeService.isUnlocked {
                            dismiss()
                        }
                    }
                } label: {
                    Text("Restore Purchase")
                        .font(.subheadline)
                }
                .disabled(storeService.isPurchasing)
                .accessibilityIdentifier("paywallRestoreButton")
                
                // Error message
                if let error = storeService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("paywallCancelButton")
                }
            }
            .task {
                if storeService.product == nil {
                    await storeService.loadProduct()
                }
            }
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    PaywallView(storeService: StoreService())
}
