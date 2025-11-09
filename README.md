# PhotoCleanup - iOS Photo Management App

An iOS app that helps you free up storage space by identifying and deleting photos from your device that have already been synced to OneDrive, while automatically protecting your favorite photos.

## Features

- **Smart Photo Comparison**: Compares local photos with OneDrive backups using multiple matching strategies (filename, size, date)
- **Favorites Protection**: Automatically excludes favorite photos from deletion
- **Safe Deletion**: Batch deletion with progress tracking and error handling
- **Photo Review**: Grid view to review and select photos before deletion
- **Statistics Dashboard**: See total photos, synced photos, and potential storage savings
- **Dry Run Mode**: Test deletion without actually removing photos
- **Deletion Log**: Export CSV log of all deletion operations

## Architecture

### Models
- **PhotoItem**: Represents a local photo with metadata
- **OneDriveFile**: Represents a file in OneDrive
- **SyncStatus**: Tracks sync state for each photo

### Services
- **PhotoLibraryService**: Manages Photo Library access and operations
- **OneDriveService**: Handles OneDrive authentication and API calls
- **ComparisonService**: Compares local photos with OneDrive files
- **DeletionService**: Safely deletes photos with logging

### Views
- **MainView**: Dashboard with status, statistics, and action buttons
- **PhotoReviewView**: Grid view for reviewing and selecting photos
- **SettingsView**: Configuration and account management

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Dependencies

### Required CocoaPods/SPM Packages

1. **Microsoft Authentication Library (MSAL) for iOS**
   - Used for OAuth 2.0 authentication with Microsoft
   - Add via SPM: `https://github.com/AzureAD/microsoft-authentication-library-for-objc`

2. **Microsoft Graph SDK for iOS** (Optional but recommended)
   - Simplifies Graph API calls
   - Add via SPM: `https://github.com/microsoftgraph/msgraph-sdk-objc`

## Setup Instructions

### 1. Register Your App with Microsoft Azure

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to "Azure Active Directory" → "App registrations" → "New registration"
3. Configure your app:
   - Name: PhotoCleanup
   - Supported account types: Personal Microsoft accounts only
   - Redirect URI: `msauth.[YOUR-BUNDLE-ID]://auth`
4. After registration, note down the **Application (client) ID**
5. Under "Authentication", add the iOS platform and configure:
   - Bundle ID: Your app's bundle identifier
   - Redirect URI: `msauth.[YOUR-BUNDLE-ID]://auth`
6. Under "API permissions", add:
   - Microsoft Graph → Delegated permissions → `Files.Read`
   - Microsoft Graph → Delegated permissions → `User.Read`

### 2. Update the Project

1. Open `Info.plist` and replace `YOUR-BUNDLE-ID` with your actual bundle identifier
2. Open `PhotoCleanup/Services/OneDriveService.swift`
3. Replace `YOUR_CLIENT_ID` with your Application (client) ID from Azure

### 3. Add Dependencies

Using Swift Package Manager:
1. In Xcode, go to File → Add Package Dependencies
2. Add MSAL: `https://github.com/AzureAD/microsoft-authentication-library-for-objc`
3. Add Microsoft Graph SDK (optional): `https://github.com/microsoftgraph/msgraph-sdk-objc`

### 4. Implement MSAL Authentication

The `OneDriveService.swift` file has placeholder authentication code. You'll need to implement:

```swift
import MSAL

func authenticate() async throws {
    let config = MSALPublicClientApplicationConfig(clientId: clientId)
    config.authority = try MSALAuthority(url: URL(string: "https://login.microsoftonline.com/common")!)
    
    let application = try MSALPublicClientApplication(configuration: config)
    
    let parameters = MSALInteractiveTokenParameters(scopes: ["User.Read", "Files.Read"], webviewParameters: MSALWebviewParameters())
    
    let result = try await application.acquireToken(with: parameters)
    self.accessToken = result.accessToken
    self.isAuthenticated = true
}
```

## Usage

1. **Grant Permissions**: When you first launch the app, tap "Allow Photo Access"
2. **Sign In**: Tap "Sign in to OneDrive" and authenticate with your Microsoft account
3. **Configure Settings**: Go to Settings to configure the OneDrive folder path (default: `/Photos`)
4. **Scan Photos**: Tap "Scan for Synced Photos" to compare your local photos with OneDrive
5. **Review**: Tap "Review Photos" to see which photos can be deleted
6. **Delete**: Select photos and tap "Delete Selected" or use "Delete All Synced Photos"

## Safety Features

- **Favorites are always protected**: Photos marked as favorites will never be deleted
- **Confirmation dialogs**: All deletion operations require user confirmation
- **Dry run mode**: Test deletions without actually removing photos
- **Deletion log**: Track all deletion operations with exportable CSV
- **Batch processing**: Photos are deleted in batches with retry logic
- **Error handling**: Individual failures don't stop the entire operation

## Matching Strategy

The app uses a multi-tiered approach to match local photos with OneDrive files:

1. **Primary**: Filename + File Size (fast and reliable)
2. **Fallback**: File Size + Creation Date within 1 second (handles renamed files)
3. **Future**: SHA256 hash comparison (most reliable but slower)

## Configuration Options

In Settings, you can configure:

- **OneDrive Folder Path**: Where your photos are backed up in OneDrive
- **Matching Sensitivity**: How strict the photo matching should be
- **Require Confirmation**: Whether to show confirmation before deletion
- **Dry Run Mode**: Simulate deletions without actually removing photos

## File Structure

```
PhotoCleanup/
├── Models/
│   ├── PhotoItem.swift
│   ├── OneDriveFile.swift
│   └── SyncStatus.swift
├── Services/
│   ├── PhotoLibraryService.swift
│   ├── OneDriveService.swift
│   ├── ComparisonService.swift
│   └── DeletionService.swift
├── Views/
│   ├── MainView.swift
│   ├── PhotoReviewView.swift
│   └── SettingsView.swift
├── ContentView.swift
├── PhotoCleanupApp.swift
└── Info.plist
```

## Known Limitations

1. OneDrive authentication requires MSAL implementation (placeholder code provided)
2. Hash-based matching is not yet implemented for performance reasons
3. No background sync capability
4. Single OneDrive account support only

## Future Enhancements

- Background photo scanning
- Scheduled automatic cleanup
- Multiple OneDrive account support
- iCloud Photos integration
- Advanced filtering (by date range, album, etc.)
- Duplicate photo detection without OneDrive
- Photo upload to OneDrive from within the app

## Troubleshooting

### "Not Authorized" Error
- Go to iOS Settings → Privacy → Photos → PhotoCleanup
- Ensure "All Photos" access is granted

### OneDrive Authentication Fails
- Verify your Client ID is correct in `OneDriveService.swift`
- Check that redirect URI matches in both Azure Portal and `Info.plist`
- Ensure MSAL framework is properly integrated

### Photos Don't Match
- Verify the OneDrive folder path in Settings
- Check that photos have been fully uploaded to OneDrive
- Try adjusting the matching sensitivity in Settings

## Privacy & Security

- All authentication tokens are stored securely in iOS Keychain
- No photo data is uploaded or transmitted except to Microsoft OneDrive
- Photo analysis is performed locally on device
- Deletion operations are logged locally only

## License

MIT License - See LICENSE file for details

## Support

For issues, questions, or contributions, please open an issue on GitHub.

---

**⚠️ Important**: This app permanently deletes photos from your device. Always ensure your photos are properly backed up to OneDrive before using this app. The developers are not responsible for any data loss.
