#!/usr/bin/env bash
# Cross-build the pinned upstream source for Android/Termux on Linux x86_64.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE_DIR=${SOURCE_DIR:-"$ROOT/upstream"}
CACHE_DIR=${CACHE_DIR:-"$ROOT/.cache"}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT/dist"}
UPSTREAM_REV=7b116c05bfda646af39d2524c54e70c751f57ee8
RUST_VERSION=1.98.0
ZIG_VERSION=0.16.0
ZIG_SHA256=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
NDK_VERSION=28.2.13676358
ANDROID_API=24
TARGET=${TARGET:-aarch64-linux-android}
ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-"${ANDROID_HOME:-$HOME/Android/Sdk}/ndk/$NDK_VERSION"}
export ANDROID_NDK_HOME

fail() { printf 'build: %s\n' "$*" >&2; exit 1; }
[[ $(uname -s)-$(uname -m) == Linux-x86_64 ]] || fail 'use a Linux x86_64 build host'
case "$TARGET" in
    aarch64-linux-android|x86_64-linux-android) ;;
    *) fail "unsupported target: $TARGET" ;;
esac
for command in curl git tar sha256sum rustup; do
    command -v "$command" >/dev/null || fail "required command missing: $command"
done
[[ -f "$ANDROID_NDK_HOME/source.properties" ]] || fail "NDK $NDK_VERSION missing; set ANDROID_NDK_HOME"
grep -Eq "^Pkg.Revision = $NDK_VERSION$" "$ANDROID_NDK_HOME/source.properties" || fail "NDK $NDK_VERSION required"
NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
SYSROOT="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
[[ -x "$NDK_BIN/${TARGET}${ANDROID_API}-clang" ]] || fail 'NDK compiler missing'

mkdir -p "$CACHE_DIR" "$OUTPUT_DIR" "$ROOT/build"
ZIG="$CACHE_DIR/zig-x86_64-linux-$ZIG_VERSION/zig"
if [[ ! -x "$ZIG" ]]; then
    ARCHIVE="$CACHE_DIR/zig-x86_64-linux-$ZIG_VERSION.tar.xz"
    curl --proto '=https' --tlsv1.2 --fail --location --retry 3 \
        "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz" -o "$ARCHIVE"
    printf '%s  %s\n' "$ZIG_SHA256" "$ARCHIVE" | sha256sum -c -
    tar -xJf "$ARCHIVE" -C "$CACHE_DIR"
fi
[[ $("$ZIG" version) == "$ZIG_VERSION" ]] || fail "Zig $ZIG_VERSION required"
export ZIG
export ZIG_GLOBAL_CACHE_DIR="$CACHE_DIR/zig-global"
if ! rustup run "$RUST_VERSION" rustc --version >/dev/null 2>&1; then
    rustup toolchain install "$RUST_VERSION" --profile minimal
fi
rustup target add --toolchain "$RUST_VERSION" "$TARGET"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    git clone --depth 1 --branch v0.9.3 https://github.com/herdrdev/herdr.git "$SOURCE_DIR"
fi
[[ $(git -C "$SOURCE_DIR" rev-parse HEAD) == "$UPSTREAM_REV" ]] || fail "upstream must be pinned at $UPSTREAM_REV"
for patch_file in "$ROOT"/patches/*.patch; do
    if git -C "$SOURCE_DIR" apply --check "$patch_file" 2>/dev/null; then
        git -C "$SOURCE_DIR" apply "$patch_file"
    elif ! git -C "$SOURCE_DIR" apply --reverse --check "$patch_file" 2>/dev/null; then
        fail "patch neither applicable nor already applied: $patch_file"
    fi
done

# Reject additional tracked edits so the recorded revision and patches identify
# the source that actually enters the release build. Ignore Cargo/Zig caches.
EXPECTED_INDEX=$(mktemp "$ROOT/build/expected-index.XXXXXX")
rm -f "$EXPECTED_INDEX"
trap 'rm -f "$EXPECTED_INDEX"' EXIT
GIT_INDEX_FILE="$EXPECTED_INDEX" git -C "$SOURCE_DIR" read-tree HEAD
for patch_file in "$ROOT"/patches/*.patch; do
    GIT_INDEX_FILE="$EXPECTED_INDEX" git -C "$SOURCE_DIR" apply --cached "$patch_file"
done
EXPECTED_TREE=$(GIT_INDEX_FILE="$EXPECTED_INDEX" git -C "$SOURCE_DIR" write-tree)
git -C "$SOURCE_DIR" diff --quiet "$EXPECTED_TREE" -- || fail 'upstream contains edits outside the release patches'

LIBC_FILE="$ROOT/build/zig-libc-$TARGET.conf"
cat > "$LIBC_FILE.tmp" <<EOF
include_dir=$SYSROOT/usr/include
sys_include_dir=$SYSROOT/usr/include/$TARGET
crt_dir=$SYSROOT/usr/lib/$TARGET/$ANDROID_API
msvc_lib_dir=
kernel32_lib_dir=
gcc_dir=
EOF
if ! cmp -s "$LIBC_FILE.tmp" "$LIBC_FILE"; then
    mv -f "$LIBC_FILE.tmp" "$LIBC_FILE"
else
    rm -f "$LIBC_FILE.tmp"
fi
export LIBGHOSTTY_VT_ANDROID_LIBC="$LIBC_FILE"
# Android's loader does not search the Termux prefix unless the ELF requests it.
export RUSTFLAGS="-C link-arg=-Wl,-rpath,/data/data/com.termux/files/usr/lib -C link-arg=-Wl,-z,max-page-size=16384"
export CARGO_TARGET_DIR="$ROOT/build/cargo"
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-4}
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(git -C "$SOURCE_DIR" show -s --format=%ct HEAD)
TARGET_ENV=${TARGET//-/_}
export "CARGO_TARGET_${TARGET_ENV^^}_LINKER=$NDK_BIN/${TARGET}${ANDROID_API}-clang"
export "CC_$TARGET_ENV=$NDK_BIN/${TARGET}${ANDROID_API}-clang"
export "CXX_$TARGET_ENV=$NDK_BIN/${TARGET}${ANDROID_API}-clang++"
export "AR_$TARGET_ENV=$NDK_BIN/llvm-ar"

cd "$SOURCE_DIR"
cargo +"$RUST_VERSION" build --release --locked --target "$TARGET"
install -m 755 "$CARGO_TARGET_DIR/$TARGET/release/herdr" "$OUTPUT_DIR/herdr"
"$NDK_BIN/llvm-strip" "$OUTPUT_DIR/herdr"
{
    printf 'upstream_version=0.9.3\nupstream_revision=%s\n' "$UPSTREAM_REV"
    printf 'target=%s\nandroid_api=%s\nndk=%s\nzig=%s\n' "$TARGET" "$ANDROID_API" "$NDK_VERSION" "$ZIG_VERSION"
    rustup run "$RUST_VERSION" rustc --version
    printf 'source_date_epoch=%s\n' "$SOURCE_DATE_EPOCH"
    sha256sum "$ROOT"/patches/*.patch "$OUTPUT_DIR/herdr"
    "$NDK_BIN/llvm-readelf" -l -d "$OUTPUT_DIR/herdr"
} > "$OUTPUT_DIR/build-info.txt"
printf 'Built %s\n' "$OUTPUT_DIR/herdr"
