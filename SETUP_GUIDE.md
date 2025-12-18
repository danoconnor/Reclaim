# Reclaim Setup Guide

This guide will walk you through the complete setup process for the Reclaim iOS app.

## Prerequisites

- Xcode 15.0 or later
- macOS with iOS 16.0+ SDK
- Active Microsoft account
- Access to Azure Portal (free)

## Step 1: Azure App Registration

### 1.1 Create App Registration

1. Navigate to [Azure Portal](https://portal.azure.com)
2. Sign in with your Microsoft account
3. Search for "Azure Active Directory" in the top search bar
4. Click on "App registrations" in the left sidebar
5. Click "+ New registration"

### 1.2 Configure Basic Settings

Fill in the registration form:
- **Name**: `Reclaim` (or your preferred name)
- **Supported account types**: Select "Personal Microsoft accounts only"
- **Redirect URI**: Leave blank for now (we'll add it later)

Click "Register"

### 1.3 Note Your Client ID

After registration, you'll see the app overview page. Copy the **Application (client) ID** - you'll need this later.

Example: `12345678-1234-1234-1234-123456789abc`

### 1.4 Configure Authentication

1. Click "Authentication" in the left sidebar
2. Click "+ Add a platform"
3. Select "iOS / macOS"
4. Enter your **Bundle ID** (e.g., `com.yourname.Reclaim`)
5. The redirect URI will be auto-generated: `msauth.[BUNDLE-ID]://auth`
6. Click "Configure"

### 1.5 Add API Permissions

1. Click "API permissions" in the left sidebar
2. Click "+ Add a permission"
3. Select "Microsoft Graph"
4. Select "Delegated permissions"
5. Search and add these permissions:
   - `User.Read`
   - `Files.Read`
   - `Files.Read.All` (if you want to read from any folder)
6. Click "Add permissions"

**Note**: You don't need admin consent for personal Microsoft accounts.

## Step 2: Xcode Project Setup

### 2.1 Open the Project

1. Clone or download the Reclaim project
2. Open `Reclaim.xcodeproj` in Xcode
3. Select the project in the navigator
4. Select the Reclaim target

### 2.2 Update Bundle Identifier

1. In the "General" tab, find "Identity"
2. Set your **Bundle Identifier** (must match what you entered in Azure)
   - Example: `com.yourname.Reclaim`

### 2.3 Update Info.plist

1. Open `Info.plist` in the project
2. Find `msauth.YOUR-BUNDLE-ID` and replace with your actual bundle ID
   - Before: `msauth.YOUR-BUNDLE-ID`
   - After: `msauth.com.yourname.Reclaim`

### 2.4 Update OneDriveService

1. Open `Reclaim/Services/OneDriveService.swift`
2. Find the line: `private let clientId = "YOUR_CLIENT_ID"`
3. Replace `YOUR_CLIENT_ID` with your Application (client) ID from Azure
   - Example: `private let clientId = "12345678-1234-1234-1234-123456789abc"`

## Step 3: Add Dependencies

### 3.1 Add MSAL via Swift Package Manager

1. In Xcode, go to **File** → **Add Package Dependencies...**
2. Enter this URL: `https://github.com/AzureAD/microsoft-authentication-library-for-objc`
3. Select "Up to Next Major Version" with 1.0.0 as minimum
4. Click "Add Package"
5. Select the "MSAL" library
6. Click "Add Package"

### 3.2 Add Microsoft Graph SDK (Optional)

1. Go to **File** → **Add Package Dependencies...**
2. Enter: `https://github.com/microsoftgraph/msgraph-sdk-objc`
3. Follow the same steps as above
4. Select "MSGraphClientSDK"

## Step 4: Implement MSAL Authentication

### 4.1 Import MSAL

Add the import at the top of `OneDriveService.swift`:

```swift
import MSAL
```

### 4.2 Add MSAL Properties

Add these properties to the `OneDriveService` class:

```swift
private var msalApplication: MSALPublicClientApplication?
private var currentAccount: MSALAccount?
```

### 4.3 Replace the authenticate() Method

Replace the placeholder `authenticate()` method with:

```swift
func authenticate() async throws {
    // Create MSAL configuration
    guard let authorityURL = URL(string: "https://login.microsoftonline.com/common") else {
        throw OneDriveError.invalidURL
    }
    
    let authority = try MSALAuthority(url: authorityURL)
    
    let config = MSALPublicClientApplicationConfig(clientId: clientId)
    config.authority = authority
    
    // Create MSAL application
    let application = try MSALPublicClientApplication(configuration: config)
    self.msalApplication = application
    
    // Set up interactive parameters
    let webParameters = MSALWebviewParameters(authPresentationViewController: UIApplication.shared.windows.first!.rootViewController!)
    let interactiveParameters = MSALInteractiveTokenParameters(scopes: ["User.Read", "Files.Read"], webviewParameters: webParameters)
    
    // Acquire token
    let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
        application.acquireToken(with: interactiveParameters) { result, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else if let result = result {
                continuation.resume(returning: result)
            }
        }
    }
    
    // Store token and account
    self.accessToken = result.accessToken
    self.currentAccount = result.account
    self.isAuthenticated = true
}
```

### 4.4 Add Silent Token Refresh

Add this method to handle token refresh:

```swift
private func acquireTokenSilently() async throws -> String {
    guard let application = msalApplication,
          let account = currentAccount else {
        throw OneDriveError.notAuthenticated
    }
    
    let parameters = MSALSilentTokenParameters(scopes: ["User.Read", "Files.Read"], account: account)
    
    let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
        application.acquireTokenSilent(with: parameters) { result, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else if let result = result {
                continuation.resume(returning: result)
            }
        }
    }
    
    self.accessToken = result.accessToken
    return result.accessToken
}
```

## Step 5: Build and Test

### 5.1 Build the Project

1. Select a simulator or connected device
2. Press **⌘ + B** to build
3. Fix any build errors (usually related to import statements)

### 5.2 Run the App

1. Press **⌘ + R** to run
2. The app should launch on your simulator/device

### 5.3 Test Authentication Flow

1. Tap "Allow Photo Access" (grant permission in the dialog)
2. Tap "Sign in to OneDrive"
3. You should see the Microsoft login page
4. Sign in with your Microsoft account
5. Grant the requested permissions
6. You should be redirected back to the app

## Step 6: Review Settings

1. In the app, tap the Settings icon (gear)
2. Confirm you're signed in to OneDrive and adjust optional preferences like date filters, matching sensitivity, and dry run mode
3. Tap "Done"

### 6.1 Test Photo Scanning

1. Go back to the main screen
2. Tap "Scan for Synced Photos"
3. The app will fetch your local photos and compare with OneDrive
4. Check the statistics to see results

## Troubleshooting

### Build Errors

**Error**: "No such module 'MSAL'"
- **Solution**: Make sure MSAL is properly added via SPM. Try cleaning build folder (⌘ + Shift + K) and rebuilding.

**Error**: "Cannot find type 'MSALPublicClientApplication'"
- **Solution**: Add `import MSAL` at the top of OneDriveService.swift

### Runtime Errors

**Error**: "Invalid redirect URI"
- **Solution**: Double-check that Info.plist and Azure Portal have matching redirect URIs

**Error**: "Application with identifier was not found"
- **Solution**: Verify your Client ID is correct in OneDriveService.swift

**Error**: "User cancelled authentication"
- **Solution**: This is normal if user closes the login window. Just try again.

### Permission Issues

**Photos not accessible**
- Go to iOS Settings → Privacy & Security → Photos → Reclaim
- Ensure "All Photos" is selected

**OneDrive files not loading**
- Check that you granted Files.Read permission during login
- Try signing out and signing in again

## Advanced Configuration

### Custom Scopes

If you need additional permissions, modify the scopes array:

```swift
let scopes = ["User.Read", "Files.Read", "Files.Read.All", "Files.ReadWrite"]
```

### Different Authority

To support work/school accounts:

```swift
let authorityURL = URL(string: "https://login.microsoftonline.com/organizations")
```

For specific tenant:

```swift
let authorityURL = URL(string: "https://login.microsoftonline.com/[TENANT-ID]")
```

## Next Steps

1. Test the photo scanning functionality
2. Review photos in the Review screen
3. Test the deletion functionality (use Dry Run mode first!)
4. Export deletion logs to verify operations
5. Customize settings to your preferences

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review the [MSAL documentation](https://github.com/AzureAD/microsoft-authentication-library-for-objc)
3. Check Azure Portal for any configuration issues
4. Open an issue on GitHub with detailed error messages

---

**Important**: Always test with Dry Run mode enabled before performing actual deletions!
