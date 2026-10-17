#!/usr/bin/env bash
#
# Install the latest ncfig release without compiling:
#
#   bash <(curl -L https://raw.githubusercontent.com/jaydg/ncfig/main/scripts/install.sh)
#
# Installs ncfig and ncmarquee into $PREFIX/bin and the standard FIGlet fonts
# into $PREFIX/share/ncfig/fonts. PREFIX defaults to ~/.local; set it to
# install elsewhere, e.g. PREFIX=/usr/local sudo -E bash <(curl ...).
# A specific version can be chosen with VERSION=v0.1.0, and NCFIG_REPO=owner/ncfig
# installs from another fork's releases.

set -euo pipefail

repo="${NCFIG_REPO:-jaydg/ncfig}"   # override to use another fork's releases
prefix="${PREFIX:-$HOME/.local}"
version="${VERSION:-latest}"

script_dir=""
case "$0" in
    */*) [ -f "$0" ] && script_dir="$(cd "$(dirname "$0")" && pwd)" ;;
esac
if [ -n "$script_dir" ] && [ -f "$script_dir/lib.sh" ]; then
    # shellcheck source=lib.sh
    source "$script_dir/lib.sh"
else
    lib_tmp="$(mktemp)"
    if ! curl -fsSL "https://raw.githubusercontent.com/$repo/main/scripts/lib.sh" -o "$lib_tmp"; then
        rm -f "$lib_tmp"
        echo "Failed to fetch scripts/lib.sh from $repo" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$lib_tmp"
    rm -f "$lib_tmp"
fi
ncfig_detect_platform

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! ncfig_fetch_release "$repo" "$version" "$tmp"; then
    exit 1
fi

mkdir -p "$prefix/bin" "$prefix/share/ncfig/fonts"
install -m 755 "$tmp/ncfig" "$tmp/ncmarquee" "$prefix/bin/"
install -m 644 "$tmp"/fonts/*.flf "$prefix/share/ncfig/fonts/"

echo "Installed ncfig and ncmarquee to $prefix/bin, fonts to $prefix/share/ncfig/fonts."
case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) echo "Note: $prefix/bin is not on your PATH. Add it, e.g.: export PATH=\"$prefix/bin:\$PATH\"" ;;
esac
echo 'Try: ncfig -f banner -v 0xff0000:0x0000ff "Hello"'
