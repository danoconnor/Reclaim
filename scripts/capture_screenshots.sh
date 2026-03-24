#!/bin/bash
#
# capture_screenshots.sh
# Captures App Store screenshots by running UI tests on multiple simulator destinations,
# then automatically extracts the screenshot images into organized folders.
#
# Usage: ./scripts/capture_screenshots.sh
#
# Output structure:
#   screenshots/
#     iPhone_6.7/
#       01_MainDashboard.png
#       02_PhotoReview.png
#       ...
#     iPhone_6.5/
#       ...
#     iPad_12.9/
#       ...
#

set -e

SCHEME="Reclaim"
PROJECT="Reclaim.xcodeproj"
TEST_CLASS="ScreenshotTests"
OUTPUT_DIR="./screenshots"

# Clean previous results
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "=== Capturing App Store Screenshots ==="
echo ""

# Device configurations for App Store submission
# App deployment target is iOS 26.1, so only iOS 26.1+ simulators are compatible.
# 6.9" iPhone: iPhone 17 Pro Max (required for App Store 6.7" category)
# 12.9" iPad: iPad Pro 13-inch (M5) (required for App Store 12.9" category)
# Add more devices below as needed.
declare -a DEVICES=(
    "iPhone 17 Pro Max|iPhone_6.9"
    "iPad Pro 13-inch (M5)|iPad_12.9"
)

for device_config in "${DEVICES[@]}"; do
    IFS='|' read -r device_name folder_name <<< "$device_config"
    
    RESULT_BUNDLE="$OUTPUT_DIR/${folder_name}_result.xcresult"
    EXPORT_DIR="$OUTPUT_DIR/${folder_name}_raw"
    FINAL_DIR="$OUTPUT_DIR/$folder_name"
    
    echo "--- Capturing screenshots on: $device_name ---"
    
    # Clean any pre-existing result bundle (xcodebuild fails if it already exists)
    rm -rf "$RESULT_BUNDLE"
    
    # Run the screenshot UI tests
    set +e
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS Simulator,name=$device_name,OS=latest" \
        -only-testing:"ReclaimUITests/$TEST_CLASS" \
        -resultBundlePath "$RESULT_BUNDLE" \
        -quiet \
        2>&1 | tail -5
    set -e
    
    if [ ! -d "$RESULT_BUNDLE" ]; then
        echo "  ERROR: No result bundle created for $device_name. Skipping."
        continue
    fi
    
    echo "  Tests complete. Extracting screenshots..."
    
    # Export attachments from the xcresult bundle
    mkdir -p "$EXPORT_DIR"
    xcrun xcresulttool export attachments \
        --path "$RESULT_BUNDLE" \
        --output-path "$EXPORT_DIR"
    
    # Organize exported screenshots into the final directory using the manifest
    mkdir -p "$FINAL_DIR"
    
    if [ -f "$EXPORT_DIR/manifest.json" ]; then
        # Parse manifest.json to rename UUID-named files to human-readable names.
        # The manifest has structure:
        #   [{ "attachments": [{ "exportedFileName": "UUID.png",
        #        "suggestedHumanReadableName": "Name.png", ... }], ... }]
        
        # Extract pairs of exportedFileName and suggestedHumanReadableName
        # by flattening to one line and splitting on each attachment object
        manifest_content=$(tr -d '\n' < "$EXPORT_DIR/manifest.json")
        
        # Use grep -o to extract each attachment block
        echo "$manifest_content" | grep -o '"exportedFileName" *: *"[^"]*" *,[^}]*"suggestedHumanReadableName" *: *"[^"]*"' | while IFS= read -r match; do
            att_file=$(echo "$match" | sed -n 's/.*"exportedFileName" *: *"\([^"]*\)".*/\1/p')
            suggested=$(echo "$match" | sed -n 's/.*"suggestedHumanReadableName" *: *"\([^"]*\)".*/\1/p')
            
            if [ -n "$att_file" ] && [ -n "$suggested" ] && [ -f "$EXPORT_DIR/$att_file" ]; then
                # Use the suggested name directly (it already has an extension)
                # Strip any UUID suffix pattern (_0_UUID) from the name for cleaner filenames
                clean_name=$(echo "$suggested" | sed 's/_[0-9]*_[0-9A-F\-]\{36\}\./\./')
                
                cp "$EXPORT_DIR/$att_file" "$FINAL_DIR/$clean_name"
                echo "    $clean_name"
            fi
        done
    else
        echo "  Warning: No manifest.json found. Copying raw files..."
        cp "$EXPORT_DIR"/*.png "$FINAL_DIR/" 2>/dev/null || true
    fi
    
    # Clean up intermediate files
    rm -rf "$EXPORT_DIR"
    rm -rf "$RESULT_BUNDLE"
    
    file_count=$(ls -1 "$FINAL_DIR" 2>/dev/null | wc -l | tr -d ' ')
    echo "  ✓ $file_count screenshots saved to $FINAL_DIR/"
    echo ""
done

echo "=== Screenshot capture complete ==="
echo ""
echo "Screenshots are in: $OUTPUT_DIR/"
ls -R "$OUTPUT_DIR/"
