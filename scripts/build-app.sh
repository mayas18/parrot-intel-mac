#!/usr/bin/env bash
# Builds the release binary and wraps it in a signed Parrot.app.
#   scripts/build-app.sh [version]        → build/Parrot.app
#
# The version (a tag such as v0.1.0 or 0.1.0) goes into
# CFBundleShortVersionString and CFBundleVersion. Without one it comes from
# the latest tag, or 0.0.0.
#
# Embeds Sparkle.framework (in-app updates, #50) in Contents/Frameworks and
# signs it inside-out before the app: its XPC services, Autoupdate, and
# Updater.app, then the framework, all with the same identity and the
# hardened runtime, as notarization requires.
#
# Signs with the first "Developer ID Application" identity in the keychain,
# with the hardened runtime and packaging/Parrot.entitlements. The
# designated requirement then names the bundle ID and the team, not a
# cdhash, so macOS keeps the Microphone and Accessibility grants across
# builds. Without an identity the app is ad-hoc signed and every build is a
# new identity; the script says so.
#
#   PARROT_SIGN_IDENTITY   signing identity (default: the keychain's Developer ID)
#   PARROT_TIMESTAMP=none  skip the secure timestamp (local builds, offline);
#                          notarization needs it, so releases leave this unset
#   PARROT_BUILD_DIR       output directory (default: build)
#   PARROT_ARCHS           architectures to build (default: "arm64 x86_64")

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)}"
VERSION="${VERSION#v}"
OUT="${PARROT_BUILD_DIR:-build}"
APP="$OUT/Parrot.app"

IDENTITY="${PARROT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"

ARCHS="${PARROT_ARCHS:-arm64 x86_64}"
case "$ARCHS" in
    arm64|x86_64|"arm64 x86_64"|"x86_64 arm64") ;;
    *) echo "PARROT_ARCHS must be arm64, x86_64, or both" >&2; exit 1 ;;
esac

echo "→ building parrot $VERSION (release, $ARCHS)"
BIN_PATHS=()
for arch in $ARCHS; do
    swift build --disable-keychain -c release --arch "$arch" --product parrot
    BIN_PATHS+=("$(swift build --disable-keychain -c release --arch "$arch" --show-bin-path)/parrot")
done

echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources/Licenses"
cp LICENSE "$APP/Contents/Resources/Licenses/Parrot.txt"
if [ "${#BIN_PATHS[@]}" -eq 2 ]; then
    lipo -create "${BIN_PATHS[@]}" -output "$APP/Contents/MacOS/parrot"
else
    cp "${BIN_PATHS[0]}" "$APP/Contents/MacOS/parrot"
fi
# SwiftPM links Sparkle through @rpath and puts the framework beside the
# binary; in the bundle it lives in Contents/Frameworks.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/parrot"
strip -x "$APP/Contents/MacOS/parrot"
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "${BIN_PATHS[0]}")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# SwiftPM copies Sparkle's binary framework beside each architecture's
# executable. Check that its selected macOS slice can load on every target.
for arch in $ARCHS; do
    if ! lipo "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" -verify_arch "$arch"; then
        echo "Sparkle.framework does not support $arch" >&2
        exit 1
    fi
done
if [[ " $ARCHS " == *" x86_64 "* ]]; then
    PARROT_BUILD_DIR="$OUT" scripts/build-whisper-cpp.sh
    mkdir -p "$APP/Contents/Helpers"
    cp "$OUT/whisper-cli-x86_64" "$APP/Contents/Helpers/whisper-cli"
    strip -x "$APP/Contents/Helpers/whisper-cli"
    # The pinned whisper.cpp source's MIT license covers its bundled ggml.
    WHISPER_SOURCE="${PARROT_WHISPER_SOURCE:-$OUT/vendor/whisper.cpp}"
    cp "$WHISPER_SOURCE/LICENSE" "$APP/Contents/Resources/Licenses/whisper.cpp-and-ggml.txt"
fi
cp packaging/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM's resource bundles (swift-transformers' fallback tokenizer
# configs, swift-crypto's privacy manifest) are left out, as they were from
# the bare binary: their accessors look beside the .app, where a signed
# bundle can't hold anything.

# docs/assets/app-icon.png is the bird on a white rounded square, drawn by
# scripts/make-app-icon.swift from docs/assets/icon.png.
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" docs/assets/app-icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" docs/assets/app-icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

TIMESTAMP="--timestamp"
[ "${PARROT_TIMESTAMP:-}" = "none" ] && TIMESTAMP="--timestamp=none"

if [ -n "$IDENTITY" ]; then
    echo "→ signing as $IDENTITY"
    SIGN_AS="$IDENTITY"
    SIGN_OPTIONS=runtime
else
    echo "! no Developer ID Application identity; ad-hoc signing."
    echo "  Permissions will not survive the next build, and the app can't be notarized."
    SIGN_AS="-"
    # Hardened runtime library validation requires a shared Team ID. Ad-hoc
    # signatures have none, so local builds cannot load embedded Sparkle
    # with that policy enabled.
    SIGN_OPTIONS=0
    TIMESTAMP="--timestamp=none"
fi

# Inside-out: each nested bundle before the one that contains it, as in
# Sparkle's documentation. Downloader.xpc keeps its entitlements.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in \
    "$SPARKLE/XPCServices/Installer.xpc" \
    "$SPARKLE/XPCServices/Downloader.xpc" \
    "$SPARKLE/Autoupdate" \
    "$SPARKLE/Updater.app" \
    "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options "$SIGN_OPTIONS" $TIMESTAMP --preserve-metadata=entitlements \
        --sign "$SIGN_AS" "$nested"
done
if [ -f "$APP/Contents/Helpers/whisper-cli" ]; then
    codesign --force --options "$SIGN_OPTIONS" $TIMESTAMP \
        --sign "$SIGN_AS" "$APP/Contents/Helpers/whisper-cli"
fi
codesign --force --options "$SIGN_OPTIONS" $TIMESTAMP \
    --entitlements packaging/Parrot.entitlements \
    --sign "$SIGN_AS" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
echo "  designated requirement: $(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
echo "$APP"
