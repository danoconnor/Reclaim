# Reclaim Setup Guide

This guide walks you through setting up the Reclaim iOS app for development.

## Prerequisites

- Xcode 16.0 or later
- macOS with iOS 18.0+ SDK
- Active Microsoft personal account
- Access to [Azure Portal](https://portal.azure.com) (free)

## Step 1: Azure App Registration

### 1.1 Create App Registration

1. Navigate to [Azure Portal](https://portal.azure.com)
2. Sign in with your Microsoft account
3. Search for "Microsoft Entra ID" (formerly Azure Active Directory) in the top search bar
4. Click on "App registrations" in the left sidebar
5. Click "+ New registration"

### 1.2 Configure Basic Settings

Fill in the registration form:
- **Name**: `Reclaim` (or your preferred name)
- **Supported account types**: Select "Personal Microsoft accounts only"
- **Redirect URI**: Leave blank for now (we'll add it next)

Click "Register"

### 1.3 Note Your Client ID

After registration, copy the **Application (client) ID** from the overview page — you'll need this in Step 2.

### 1.4 Configure Authentication

1. Click "Authentication" in the left sidebar
2. Click "+ Add a platform"
3. Select "iOS / macOS"
4. Enter your **Bundle ID** (e.g., `com.danoconnor.Reclaim`)
5. The redirect URI will be auto-generated: `msauth.[BUNDLE-ID]://auth`
6. Click "Configure"

### 1.5 Add API Permissions

1. Click "API permissions" in the left sidebar
2. Click "+ Add a permission"
3. Select "Microsoft Graph"
4. Select "Delegated permissions"
5. Search and add: `Files.Read`
6. Click "Add permissions"

**Note**: Admin consent is not required for personal Microsoft accounts.

## Step 2: Xcode Project Setup

### 2.1 Open the Project

1. Clone or download the Reclaim project
2. Open `Reclaim.xcodeproj` in Xcode

### 2.2 Update Bundle Identifier

1. Select the Reclaim target → "General" tab
2. Set your **Bundle Identifier** (must match what you entered in Azure)

### 2.3 Update Info.plist

Open `Info.plist` and verify the `CFBundleURLSchemes` value matches your bundle ID:
```
msauth.[YOUR-BUNDLE-ID]
```

The current value is `msauth.com.danoconnor.Reclaim`. Update it if you changed the bundle ID.

### 2.4 Update Client ID and Redirect URI

Open `Reclaim/Services/AuthenticationProvider.swift` and update these values in `MSALAuthenticationProvider`:

```swift
private let clientId = "YOUR_CLIENT_ID"        // Your Application (client) ID from Azure
private let redirectUri = "msauth.[YOUR-BUNDLE-ID]://auth"
```

The authority is pre-configured for personal Microsoft accounts (`https://login.microsoftonline.com/consumers`).

### 2.5 Add MSAL via Swift Package Manager

MSAL should already be configured in the project's package dependencies. If not:

1. In Xcode, go to **File** → **Add Package Dependencies...**
2. Enter: `https://github.com/AzureAD/microsoft-authentication-library-for-objc`
3. Select "Up to Next Major Version"
4. Click "Add Package" and select the "MSAL" library

## Step 3: Build and Run

1. Select a simulator or connected device
2. Press **⌘ + B** to build
3. Press **⌘ + R** to run

### Test the Authentication Flow

1. Tap "Allow Photo Access" and grant permission
2. Tap "Sign in to OneDrive"
3. Sign in with your Microsoft personal account
4. You should be redirected back to the app with OneDrive showing "Connected"

### Test Photo Scanning

1. Tap "Scan for Synced Photos"
2. The app will fetch OneDrive photo metadata and compare against local photos using file hashes
3. Check the statistics section for results

## Troubleshooting

### Build Errors

**"No such module 'MSAL'"**
- Ensure MSAL is added via SPM. Try **Product** → **Clean Build Folder** (⌘ + Shift + K) and rebuild.

### Runtime Errors

**"Invalid redirect URI"**
- Verify that `Info.plist` `CFBundleURLSchemes` and the Azure Portal redirect URI both match your bundle ID.

**"Application with identifier was not found"**
- Verify the Client ID in `AuthenticationProvider.swift` matches the Azure Portal.

### Permission Issues

**Photos not accessible**
- Go to iOS Settings → Privacy & Security → Photos → Reclaim → "Full Access"

**OneDrive files not loading**
- Ensure `Files.Read` permission was granted during sign-in
- Try signing out (Settings → Sign Out of OneDrive) and signing in again

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review the [MSAL documentation](https://github.com/AzureAD/microsoft-authentication-library-for-objc)
3. Check Azure Portal for configuration issues
4. Open an issue on GitHub
