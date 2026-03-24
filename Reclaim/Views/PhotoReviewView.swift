//
//  PhotoReviewView.swift
//  Reclaim
//
//  Created by Dan O'Connor on 11/8/25.
//

import SwiftUI
import Photos

struct PhotoReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var comparisonService: ComparisonService
    @ObservedObject var deletionService: DeletionService
    @ObservedObject var storeService: StoreService
    
    @State private var selectedPhotos = Set<String>()
    @State private var showingDeleteConfirmation = false
    @State private var showingDeletionComplete = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedPhotoForPreview: PhotoItem?
    @State private var showingPaywall = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]
    
    var deletableStatuses: [SyncStatus] {
        comparisonService.syncStatuses.filter { $0.canDelete }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Selection toolbar
                selectionToolbar
                
                Divider()
                
                // Photo grid
                if deletableStatuses.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(deletableStatuses) { status in
                                PhotoGridCell(
                                    photoItem: status.photoItem,
                                    isSelected: selectedPhotos.contains(status.id),
                                    onTap: {
                                        toggleSelection(status.id)
                                    },
                                    onLongPress: {
                                        selectedPhotoForPreview = status.photoItem
                                    }
                                )
                            }
                        }
                        .padding(2)
                        .accessibilityIdentifier("photoGrid")
                    }
                }
                
                Divider()
                
                // Action toolbar
                actionToolbar
            }
            .navigationTitle("Review Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedPhotoForPreview) { photo in
                PhotoPreviewView(photoItem: photo)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(storeService: storeService)
            }
            .alert("Confirm Deletion", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteSelectedPhotos()
                    }
                }
            } message: {
                Text("Are you sure you want to delete \(selectedPhotos.count) selected photos?")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Deletion Complete", isPresented: $showingDeletionComplete) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Photos have been moved to the Recently Deleted album. To free up storage, go to Settings > General > iPhone Storage > Photos and empty the \"Recently Deleted\" album.")
            }
        }
    }
    
    // MARK: - Selection Toolbar
    
    private var selectionToolbar: some View {
        HStack {
            Button {
                selectAll()
            } label: {
                Text("Select All")
            }
            .accessibilityIdentifier("selectAllButton")
            
            Spacer()
            
            Text("\(selectedPhotos.count) selected")
                .foregroundColor(.secondary)
                .accessibilityIdentifier("selectedCount")
            
            Spacer()
            
            Button {
                deselectAll()
            } label: {
                Text("Deselect All")
            }
            .accessibilityIdentifier("deselectAllButton")
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Action Toolbar
    
    private var actionToolbar: some View {
        VStack(spacing: 8) {
            if deletionService.isDeleting {
                ProgressView(value: deletionService.deletionProgress) {
                    Text("Deleting... (\(deletionService.deletedCount) of \(selectedPhotos.count))")
                }
                .padding(.horizontal)
            }
            
            HStack(spacing: 12) {
                Button {
                    if storeService.isUnlocked {
                        showingDeleteConfirmation = true
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    HStack {
                        Label("Delete Selected", systemImage: "trash")
                        if !storeService.isUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedPhotos.isEmpty || deletionService.isDeleting)
                .accessibilityIdentifier("deleteSelectedButton")
                
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("doneButton")
            }
            .padding()
        }
        .background(Color(.systemGray6))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("No Photos to Delete")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("All synced photos have been processed or no photos are ready for deletion.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func toggleSelection(_ id: String) {
        if selectedPhotos.contains(id) {
            selectedPhotos.remove(id)
        } else {
            selectedPhotos.insert(id)
        }
    }
    
    private func selectAll() {
        selectedPhotos = Set(deletableStatuses.map { $0.id })
    }
    
    private func deselectAll() {
        selectedPhotos.removeAll()
    }
    
    private func deleteSelectedPhotos() async {
        let photosToDelete = deletableStatuses
            .filter { selectedPhotos.contains($0.id) }
            .map { $0.photoItem }
        
        do {
            _ = try await deletionService.deletePhotos(photosToDelete)
            
            // Refresh comparison
            try await comparisonService.comparePhotos()
            
            // Clear selection
            selectedPhotos.removeAll()
            
            // Show reminder about Recently Deleted album
            showingDeletionComplete = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Photo Grid Cell

struct PhotoGridCell: View {
    let photoItem: PhotoItem
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    @State private var thumbnail: UIImage?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 100)
                    .overlay {
                        ProgressView()
                    }
            }
            
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .background(Circle().fill(Color.white))
                    .padding(4)
            }
        }
        .overlay {
            Rectangle()
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        }
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress()
        }
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        // If there's no PHAsset (e.g. demo mode), generate a placeholder
        guard photoItem.asset != nil else {
            thumbnail = Self.generatePlaceholder(for: photoItem)
            return
        }
        
        let service = PhotoLibraryService()
        do {
            let image = try await service.getThumbnail(for: photoItem, size: CGSize(width: 200, height: 200))
            thumbnail = image
        } catch {
            // Failed to load thumbnail — use placeholder as fallback
            thumbnail = Self.generatePlaceholder(for: photoItem)
        }
    }
    
    /// Generates a colored placeholder image based on the photo item's ID
    private static func generatePlaceholder(for photo: PhotoItem) -> UIImage {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Generate a deterministic color from the ID hash
            let hash = abs(photo.id.hashValue)
            let hue = CGFloat(hash % 360) / 360.0
            let saturation = CGFloat(40 + (hash / 360) % 30) / 100.0
            let brightness = CGFloat(65 + (hash / 10800) % 25) / 100.0
            
            let baseColor = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
            let lighterColor = UIColor(hue: hue, saturation: max(0, saturation - 0.15), brightness: min(1, brightness + 0.2), alpha: 1.0)
            
            // Draw gradient background
            let colors = [lighterColor.cgColor, baseColor.cgColor]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            
            // Draw a subtle landscape icon in the center
            let iconRect = CGRect(x: size.width * 0.25, y: size.height * 0.3, width: size.width * 0.5, height: size.height * 0.4)
            UIColor.white.withAlphaComponent(0.3).setFill()
            
            // Mountain shape
            let path = UIBezierPath()
            path.move(to: CGPoint(x: iconRect.minX, y: iconRect.maxY))
            path.addLine(to: CGPoint(x: iconRect.midX - 15, y: iconRect.minY + 10))
            path.addLine(to: CGPoint(x: iconRect.midX + 5, y: iconRect.midY))
            path.addLine(to: CGPoint(x: iconRect.maxX - 10, y: iconRect.minY + 20))
            path.addLine(to: CGPoint(x: iconRect.maxX, y: iconRect.maxY))
            path.close()
            path.fill()
            
            // Sun circle
            let sunRect = CGRect(x: iconRect.maxX - 30, y: iconRect.minY - 10, width: 24, height: 24)
            UIBezierPath(ovalIn: sunRect).fill()
        }
    }
}

// MARK: - Photo Preview View

struct PhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let photoItem: PhotoItem
    
    @State private var fullImage: UIImage?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = fullImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .navigationTitle(photoItem.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadFullImage()
            }
        }
    }
    
    private func loadFullImage() async {
        let service = PhotoLibraryService()
        do {
            let image = try await service.getThumbnail(for: photoItem, size: CGSize(width: 1000, height: 1000))
            fullImage = image
        } catch {
            print("Failed to load full image: \(error)")
        }
    }
}

#Preview {
    let photoService = PhotoLibraryService()
    let oneDrive = OneDriveService()
    let comparison = ComparisonService(photoLibraryService: photoService, oneDriveService: oneDrive)
    let deletion = DeletionService(photoLibraryService: photoService)
    let store = StoreService()
    
    return PhotoReviewView(
        comparisonService: comparison,
        deletionService: deletion,
        storeService: store
    )
}
