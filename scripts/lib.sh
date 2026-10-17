#!/usr/bin/env bash
#
# Shared helpers for ncfig's download/install scripts. Not meant to be run
# directly; sourced by install.sh and download.sh.

# ncfig_detect_platform: sets $arch and $os from uname, or exits 2.
ncfig_detect_platform() {
    case "$(uname -m)" in
        x86_64|amd64)  arch="x86_64" ;;
        arm64|aarch64) arch="aarch64" ;;
        *) echo "Unsupported CPU architecture: $(uname -m)" >&2; exit 2 ;;
    esac
    case "$(uname -s)" in
        Linux)  os="linux" ;;
        Darwin) os="macos" ;;
        *) echo "Unsupported operating system: $(uname -s)" >&2; exit 2 ;;
    esac
}

# ncfig_fetch_release <repo> <version> <dest-dir>: downloads and extracts
# the release asset for $arch/$os (set by ncfig_detect_platform) into
# dest-dir. version is "latest" or a tag like "v0.1.0".
ncfig_fetch_release() {
    local repo="$1" version="$2" dest="$3" asset url
    asset="ncfig-$arch-$os.tar.gz"
    if [ "$version" = "latest" ]; then
        url="https://github.com/$repo/releases/latest/download/$asset"
    else
        url="https://github.com/$repo/releases/download/$version/$asset"
    fi

    echo "Downloading $url ..." >&2
    if ! curl -fsSL "$url" | tar -C "$dest" -xz; then
        echo "Download failed. Is there a release for $arch-$os at https://github.com/$repo/releases ?" >&2
        return 1
    fi
}
