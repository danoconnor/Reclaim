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
    
    @AppStorage("oneDriveFolderPath") private var oneDriveFolderPath = "/Pictures"
    @AppStorage("matchingSensitivity") private var matchingSensitivity = MatchingSensitivity.medium.rawValue
    @AppStorage("requireConfirmation") private var requireConfirmation = true
    @AppStorage("enableDryRun") private var enableDryRun = false
    
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
                
                // OneDrive Configuration
                Section {
                    HStack {
                        Text("Folder Path")
                        Spacer()
                        TextField("/Pictures", text: $oneDriveFolderPath)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Specify the OneDrive folder path where your photos are backed up.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("OneDrive Settings")
                }
                
                // Matching Settings
                Section {
                    Picker("Matching Sensitivity", selection: $matchingSensitivity) {
                        ForEach(MatchingSensitivity.allCases, id: \.rawValue) { sensitivity in
                            Text(sensitivity.displayName).tag(sensitivity.rawValue)
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
                    
                    Link(destination: URL(string: "https://github.com")!) {
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
    
    private var matchingSensitivityDescription: String {
        switch MatchingSensitivity(rawValue: matchingSensitivity) ?? .medium {
        case .low:
            return "Match only by filename. Fastest but less accurate."
        case .medium:
            return "Match by filename and file size. Good balance of speed and accuracy."
        case .high:
            return "Match by filename, size, and date. Most accurate but slower."
        }
    }
}

// MARK: - Matching Sensitivity

enum MatchingSensitivity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var displayName: String {
        switch self {
        case .low:
            return "Low (Filename only)"
        case .medium:
            return "Medium (Filename + Size)"
        case .high:
            return "High (Filename + Size + Date)"
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
