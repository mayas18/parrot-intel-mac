#!/usr/bin/env bash
# Build the Intel-only, CPU whisper.cpp helper used by Parrot.app.
# Output: ${PARROT_BUILD_DIR:-build}/whisper-cli-x86_64
# Requires CMake and the macOS Command Line Tools. The source revision is pinned
# so local installs and release builds use the same inference implementation.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=v1.9.5
REVISION=d1be6fde11ac6e0407606b4e42fe72d34add8037
OUT="${PARROT_BUILD_DIR:-build}"
SOURCE="${PARROT_WHISPER_SOURCE:-$OUT/vendor/whisper.cpp}"
BUILD="${PARROT_WHISPER_BUILD:-$OUT/vendor/whisper-build-x86_64}"
CMAKE="${PARROT_CMAKE:-cmake}"

command -v "$CMAKE" >/dev/null 2>&1 || {
    echo "CMake is required to build the Intel whisper.cpp helper" >&2
    exit 1
}

if [ ! -d "$SOURCE/.git" ]; then
    mkdir -p "$(dirname "$SOURCE")"
    git clone --depth 1 --branch "$VERSION" https://github.com/ggml-org/whisper.cpp.git "$SOURCE"
fi
ACTUAL="$(git -C "$SOURCE" rev-parse HEAD)"
if [ "$ACTUAL" != "$REVISION" ]; then
    echo "whisper.cpp checkout is $ACTUAL; expected $REVISION ($VERSION)" >&2
    exit 1
fi

"$CMAKE" -S "$SOURCE" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DGGML_METAL=OFF \
    -DWHISPER_COREML=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_NATIVE=OFF \
    -DWHISPER_BUILD_TESTS=OFF
"$CMAKE" --build "$BUILD" --target whisper-cli --config Release -j "${PARROT_BUILD_JOBS:-2}"

mkdir -p "$OUT"
cp "$BUILD/bin/whisper-cli" "$OUT/whisper-cli-x86_64"
lipo "$OUT/whisper-cli-x86_64" -verify_arch x86_64
echo "$OUT/whisper-cli-x86_64"
