# Reclaim - iOS Photo Management App

An iOS app that helps you free up device storage by identifying and deleting photos that have already been synced to OneDrive. Favorites are automatically protected.

## Features

- **Hash-Based Photo Matching**: Compares local photos with OneDrive backups using file hashes (QuickXorHash, SHA256, SHA1) for high-accuracy matching, with fallback to filename and size-based comparisons
- **Favorites Protection**: Automatically excludes photos marked as favorites from deletion
- **Photo Review**: Grid view with selection controls to review matched photos before deletion
- **Statistics Dashboard**: Real-time stats showing local photos, OneDrive photos, deletable count, and reclaimable storage
- **Date Range Filtering**: Filter scans by preset ranges (last 30 days, 6 months, year) or a custom date range
- **In-App Purchase**: One-time purchase ($2.99) to unlock the deletion feature
- **Deletion Log**: Exportable CSV log of all deletion operations
- **Demo/UI Test Mode**: Built-in demo data provider for screenshots and automated UI testing

## Architecture

### Models
- **PhotoItem**: Wraps a `PHAsset` with metadata (filename, size, dates, favorite status)
- **OneDriveFile**: Represents a file from the OneDrive Graph API, including hash values and algorithm type
- **SyncStatus**: Tracks sync state (`notChecked`, `checking`, `synced`, `notSynced`, `error`) for each photo
- **HashAlgorithm**: Enum for supported hash types (`sha256`, `sha1`, `quickXor`)
- **MatchingSensitivity**: Enum for matching strictness (`low` = filename only, `medium` = filename + size, `high` = file hash)

### Services
- **PhotoLibraryService**: Manages Photos framework access, fetches non-favorite photos, and handles deletion via `PHPhotoLibrary`
- **OneDriveService**: Authenticates via MSAL, recursively fetches photos from the OneDrive `special/photos` view with pagination support
- **AuthenticationProvider**: Protocol-based MSAL authentication with silent token refresh and interactive sign-in
- **ComparisonService**: Compares local photos against OneDrive files using configurable sensitivity; uses `BatchProcessor` for concurrency-limited hash computation
- **BatchProcessor**: Generic utility for processing items in order-preserving batches with limited concurrency
- **DeletionService**: Deletes matched photos in a single `PHPhotoLibrary` change request and maintains a deletion log
- **OneDriveParser**: Decodes Microsoft Graph API JSON responses into `OneDriveFile` models
- **HashUtils**: Computes SHA256, SHA1, and QuickXorHash digests for local photo data
- **StoreService**: Manages the non-consumable in-app purchase via StoreKit 2

### Views
- **MainView**: Dashboard with connection status, progress indicators, statistics, and action buttons
- **PhotoReviewView**: Grid view for reviewing and selectively deleting matched photos
- **SettingsView**: Account management, date range filter configuration, purchase management
- **PaywallView**: In-app purchase screen for unlocking deletion

### Demo
- **DemoDataProvider**: Generates synthetic photo/sync data for UI tests and App Store screenshots
- **DemoAuthenticationProvider**: No-op `AuthenticationProvider` for demo mode

## Requirements

- iOS 18.0+
- Xcode 16.0+
- Swift 6

## Dependencies

### Swift Package Manager

