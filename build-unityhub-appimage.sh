#!/bin/bash
set -e
set -u

VER="latest"

if [[ "$#" -ne 0 ]]; then
    VER="$1"
fi


# functions time
get_package_info() {
    local packages_content="$1"
    local desired_version="$2"
    
    if [[ "$desired_version" == "latest" ]]; then
        # get the latest version
        echo "$packages_content" | awk '
            BEGIN { 
                RS=""
                FS="\n"
            }
            
            # compare two version strings (returns 1 if v1 > v2, 0 otherwise)
            function version_greater(v1, v2,    a1, a2, n1, n2, i, max) {
                n1 = split(v1, a1, /[.\-]/)
                n2 = split(v2, a2, /[.\-]/)
                max = (n1 > n2) ? n1 : n2
                
                for (i = 1; i <= max; i++) {
                    # Treat missing parts as 0
                    part1 = (i <= n1) ? a1[i] : 0
                    part2 = (i <= n2) ? a2[i] : 0
                    
                    # Convert to numbers for comparison
                    if (part1 + 0 > part2 + 0) return 1
                    if (part1 + 0 < part2 + 0) return 0
                }
                return 0
            }
            
            {
                version=""
                filename=""
                sha256=""
                
                for (i=1; i<=NF; i++) {
                    if ($i ~ /^Version: /) {
                        sub(/^Version: /, "", $i)
                        version=$i
                    }
                    else if ($i ~ /^Filename: /) {
                        sub(/^Filename: /, "", $i)
                        filename=$i
                    }
                    else if ($i ~ /^SHA256: /) {
                        sub(/^SHA256: /, "", $i)
                        sha256=$i
                    }
                }
                
                if (version) {
                    if (max_ver == "" || version_greater(version, max_ver)) {
                        max_ver=version
                        max_fname=filename
                        max_sha=sha256
                    }
                }
            }
            END {
                if (max_ver) {
                    print "VERSION=" max_ver
                    print "FILENAME=" max_fname
                    print "SHA256=" max_sha
                }
            }
        '
    else
        # get specific version
        echo "$packages_content" | awk -v ver="$desired_version" '
            BEGIN { 
                RS=""
                FS="\n"
            }
            {
                found_ver=0
                filename=""
                sha256=""
                
                for (i=1; i<=NF; i++) {
                    if ($i ~ /^Version: /) {
                        sub(/^Version: /, "", $i)
                        if ($i == ver) found_ver=1
                    }
                    else if ($i ~ /^Filename: /) {
                        sub(/^Filename: /, "", $i)
                        filename=$i
                    }
                    else if ($i ~ /^SHA256: /) {
                        sub(/^SHA256: /, "", $i)
                        sha256=$i
                    }
                }
                
                if (found_ver) {
                    print "FILENAME=" filename
                    print "SHA256=" sha256
                    exit
                }
            }
        '
    fi
}

useAR=0
TEMPDIR="workdir-temp"

mkdir -p "./$TEMPDIR"
cd "./$TEMPDIR"

# check for needed packages
if command -v dpkg-deb &> /dev/null; then
    echo "dpkg-deb is available."
    echo "Using dpkg-deb for extraction."
else
    echo "dpkg-deb is not available"
    if command -v ar &> /dev/null; then
        echo "ar is available."
        echo "Using ar for extraction."
        useAR=1
    else
        echo "ar is not available."
        echo "If this is not a debian based system, please install ar and run the script again."
        exit 1
    fi
fi

# get Unity
echo "Downloading UnityHub Package..."
UNITY_BASE_URL="https://hub-dist.unity3d.com/artifactory/hub-debian-prod-local"
UNITY_RELEASES="$UNITY_BASE_URL/dists/stable/Release"

# this feels like its making a lot of assumptions that might break lmao
RELEASES_RESP=$(curl -sL $UNITY_RELEASES | sed -n '/SHA256/,/^$/p' | grep "main/binary-amd64/Packages" | head -n 1)
PACKAGES_PATH=$(echo "$RELEASES_RESP" | awk '{print $3}')

UNITY_PACKAGES="$UNITY_BASE_URL/dists/stable/$PACKAGES_PATH"

UNITY_PACKAGES_RESP="$(get_package_info "$(curl -sL $UNITY_PACKAGES)" "$VER")"
echo "$UNITY_PACKAGES_RESP"

if [[ -n "$UNITY_PACKAGES_RESP" ]]; then
    eval "$UNITY_PACKAGES_RESP"
    UNITY_HUB_PACKAGE_VERSION="$VER"
    UNITY_HUB_PACKAGE_FILENAME="$(echo "$FILENAME" | rev | cut -d'/' -f1 | rev)"
    UNITY_HUB_PACKAGE_URL="$UNITY_BASE_URL/$FILENAME"
    UNITY_HUB_PACKAGE_SHA="$SHA256";
    unset VERSION FILENAME SHA256
fi

# echo "$UNITY_HUB_PACKAGE_VERSION"
# echo "$UNITY_HUB_PACKAGE_FILENAME"
# echo "$UNITY_HUB_PACKAGE_URL"
# echo "$UNITY_HUB_PACKAGE_SHA"

curl -sL "$UNITY_HUB_PACKAGE_URL" -o "$UNITY_HUB_PACKAGE_FILENAME"

DL_SHA=$(sha256sum "$UNITY_HUB_PACKAGE_FILENAME" | awk '{print $1}')

# echo "$DL_SHA"

if [ "$DL_SHA" = "$UNITY_HUB_PACKAGE_SHA" ]; then
    echo "Download Completed!"
