#!/usr/bin/env bash
#
# Prints the Homebrew formula for a release:
#
#   scripts/homebrew-formula.sh v0.1.0 dist/SHA256SUMS [owner/ncfig] > Formula/ncfig.rb
#
# SHA256SUMS is the file published with the release (sha256sum output for the
# ncfig-<arch>-<os>.tar.gz archives). The repository defaults to
# $GITHUB_REPOSITORY (set in GitHub Actions) or jaydg/ncfig. The template is
# packaging/homebrew/ncfig.rb.in.

set -euo pipefail
cd "$(dirname "$0")/.."

tag="${1:?usage: $0 <tag> <SHA256SUMS>}"
sums="${2:?usage: $0 <tag> <SHA256SUMS>}"
repo="${3:-${GITHUB_REPOSITORY:-jaydg/ncfig}}"
version="${tag#v}"

formula="$(sed "s/@VERSION@/$version/g; s|@REPO@|$repo|g" packaging/homebrew/ncfig.rb.in)"
for target in x86_64-linux aarch64-linux x86_64-macos aarch64-macos; do
    sha="$(awk -v f="ncfig-$target.tar.gz" '$2 == f || $2 == "*" f {print $1}' "$sums")"
    [ -n "$sha" ] || { echo "no checksum for ncfig-$target.tar.gz in $sums" >&2; exit 1; }
    key="${target//-/_}"
    formula="${formula//@SHA256_${key}@/$sha}"
done

if [[ "$formula" == *@*@* ]]; then
    echo "unreplaced placeholder in formula" >&2
    exit 1
fi
printf '%s\n' "$formula"
