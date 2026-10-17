#!/usr/bin/env bash
#
# Try ncfig without installing anything:
#
#   bash <(curl -L https://raw.githubusercontent.com/jaydg/ncfig/main/scripts/launch.sh)
#
# Downloads the latest release for this machine into a temporary directory
# (see download.sh) and runs it from there. Without arguments it plays a
# short demo (see demo.sh, which prefers a local build when run from a
# checkout). Otherwise the first argument picks the tool and the rest are
# passed on, e.g.
#
#   ... launch.sh) ncfig -f slant -v 0xff0000:0x0000ff "Hello"
#   ... launch.sh) ncmarquee -f banner -w 3 -c "LOOP"

set -euo pipefail

repo="${NCFIG_REPO:-jaydg/ncfig}"

script_dir=""
case "$0" in
    */*) [ -f "$0" ] && script_dir="$(cd "$(dirname "$0")" && pwd)" ;;
esac

tool="ncfig"
case "${1:-}" in
    ncfig|ncmarquee) tool="$1"; shift ;;
esac

if [ $# -eq 0 ] && [ "$tool" = "ncfig" ]; then
    if [ -n "$script_dir" ] && [ -f "$script_dir/demo.sh" ]; then
        exec bash "$script_dir/demo.sh"
    else
        demo_tmp="$(mktemp)"
        if ! curl -fsSL "https://raw.githubusercontent.com/$repo/main/scripts/demo.sh" -o "$demo_tmp"; then
            rm -f "$demo_tmp"
            echo "Failed to fetch scripts/demo.sh from $repo" >&2
            exit 1
        fi
        exec bash "$demo_tmp"
    fi
fi

if [ -n "$script_dir" ] && [ -f "$script_dir/download.sh" ]; then
    dir="$(bash "$script_dir/download.sh")"
else
    download_tmp="$(mktemp)"
    if ! curl -fsSL "https://raw.githubusercontent.com/$repo/main/scripts/download.sh" -o "$download_tmp"; then
        rm -f "$download_tmp"
        echo "Failed to fetch scripts/download.sh from $repo" >&2
        exit 1
    fi
    dir="$(bash "$download_tmp")"
    rm -f "$download_tmp"
fi

# the tools look here for fonts given by name, e.g. -f banner
export NCFIG_FONTDIR="$dir/fonts"

exec "$dir/$tool" "$@"
