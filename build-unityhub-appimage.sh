#!/bin/bash
set -e

echo "=== Unity Hub AppImage Builder ==="
echo

echo "Adding Unity Package Repo..."
# Check if we need sudo
if [ "$EUID" -ne 0 ]; then
    # set up unity package repo
    sudo curl -fsSL https://hub.unity3d.com/linux/keys/public | gpg --dearmor | tee /usr/share/keyrings/Unity_Technologies_ApS.gpg > /dev/null
    sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/Unity_Technologies_ApS.gpg] https://hub.unity3d.com/linux/repos/deb stable main" > /etc/apt/sources.list.d/unityhub.list'
    sudo apt-get update > /dev/null
else
    curl -fsSL https://hub.unity3d.com/linux/keys/public | gpg --dearmor | tee /usr/share/keyrings/Unity_Technologies_ApS.gpg > /dev/null
    sh -c 'echo "deb [signed-by=/usr/share/keyrings/Unity_Technologies_ApS.gpg] https://hub.unity3d.com/linux/repos/deb stable main" > /etc/apt/sources.list.d/unityhub.list'
    apt-get update > /dev/null
fi


echo "Downloading appimagetool..."
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
APPIMAGETOOL_FILE="appimagetool.AppImage"
STATUS=$(curl -sL -o /dev/null -w '%{http_code}' "$APPIMAGETOOL_URL")

if [ "$STATUS" -ne 200 ]; then
    echo "File not found or inaccessible: $APPIMAGETOOL_URL"
else
    curl -sL "$APPIMAGETOOL_URL" -o "$APPIMAGETOOL_FILE"
    chmod +x appimagetool.AppImage
fi

# Download Unity Hub
echo "Downloading Unity Hub..."
PACKAGE_RESP=$(apt-get download --print-uris unityhub)
PACKAGE_URL=$(echo "$PACKAGE_RESP" | grep -o "'[^']*'" | tr -d "'")
PACKAGE_FILE=$(echo "$PACKAGE_RESP" | awk '{print $2}')
PACKAGE_VERSION=$(echo "$PACKAGE_FILE" | grep -oP '\d+\.\d+\.\d+')
PACKAGE_SHA=$(echo "$PACKAGE_RESP" | awk -F'SHA256:' '{print $2}' | awk '{print $1}')
PACKAGE_STATUS=$(curl -sL -o /dev/null -w '%{http_code}' "$PACKAGE_URL")

echo ""
echo "================================="
echo "  URL:           $PACKAGE_URL"
echo "  FILE:          $PACKAGE_FILE"
echo "  Version:       $PACKAGE_VERSION"
echo "  SHA:           $PACKAGE_SHA"
echo "  RESPONSE CODE: $PACKAGE_STATUS"
echo "================================="
echo ""

if [ "$PACKAGE_STATUS" -ne 200 ]; then
    echo "File not found or inaccessible: $PACKAGE_URL"
else
    curl -sL "$PACKAGE_URL" -o "$PACKAGE_FILE"
fi

# Check against sha
DOWNLOADED_PACKAGE_SHA=$(sha256sum "$PACKAGE_FILE" | awk '{print $1}')
if [ "$DOWNLOADED_PACKAGE_SHA" = "$PACKAGE_SHA" ]; then
    echo "Download Successful!"
else
    echo "Checksum mismatch!"
    echo "  Expected: $PACKAGE_SHA"
    echo "  Received: $DOWNLOADED_PACKAGE_SHA"
    rm -f "$PACKAGE_FILE"
    exit 1
fi

# Extract package
echo "Extracting Unity Hub..."
mkdir -p extract-temp
dpkg-deb -x $PACKAGE_FILE ./extract-temp/

# Create AppDir
echo "Creating AppDir..."
mkdir -p UnityHub.AppDir/usr

# Copy extracted files
if [ -d "extract-temp/opt/unityhub" ]; then
    cp -r extract-temp/opt/unityhub/* UnityHub.AppDir/usr/
fi
cp -r extract-temp/usr/* UnityHub.AppDir/usr/ 2>/dev/null || true

# Create desktop file
cp assets/unityhub.desktop UnityHub.AppDir/unityhub.desktop

# Copy icon
if [ -f "UnityHub.AppDir/usr/share/pixmaps/unityhub.png" ]; then
    cp UnityHub.AppDir/usr/share/pixmaps/unityhub.png UnityHub.AppDir/
elif [ -f "UnityHub.AppDir/usr/share/icons/hicolor/256x256/apps/unityhub.png" ]; then
    cp UnityHub.AppDir/usr/share/icons/hicolor/256x256/apps/unityhub.png UnityHub.AppDir/unityhub.png
fi

# Create AppRun
cp assets/AppRun UnityHub.AppDir/
chmod +x UnityHub.AppDir/AppRun

# Bundle libssl 1.1
echo "Bundling libssl 1.1..."
mkdir -p UnityHub.AppDir/usr/lib

# some distros still have libssl 1.1
if [ -f "/usr/lib/x86_64-linux-gnu/libssl.so.1.1" ]; then
    cp /usr/lib/x86_64-linux-gnu/libssl.so.1.1 UnityHub.AppDir/usr/lib/
    cp /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1 UnityHub.AppDir/usr/lib/
    echo "Using system libssl 1.1"
elif [ -f "/usr/lib64/libssl.so.1.1" ]; then
    cp /usr/lib64/libssl.so.1.1 UnityHub.AppDir/usr/lib/
    cp /usr/lib64/libcrypto.so.1.1 UnityHub.AppDir/usr/lib/
    echo "Using system libssl 1.1"
else
    echo "Downloading libssl 1.1 from Ubuntu 20.04..."
    curl -sL http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb -o libssl.deb
    
    dpkg-deb -x libssl.deb libssl-temp/
    
    cp libssl-temp/usr/lib/x86_64-linux-gnu/libssl.so.1.1* UnityHub.AppDir/usr/lib/
    cp libssl-temp/usr/lib/x86_64-linux-gnu/libcrypto.so.1.1* UnityHub.AppDir/usr/lib/
    
    rm -rf libssl-temp libssl.deb
    echo "Bundled libssl 1.1"
fi

# Build AppImage using appimagetool
echo "Building AppImage..."
export ARCH=x86_64
OUTPUT_NAME="UnityHub-${PACKAGE_VERSION}-x86_64.AppImage"
OUTPUT_PATH="./out/${OUTPUT_NAME}"
mkdir -p ./out
./$APPIMAGETOOL_FILE --appimage-extract
./squashfs-root/AppRun UnityHub.AppDir "$OUTPUT_PATH"

# Create checksum
sha256sum "$OUTPUT_PATH" > "${OUTPUT_PATH}.sha256"

# Fix ownership if in Docker
if [ -f /.dockerenv ]; then
    TARGET_UID=1000
    TARGET_GID=1000
    chown -R $TARGET_UID:$TARGET_GID ./out 2>/dev/null || true
fi

# Cleanup
rm -rf extract-temp "$PACKAGE_FILE"

echo
echo "=== Build Complete! ==="
echo "AppImage: $OUTPUT_NAME"
echo "Version: $PACKAGE_VERSION"
echo "Size: $(du -h "$OUTPUT_PATH" | cut -f1)"
echo
echo "To run: ./$OUTPUT_NAME"