//
//  MainView.swift
//  Reclaim
//
//  Created by Dan O'Connor on 11/8/25.
//

import Combine
import Photos
import SwiftUI

struct MainView: View {
    @StateObject private var photoLibraryService = PhotoLibraryService()
    @StateObject private var oneDriveService = OneDriveService()
    @StateObject private var comparisonService: ComparisonService
    @StateObject private var deletionService: DeletionService
    @StateObject private var storeService = StoreService()
    
    @AppStorage("dateRangeFilter") private var dateRangeFilter = DateRangeFilter.allTime.rawValue
    @AppStorage("customStartDate") private var customStartDateTimestamp: Double = 0
    @AppStorage("customEndDate") private var customEndDateTimestamp: Double = Date().timeIntervalSince1970
    
    @State private var showingPhotoReview = false
    @State private var showingSettings = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeletionComplete = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingPaywall = false
    
    init() {
        let photoService = PhotoLibraryService()
        let oneDrive = OneDriveService()
        let comparison = ComparisonService(photoLibraryService: photoService, oneDriveService: oneDrive)
        let deletion = DeletionService(photoLibraryService: photoService)
        
        _photoLibraryService = StateObject(wrappedValue: photoService)
        _oneDriveService = StateObject(wrappedValue: oneDrive)
        _comparisonService = StateObject(wrappedValue: comparison)
        _deletionService = StateObject(wrappedValue: deletion)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Status Section
                statusSection
                
                Divider()
                
                // Date Filter Indicator
                if isDateFilterActive {
                    dateFilterIndicator
                    Divider()
                }
                
                // Statistics Section
                if !comparisonService.syncStatuses.isEmpty || comparisonService.currentPhase == .fetchingData {
                    statisticsSection
                    Divider()
                }
                
                // Action Buttons
                actionButtons
                
                Spacer()
            }
            .padding()
            .navigationTitle("Reclaim")
            //.navigationSubtitle("Get your storage back")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingPhotoReview) {
                PhotoReviewView(
                    comparisonService: comparisonService,
                    deletionService: deletionService,
                    storeService: storeService
                )
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    photoLibraryService: photoLibraryService,
                    oneDriveService: oneDriveService,
                    storeService: storeService
                )
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(storeService: storeService)
            }
            .task {
                await storeService.loadProduct()
                await storeService.checkEntitlements()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Confirm Deletion", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await performDeletion()
                    }
                }
            } message: {
                Text("Are you sure you want to delete \(comparisonService.deletablePhotosCount) photos? This will free up \(formatBytes(comparisonService.totalDeletableSize)).")
            }
            .alert("Deletion Complete", isPresented: $showingDeletionComplete) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Photos have been moved to the Recently Deleted album. To free up storage, go to Settings > General > iPhone Storage > Photos and empty the \"Recently Deleted\" album.")
            }
        }
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            // Photo Library Status
            HStack {
                Image(systemName: photoLibraryService.authorizationStatus == .authorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(photoLibraryService.authorizationStatus == .authorized ? .green : .red)
                Text("Photo Library")
                Spacer()
                Text(authorizationStatusText)
                    .foregroundColor(.secondary)
            }
            
            // OneDrive Status
            HStack {
                Image(systemName: oneDriveService.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(oneDriveService.isAuthenticated ? .green : .red)
                Text("OneDrive")
                Spacer()
                Text(oneDriveService.isAuthenticated ? "Connected" : "Not Connected")
                    .foregroundColor(.secondary)
            }
            
            // Comparison Status
            if comparisonService.isComparing {
                if comparisonService.currentPhase == .hashing {
                    ProgressView(value: comparisonService.comparisonProgress) {
                        Text(comparisonService.currentPhase.description)
                    }
                    Text("\(comparisonService.hashingCompletedCount) of \(comparisonService.hashingTotalCount) photos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if comparisonService.currentPhase == .comparing {
                    ProgressView(value: comparisonService.comparisonProgress) {
                        Text(comparisonService.currentPhase.description)
                    }
                } else if comparisonService.currentPhase == .fetchingData {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(comparisonService.currentPhase.description)
                    }
                } else {
                    ProgressView {
                        Text(comparisonService.currentPhase.description)
                    }
                }
            }
            
            // Deletion Status
            if deletionService.isDeleting {
                ProgressView(value: deletionService.deletionProgress) {
                    Text("Deleting Photos... (\(deletionService.deletedCount) deleted)")
                }
            }
        }
    }
    
    // MARK: - Date Filter Indicator
    
    private var dateFilterIndicator: some View {
        HStack {
            Image(systemName: "calendar.badge.clock")
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Date Filter Active")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(dateFilterDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Statistics Section
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
        
            HStack {
                StatisticView(
                    title: "Local Photos",
                    value: "\(photoLibraryService.loadedPhotoCount)",
                    icon: "photo.on.rectangle"
                )
                
                StatisticView(
                    title: "OneDrive Photos",
                    value: "\(oneDriveService.fetchedCount)",
                    icon: "cloud.fill",
                    color: .green
                )
            }
            
            HStack {
                StatisticView(
                    title: "Can Delete",
                    value: "\(comparisonService.deletablePhotosCount)",
                    icon: "trash.fill",
                    color: .orange,
                    isLoading: comparisonService.isComparing
                )
                
                StatisticView(
                    title: "Space to Free",
                    value: formatBytes(comparisonService.totalDeletableSize),
                    icon: "externaldrive.fill",
                    color: .blue,
                    isLoading: comparisonService.isComparing
                )
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Request Photo Library Access
            if photoLibraryService.authorizationStatus != .authorized {
                Button {
                    Task {
                        await requestPhotoLibraryAccess()
                    }
                } label: {
                    Label("Allow Photo Access", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Sign in to OneDrive
            if !oneDriveService.isAuthenticated {
                Button {
                    Task {
                        await signInToOneDrive()
                    }
                } label: {
                    Label("Sign in to OneDrive", systemImage: "cloud")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Start Scan
            Button {
                Task {
                    await startComparison()
                }
            } label: {
                Label("Scan for Synced Photos", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canStartScan || comparisonService.isComparing)
            
            // Review Photos
            Button {
                showingPhotoReview = true
            } label: {
                Label("Review Photos (\(comparisonService.deletablePhotosCount))", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(comparisonService.deletablePhotosCount == 0)
            
            // Quick Delete
            Button {
                if storeService.isUnlocked {
                    showingDeleteConfirmation = true
                } else {
                    showingPaywall = true
                }
            } label: {
                HStack {
                    Label("Delete All Synced Photos", systemImage: "trash")
                    if !storeService.isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(comparisonService.deletablePhotosCount == 0 || deletionService.isDeleting)
        }
    }
    
    // MARK: - Computed Properties
    
    private var authorizationStatusText: String {
        switch photoLibraryService.authorizationStatus {
        case .authorized:
            return "Authorized"
        case .limited:
            return "Limited"
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
    
    private var canStartScan: Bool {
        photoLibraryService.authorizationStatus == .authorized && oneDriveService.isAuthenticated
    }
    
    private var isDateFilterActive: Bool {
        dateRangeFilter != DateRangeFilter.allTime.rawValue
    }
    
    private var dateFilterDescription: String {
        let filter = DateRangeFilter(rawValue: dateRangeFilter) ?? .allTime
        switch filter {
        case .allTime:
            return "All photos"
        case .last30Days:
            return "Last 30 days"
        case .last6Months:
            return "Last 6 months"
        case .lastYear:
            return "Last year"
        case .custom:
            let startDate = Date(timeIntervalSince1970: customStartDateTimestamp)
            let endDate = Date(timeIntervalSince1970: customEndDateTimestamp)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }
    
    // MARK: - Actions
    
    private func requestPhotoLibraryAccess() async {
        let granted = await photoLibraryService.requestAuthorization()
        if !granted {
            errorMessage = "Photo library access was not granted. Please enable it in Settings."
            showingError = true
        }
    }
    
    private func signInToOneDrive() async {
        do {
            try await oneDriveService.authenticate()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func startComparison() async {
        do {
            // Get date range based on filter setting
            let filter = DateRangeFilter(rawValue: dateRangeFilter) ?? .allTime
            let customStart = customStartDateTimestamp > 0 ? Date(timeIntervalSince1970: customStartDateTimestamp) : nil
            let customEnd = customEndDateTimestamp > 0 ? Date(timeIntervalSince1970: customEndDateTimestamp) : nil
            let (startDate, endDate) = filter.getDateRange(customStart: customStart, customEnd: customEnd)
            
            try await comparisonService.comparePhotos(
                startDate: startDate,
                endDate: endDate
            )
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func performDeletion() async {
        do {
            let photos = comparisonService.getDeletablePhotos()
            _ = try await deletionService.deletePhotos(photos)
            
            // Show reminder about Recently Deleted album
            showingDeletionComplete = true
            
            // Refresh comparison after deletion with same date filter
            let filter = DateRangeFilter(rawValue: dateRangeFilter) ?? .allTime
            let customStart = customStartDateTimestamp > 0 ? Date(timeIntervalSince1970: customStartDateTimestamp) : nil
            let customEnd = customEndDateTimestamp > 0 ? Date(timeIntervalSince1970: customEndDateTimestamp) : nil
            let (startDate, endDate) = filter.getDateRange(customStart: customStart, customEnd: customEnd)
            
            try await comparisonService.comparePhotos(
                startDate: startDate,
                endDate: endDate
            )
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Statistic View

struct StatisticView: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .primary
    var isLoading: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 28, alignment: .leading)
            } else {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

#Preview {
    MainView()
}
