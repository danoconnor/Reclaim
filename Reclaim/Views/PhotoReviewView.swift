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
    
    @State private var selectedPhotos = Set<String>()
    @State private var showingDeleteConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedPhotoForPreview: PhotoItem?
    
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
            
            Spacer()
            
            Text("\(selectedPhotos.count) selected")
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button {
                deselectAll()
            } label: {
                Text("Deselect All")
            }
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
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Selected", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedPhotos.isEmpty || deletionService.isDeleting)
                
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
            
            // Dismiss if no more photos to review
            if deletableStatuses.isEmpty {
                dismiss()
            }
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
        let service = PhotoLibraryService()
        do {
            let image = try await service.getThumbnail(for: photoItem, size: CGSize(width: 200, height: 200))
            thumbnail = image
        } catch {
            // Failed to load thumbnail
            print("Failed to load thumbnail: \(error)")
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
    
    return PhotoReviewView(
        comparisonService: comparison,
        deletionService: deletion
    )
}
