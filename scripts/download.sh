#!/usr/bin/env bash
#
# Download (or reuse the cached) ncfig release for this machine:
#
#   bash <(curl -L https://raw.githubusercontent.com/jaydg/ncfig/main/scripts/download.sh)
#
# Prints the directory holding ncfig, ncmarquee and fonts/ on stdout; all
# other output goes to stderr. Files are cached in ~/.cache/ncfig/launch
# (or under $XDG_CACHE_HOME) keyed by version, and reused until that
# directory is deleted. A specific version can be pinned with
# VERSION=v0.1.0 (default: latest), and NCFIG_REPO=owner/ncfig downloads
# from another fork's releases.
#
# Used by launch.sh and demo.sh to get hold of the tools without compiling
# them; install.sh instead copies them permanently into a PREFIX.

set -euo pipefail

repo="${NCFIG_REPO:-jaydg/ncfig}"
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

cache="${XDG_CACHE_HOME:-$HOME/.cache}/ncfig"
dir="$cache/launch/$version"

if [ ! -x "$dir/ncfig" ] || [ ! -x "$dir/ncmarquee" ] || [ ! -d "$dir/fonts" ]; then
    ncfig_detect_platform
    mkdir -p "$cache"
    tmp="$(mktemp -d "$cache/download.XXXXXX")"
    if ! ncfig_fetch_release "$repo" "$version" "$tmp"; then
        rm -rf "$tmp"
        exit 1
    fi
    rm -rf "$dir"
    mkdir -p "$(dirname "$dir")"
    mv "$tmp" "$dir"
fi

echo "$dir"
