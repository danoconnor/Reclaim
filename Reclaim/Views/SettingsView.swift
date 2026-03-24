//
//  SettingsView.swift
//  Reclaim
//
//  Created by Dan O'Connor on 11/8/25.
//

import Photos
import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var photoLibraryService: PhotoLibraryService
    @ObservedObject var oneDriveService: OneDriveService
    @ObservedObject var storeService: StoreService
    
    @AppStorage("dateRangeFilter") private var dateRangeFilter = DateRangeFilter.allTime.rawValue
    @AppStorage("customStartDate") private var customStartDateTimestamp: Double = 0
    @AppStorage("customEndDate") private var customEndDateTimestamp: Double = Date().timeIntervalSince1970
    
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    
    var body: some View {
        NavigationView {
            Form {
                // Account Section
                Section {
                    // Photo Library Status
                    HStack {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                        Spacer()
                        Text(photoLibraryStatusText)
                            .foregroundColor(.secondary)
                    }
                    
                    // OneDrive Status
                    HStack {
                        Label("OneDrive", systemImage: "cloud")
                        Spacer()
                        Text(oneDriveService.isAuthenticated ? "Connected" : "Not Connected")
                            .foregroundColor(.secondary)
                    }
                    
                    if oneDriveService.isAuthenticated {
                        Button(role: .destructive) {
                            oneDriveService.signOut()
                        } label: {
                            Text("Sign Out of OneDrive")
                        }
                    }
                } header: {
                    Text("Accounts")
                }
                
                // Date Range Settings
                Section {
                    Picker("Date Range", selection: $dateRangeFilter) {
                        ForEach(DateRangeFilter.allCases, id: \.rawValue) { filter in
                            Text(filter.displayName).tag(filter.rawValue)
                        }
                    }
                    
                    if dateRangeFilter == DateRangeFilter.custom.rawValue {
                        DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                            .onChange(of: customStartDate) { _, newValue in
                                customStartDateTimestamp = newValue.timeIntervalSince1970
                            }
                        
                        DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                            .onChange(of: customEndDate) { _, newValue in
                                customEndDateTimestamp = newValue.timeIntervalSince1970
                            }
                    }
                    
                    Text(dateRangeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Date Filter")
                }
                
                // Information Section
                Section {
                    HStack {
                        Text("Favorites")
                        Spacer()
                        Text("Always Protected")
                            .foregroundColor(.green)
                    }
                    
                    Text("Photos marked as favorites will never be deleted, even if they are synced to OneDrive.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Protection")
                }
                
                // Purchases Section
                Section {
                    HStack {
                        Label("Deletion", systemImage: "trash")
                        Spacer()
                        if storeService.isUnlocked {
                            Label("Unlocked", systemImage: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Text("Locked")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !storeService.isUnlocked {
                        if let product = storeService.product {
                            Button {
                                Task {
                                    try? await storeService.purchase()
                                }
                            } label: {
                                HStack {
                                    Text("Unlock Deletion")
                                    Spacer()
                                    Text(product.displayPrice)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .disabled(storeService.isPurchasing)
                        }
                    }
                    
                    Button {
                        Task {
                            await storeService.restorePurchase()
                        }
                    } label: {
                        Text("Restore Purchase")
                    }
                    .disabled(storeService.isPurchasing)
                    
                    if let error = storeService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Purchases")
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/danoconnor/Reclaim")!) {
                        HStack {
                            Text("GitHub Repository")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                    
                    Link(destination: URL(string: "https://support.microsoft.com")!) {
                        HStack {
                            Text("OneDrive Help")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settingsDoneButton")
                }
            }
            .onAppear {
                // Load custom dates from storage
                if customStartDateTimestamp > 0 {
                    customStartDate = Date(timeIntervalSince1970: customStartDateTimestamp)
                }
                if customEndDateTimestamp > 0 {
                    customEndDate = Date(timeIntervalSince1970: customEndDateTimestamp)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var photoLibraryStatusText: String {
        switch photoLibraryService.authorizationStatus {
        case .authorized:
            return "Authorized"
        case .limited:
            return "Limited Access"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var dateRangeDescription: String {
        let filter = DateRangeFilter(rawValue: dateRangeFilter) ?? .allTime
        switch filter {
        case .allTime:
            return "Process all photos in your library."
        case .last30Days:
            return "Only process photos from the last 30 days."
        case .last6Months:
            return "Only process photos from the last 6 months."
        case .lastYear:
            return "Only process photos from the last year."
        case .custom:
            return "Only process photos within your custom date range."
        }
    }
    

}

// MARK: - Date Range Filter

enum DateRangeFilter: String, CaseIterable {
    case allTime = "allTime"
    case last30Days = "last30Days"
    case last6Months = "last6Months"
    case lastYear = "lastYear"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .allTime:
            return "All Time"
        case .last30Days:
            return "Last 30 Days"
        case .last6Months:
            return "Last 6 Months"
        case .lastYear:
            return "Last Year"
        case .custom:
            return "Custom Range"
        }
    }
    
    func getDateRange(customStart: Date?, customEnd: Date?) -> (start: Date?, end: Date?) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .allTime:
            return (nil, nil)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)
            return (start, now)
        case .last6Months:
            let start = calendar.date(byAdding: .month, value: -6, to: now)
            return (start, now)
        case .lastYear:
            let start = calendar.date(byAdding: .year, value: -1, to: now)
            return (start, now)
        case .custom:
            return (customStart, customEnd)
        }
    }
}



#Preview {
    let photoService = PhotoLibraryService()
    let oneDrive = OneDriveService()
    let store = StoreService()
    
    return SettingsView(
        photoLibraryService: photoService,
        oneDriveService: oneDrive,
        storeService: store
    )
}
