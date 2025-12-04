//
//  SettingsView.swift
//  PhotoCleanup
//
//  Created by Dan O'Connor on 11/8/25.
//

import Photos
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var photoLibraryService: PhotoLibraryService
    @ObservedObject var oneDriveService: OneDriveService
    
    @AppStorage("matchingSensitivity") private var matchingSensitivity: MatchingSensitivity = .medium
    @AppStorage("requireConfirmation") private var requireConfirmation = true
    @AppStorage("enableDryRun") private var enableDryRun = false
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
                
                // Matching Settings
                Section {
                    Picker("Matching Sensitivity", selection: $matchingSensitivity) {
                        ForEach(MatchingSensitivity.allCases, id: \.self) { sensitivity in
                            Text(sensitivity.displayName).tag(sensitivity)
                        }
                    }
                    
                    Text(matchingSensitivityDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Photo Matching")
                }
                
                // Safety Settings
                Section {
                    Toggle("Require Confirmation", isOn: $requireConfirmation)
                    Toggle("Dry Run Mode", isOn: $enableDryRun)
                    
                    Text("Dry run mode will simulate deletions without actually removing photos.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Safety")
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
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/danoconnor/PhotoCleanup")!) {
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
    
    private var matchingSensitivityDescription: String {
        switch matchingSensitivity {
        case .low:
            return "Match only by filename. Fastest but least accurate."
        case .medium:
            return "Match by filename and file size. Good balance of speed and accuracy."
        case .high:
            return "Match by cryptographic hash. Most accurate but slowest."
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
    
    return SettingsView(
        photoLibraryService: photoService,
        oneDriveService: oneDrive
    )
}
