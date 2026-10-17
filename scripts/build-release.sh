#!/usr/bin/env bash
#
# Builds the release binaries and packages them, together with the standard
# FIGlet fonts, into dist/ncfig-<arch>-<os>.tar.gz. The GitHub Actions release
# workflow runs this on each platform; it works locally as well.
#
# The binaries link Notcurses statically (xmake f --static=y), so the
# development packages of notcurses, libunistring, libdeflate and ncurses with
# their static libraries must be installed (on Alpine the *-static packages).
#
# Note: this reconfigures the xmake project (output in build/release). Run
# `xmake f -c` afterwards to get back to a normal development configuration.
#
# Environment:
#   XMAKE_CONFIG_ARGS  arguments for `xmake f`, replacing the default toolchain
#                      choice (macOS: Homebrew LLVM with a deployment target of
#                      macOS 13, Linux: clang)

set -euo pipefail
cd "$(dirname "$0")/.."

case "$(uname -m)" in
    x86_64|amd64)  arch="x86_64" ;;
    arm64|aarch64) arch="aarch64" ;;
    *) echo "Unsupported CPU architecture: $(uname -m)" >&2; exit 2 ;;
esac
case "$(uname -s)" in
    Linux)  os="linux";  toolchain="--toolchain=clang" ;;
    Darwin) os="macos";  toolchain="--toolchain=llvm --sdk=$(brew --prefix llvm) --target_minver=13.0" ;;
    *) echo "Unsupported operating system: $(uname -s)" >&2; exit 2 ;;
esac

# shellcheck disable=SC2086  # the arguments are meant to be split
xmake f -y -c -o build/release -m release --static=y ${XMAKE_CONFIG_ARGS:-$toolchain}
xmake -y
xmake fonts

stage="dist/ncfig-$arch-$os"
rm -rf "$stage"
mkdir -p "$stage/fonts"
for tool in ncfig ncmarquee; do
    binary="$(find build/release -type f -name "$tool" -perm -u+x | head -1)"
    [ -n "$binary" ] || { echo "$tool binary not found under build/release" >&2; exit 1; }
    cp "$binary" "$stage/"
    strip "$stage/$tool"
    # a release binary must not depend on anything but the system
    case "$os" in
        linux)
            file "$stage/$tool" | grep -q "statically linked" || { echo "$tool is not statically linked" >&2; exit 1; } ;;
        macos)
            if otool -L "$stage/$tool" | tail -n +2 | grep -v '^[[:space:]]*/usr/lib/'; then
                echo "$tool depends on libraries outside /usr/lib (see above)" >&2
                exit 1
            fi ;;
    esac
done
cp fonts/*.flf "$stage/fonts/"
cp LICENSE README.md "$stage/"

archive="dist/ncfig-$arch-$os.tar.gz"
tar -C "$stage" -czf "$archive" .
rm -rf "$stage"

echo
echo "Built $archive:"
tar -tzf "$archive" | sed 's/^/  /'
ls -la "$archive"