else
    echo "Checksum mismatch!"
    echo "  Expected: $UNITY_HUB_PACKAGE_SHA"
    echo "  Received: $DL_SHA"
    rm -f "$TEMPDIR/$UNITY_HUB_PACKAGE_FILENAME"
    exit 1
fi

echo ""
echo "================================="
echo "  URL:           $UNITY_HUB_PACKAGE_URL"
echo "  FILE:          $UNITY_HUB_PACKAGE_FILENAME"
echo "  Version:       $UNITY_HUB_PACKAGE_VERSION"
echo "  SHA:           $UNITY_HUB_PACKAGE_SHA"
echo "================================="
echo ""

echo "Extracting Unity Hub Setup..."
EXTRACTED_PKG_DATA="extracted-package/data"
EXTRACTED_PKG_CTRL="extracted-package/control"
mkdir -p "./$EXTRACTED_PKG_DATA"
mkdir -p "./$EXTRACTED_PKG_CTRL"

if [ $useAR = "1" ]; then
    ar x "$UNITY_HUB_PACKAGE_FILENAME"
    tar -xf data.tar.* -C ./$EXTRACTED_PKG_DATA
    tar -xf control.tar.* -C ./$EXTRACTED_PKG_CTRL
    rm data.tar.* control.tar.* debian-binary
else
    dpkg-deb -x $UNITY_HUB_PACKAGE_FILENAME "./$EXTRACTED_PKG_DATA"
fi

# setup appdir
echo "Creating AppDir..."
mkdir -p ./UnityHub.AppDir/usr

echo "Copying package data..."
if [ -d "./$EXTRACTED_PKG_DATA/opt/unityhub" ]; then
    cp -r ./$EXTRACTED_PKG_DATA/opt/unityhub/* ./UnityHub.AppDir/usr/
fi
cp -r ./$EXTRACTED_PKG_DATA/usr/* ./UnityHub.AppDir/usr/

# create desktop file
echo "Copying desktop file..."
cp ../assets/unityhub.desktop ./UnityHub.AppDir/unityhub.desktop

# copy icon
echo "Copying app icons..."
if [ -f "./UnityHub.AppDir/usr/share/pixmaps/unityhub.png" ]; then
    cp ./UnityHub.AppDir/usr/share/pixmaps/unityhub.png ./UnityHub.AppDir/
elif [ -f "./UnityHub.AppDir/usr/share/icons/hicolor/256x256/apps/unityhub.png" ]; then
    cp ./UnityHub.AppDir/usr/share/icons/hicolor/256x256/apps/unityhub.png ./UnityHub.AppDir/unityhub.png
fi

# create AppRun
echo "Copying AppRun..."
cp ../assets/AppRun UnityHub.AppDir/
chmod +x ./UnityHub.AppDir/AppRun

# Bundle libssl 1.1
echo "Bundling libssl 1.1..."
mkdir -p ./UnityHub.AppDir/usr/lib

# some distros still have libssl 1.1
if [ -f "/usr/lib/x86_64-linux-gnu/libssl.so.1.1" ]; then
    cp /usr/lib/x86_64-linux-gnu/libssl.so.1.1 ./UnityHub.AppDir/usr/lib/
    cp /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1 ./UnityHub.AppDir/usr/lib/
    echo "Using system libssl 1.1"
elif [ -f "/usr/lib64/libssl.so.1.1" ]; then
    cp /usr/lib64/libssl.so.1.1 ./UnityHub.AppDir/usr/lib/
    cp /usr/lib64/libcrypto.so.1.1 ./UnityHub.AppDir/usr/lib/
    echo "Using system libssl 1.1"
else
    echo "Downloading libssl 1.1 from Ubuntu 20.04..."
    curl -sL http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb -o libssl.deb
    
    if [ $useAR = "1" ]; then
        mkdir -p ./libssl-temp
        ar x ./libssl.deb && tar -xf data.tar.* -C ./libssl-temp
        rm control.tar.* data.tar.* debian-binary
    else
        dpkg-deb -x libssl.deb libssl-temp/
    fi
    
    cp ./libssl-temp/usr/lib/x86_64-linux-gnu/libssl.so.1.1* ./UnityHub.AppDir/usr/lib/
    cp ./libssl-temp/usr/lib/x86_64-linux-gnu/libcrypto.so.1.1* ./UnityHub.AppDir/usr/lib/
    
    rm -rf ./libssl-temp libssl.deb
    echo "Bundled libssl 1.1"
fi

# get appimagetool
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

# build appimage using appimagetool
echo "Building AppImage..."
export ARCH=x86_64
OUTPUT_NAME="UnityHub-${UNITY_HUB_PACKAGE_VERSION}-amd64.AppImage"
OUTPUT_PATH="../out/${OUTPUT_NAME}"
mkdir -p ../out
./$APPIMAGETOOL_FILE --appimage-extract
./squashfs-root/AppRun UnityHub.AppDir "$OUTPUT_PATH"

# create checksum
sha256sum "$OUTPUT_PATH" > "${OUTPUT_PATH}.sha256"
OUTPUT_FILESIZE="$(du -h "$OUTPUT_PATH" | cut -f1)"

# fix ownership if in Docker
if [ -f /.dockerenv ]; then
    TARGET_UID=1000
    TARGET_GID=1000
    chown -R $TARGET_UID:$TARGET_GID ../out 2>/dev/null || true
fi

# cleanup
cd ../
rm -rf "./$TEMPDIR"

echo
echo "=== Build Complete! ==="
echo "AppImage: $OUTPUT_NAME"
echo "Version: $UNITY_HUB_PACKAGE_VERSION"
echo "Size: $OUTPUT_FILESIZE"
echo
echo "To run: ./$OUTPUT_NAME"