- **[MSAL for iOS](https://github.com/AzureAD/microsoft-authentication-library-for-objc)**: OAuth 2.0 authentication with Microsoft (personal accounts)

## Setup

See [SETUP_GUIDE.md](SETUP_GUIDE.md) for detailed Azure app registration and project configuration steps.

Quick summary:

1. Register an app in the [Azure Portal](https://portal.azure.com) with personal Microsoft account support
2. Add `Files.Read` delegated permission under Microsoft Graph
3. Set the redirect URI to `msauth.com.danoconnor.Reclaim://auth`
4. Add MSAL via Swift Package Manager
5. Build and run

## Usage

1. **Grant Permissions**: Tap "Allow Photo Access" to grant full photo library access
2. **Sign In**: Tap "Sign in to OneDrive" and authenticate with your Microsoft account
3. **Configure Date Filter** (optional): Go to Settings to limit the scan to a specific date range
4. **Scan Photos**: Tap "Scan for Synced Photos" to fetch OneDrive files and compare them with local photos
5. **Review**: Tap "Review Photos" to browse matched photos in a grid and select/deselect individual items
6. **Delete**: Tap "Delete Selected" or "Delete All Synced Photos" (requires in-app purchase)

## Safety Features

- **Favorites are always protected**: Photos marked as favorites are excluded from comparison results
- **Confirmation dialogs**: All deletion operations require explicit user confirmation
- **Single iOS prompt**: All selected photos are deleted in one `PHPhotoLibrary` change request, so iOS shows a single confirmation dialog
- **Deletion log**: All deletions are tracked with timestamps and exportable as CSV
- **Recently Deleted reminder**: After deletion, a reminder explains that photos must be permanently removed from the Recently Deleted album to reclaim storage

## Matching Strategy

The app uses a configurable matching sensitivity (defaults to **high**):

| Sensitivity | Method | Speed | Accuracy |
|---|---|---|---|
| **Low** | Filename only (including OneDrive rename patterns) | Fast | Lower |
| **Medium** | Filename + file size | Fast | Moderate |
| **High** (default) | File size + hash comparison (QuickXorHash/SHA256/SHA1) | Slower | Highest |

For **high** sensitivity, the app:
1. Groups OneDrive files by size to find candidates matching the local file size
2. Loads the local photo's original data and computes the hash using the same algorithm OneDrive used (QuickXorHash, SHA256, or SHA1)
3. Caches computed hashes per algorithm to avoid redundant computation
4. Confirms a match only when hashes are identical

## File Structure

```
Reclaim/
├── Models/
│   ├── HashAlgorithm.swift
│   ├── MatchingSensitivity.swift
│   ├── OneDriveFile.swift
│   ├── PhotoItem.swift
│   └── SyncStatus.swift
├── Services/
│   ├── AuthenticationProvider.swift
│   ├── BatchProcessor.swift
│   ├── ComparisonService.swift
│   ├── DeletionService.swift
│   ├── HashUtils.swift
│   ├── OneDriveParser.swift
│   ├── OneDriveService.swift
│   ├── PhotoLibraryService.swift
│   ├── ServiceProtocols.swift
│   └── StoreService.swift
├── Views/
│   ├── MainView.swift
│   ├── PaywallView.swift
│   ├── PhotoReviewView.swift
│   └── SettingsView.swift
├── Demo/
│   ├── DemoAuthenticationProvider.swift
│   └── DemoDataProvider.swift
├── ContentView.swift
├── ReclaimApp.swift
├── Info.plist
├── Products.storekit
└── Reclaim.entitlements
ReclaimTests/
├── BatchProcessorTests.swift
├── ComparisonServiceTests.swift
├── DeletionServiceTests.swift
├── HashUtilsTests.swift
├── OneDriveParserTests.swift
├── OneDriveServiceTests.swift
├── StoreServiceTests.swift
├── Mocks/
│   ├── MockOneDriveService.swift
│   ├── MockPhotoLibraryService.swift
│   └── MockStoreService.swift
└── Resources/
    └── quickXorHashTestData.json
ReclaimUITests/
├── ReclaimUITests.swift
└── ReclaimUITestsLaunchTests.swift
```

## Testing

The project includes unit tests for all services with mock implementations of `PhotoLibraryServiceProtocol`, `OneDriveServiceProtocol`, and `StoreServiceProtocol`. UI tests use a demo mode activated via the `-UITestMode` launch argument.

Run tests via Xcode or:
```bash
xcodebuild test -scheme Reclaim -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Known Limitations

- Single OneDrive account support only
- No background sync capability
- Video files are supported for matching but OneDrive hash availability varies

## Troubleshooting

### "Not Authorized" Error
- Go to iOS Settings → Privacy & Security → Photos → Reclaim
- Ensure "Full Access" is granted

### OneDrive Authentication Fails
- Verify the Client ID in `AuthenticationProvider.swift`
- Check that the redirect URI matches in both Azure Portal and `Info.plist`
- Ensure MSAL framework is properly added via SPM

### Photos Don't Match
- Photos must exist in OneDrive's special photos view (auto-created by OneDrive camera upload)
- Ensure photos have been fully uploaded to OneDrive before scanning
- The default high-sensitivity mode requires matching file hashes — files that were re-encoded or edited after upload may not match

## Privacy & Security

- Authentication tokens are stored in the iOS Keychain via MSAL
- No photo data is uploaded or transmitted — all comparison is performed locally on device
- OneDrive file metadata (names, sizes, hashes) is fetched read-only via Microsoft Graph API with `Files.Read` scope
- Deletion operations are logged locally only

MIT License - See LICENSE file for details

## Support

For issues, questions, or contributions, please open an issue on GitHub.

---

**⚠️ Important**: This app permanently deletes photos from your device. Always ensure your photos are properly backed up to OneDrive before using this app. The developers are not responsible for any data loss.
