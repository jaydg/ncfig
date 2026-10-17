#!/usr/bin/env bash
#
# Play the ncfig demo:
#
#   bash <(curl -L https://raw.githubusercontent.com/jaydg/ncfig/main/scripts/demo.sh)
#
# Uses a local xmake build (ncfig/ncmarquee under build/, fonts in fonts/)
# when run from a checkout that has one, so it plays fully offline;
# otherwise downloads (or reuses the cached download of) the latest release
# via download.sh. NCFIG_BIN_DIR picks the tools explicitly, skipping both
# of the above. NCFIG_REPO=owner/ncfig uses another fork's releases when
# downloading.

set -euo pipefail

repo="${NCFIG_REPO:-jaydg/ncfig}"
launch="https://raw.githubusercontent.com/$repo/main/scripts/launch.sh"

script_dir=""
case "$0" in
    */*) [ -f "$0" ] && script_dir="$(cd "$(dirname "$0")" && pwd)" ;;
esac

bin_dir="${NCFIG_BIN_DIR:-}"
if [ -z "$bin_dir" ] && [ -n "$script_dir" ] && [ -f "$script_dir/../xmake.lua" ]; then
    repo_root="$(cd "$script_dir/.." && pwd)"
    # the most recently built one, e.g. a fresh `xmake` rather than an older build/release
    ncmarquee_bin="$(find "$repo_root/build" -type f -name ncmarquee -perm -u+x -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null | head -1 || true)"
    if [ -n "$ncmarquee_bin" ] && ls "$repo_root"/fonts/*.flf >/dev/null 2>&1; then
        bin_dir="$(dirname "$ncmarquee_bin")"
        export NCFIG_FONTDIR="${NCFIG_FONTDIR:-$repo_root/fonts}"
        echo "Using the local build in $bin_dir" >&2
    fi
fi

if [ -z "$bin_dir" ]; then
    if [ -n "$script_dir" ] && [ -f "$script_dir/download.sh" ]; then
        bin_dir="$(bash "$script_dir/download.sh")"
    else
        download_tmp="$(mktemp)"
        if ! curl -fsSL "https://raw.githubusercontent.com/$repo/main/scripts/download.sh" -o "$download_tmp"; then
            rm -f "$download_tmp"
            echo "Failed to fetch scripts/download.sh from $repo" >&2
            exit 1
        fi
        bin_dir="$(bash "$download_tmp")"
        rm -f "$download_tmp"
    fi
fi
# the tools look here for fonts given by name, e.g. -f banner
export NCFIG_FONTDIR="${NCFIG_FONTDIR:-$bin_dir/fonts}"

# a wavy, circular marquee; any key ends it
"$bin_dir/ncmarquee" -f banner -h 0xff0000:0x00ff00:0x0000ff -w 3 -c -s 30 "NCFIG"

fonts=""
for f in "$NCFIG_FONTDIR"/*.flf; do f="${f##*/}"; fonts="$fonts ${f%.flf}"; done
cat >&2 <<HINT

That was ncmarquee. More to try (fonts:$fonts):

  bash <(curl -L $launch) ncfig -f slant -v 0xff0000:0x0000ff "Hello"
  bash <(curl -L $launch) ncmarquee -f big -r 0xffff00:0xff00ff -w 4 "WAVE"

Install it: bash <(curl -L https://raw.githubusercontent.com/$repo/main/scripts/install.sh)
HINT
