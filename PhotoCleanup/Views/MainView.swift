//
//  MainView.swift
//  PhotoCleanup
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
    
    @AppStorage("dateRangeFilter") private var dateRangeFilter = DateRangeFilter.allTime.rawValue
    @AppStorage("customStartDate") private var customStartDateTimestamp: Double = 0
    @AppStorage("customEndDate") private var customEndDateTimestamp: Double = Date().timeIntervalSince1970
    
    @State private var showingPhotoReview = false
    @State private var showingSettings = false
    @State private var showingDeleteConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
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
                if !comparisonService.syncStatuses.isEmpty {
                    statisticsSection
                    Divider()
                }
                
                // Action Buttons
                actionButtons
                
                Spacer()
            }
            .padding()
            .navigationTitle("Photo Cleanup")
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
                    deletionService: deletionService
                )
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    photoLibraryService: photoLibraryService,
                    oneDriveService: oneDriveService
                )
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
                ProgressView(value: comparisonService.comparisonProgress) {
                    Text("Comparing Photos...")
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
                    title: "Total Photos",
                    value: "\(comparisonService.totalPhotos)",
                    icon: "photo.on.rectangle"
                )
                
                StatisticView(
                    title: "Synced",
                    value: "\(comparisonService.syncedPhotosCount)",
                    icon: "cloud.fill",
                    color: .green
                )
            }
            
            HStack {
                StatisticView(
                    title: "Can Delete",
                    value: "\(comparisonService.deletablePhotosCount)",
                    icon: "trash.fill",
                    color: .orange
                )
                
                StatisticView(
                    title: "Space to Free",
                    value: formatBytes(comparisonService.totalDeletableSize),
                    icon: "externaldrive.fill",
                    color: .blue
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
                showingDeleteConfirmation = true
            } label: {
                Label("Delete All Synced Photos", systemImage: "trash")
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
            _ = try await deletionService.deleteBatch(photos)
            
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
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
