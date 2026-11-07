#!/usr/bin/env bash
# Build the source distribution used by the offline install smoke test.
set -euo pipefail
if [[ $# -ne 1 ]]; then
    printf 'Usage: bash %s OUTPUT.tar.gz\n' "$0" >&2
    exit 2
fi

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
output="$1"
output_dir="$(cd -- "$(dirname -- "$output")" && pwd)"
stage="$(mktemp -d)"
archive=''
trap 'rm -rf -- "$stage"; if [[ -n "$archive" ]]; then rm -f -- "$archive"; fi' EXIT
archive="$(mktemp -- "$output_dir/.ipqa-package.XXXXXXXX")"

install -m 644 "$root/LICENSE" "$root/install.sh" "$stage"
install -m 755 "$root/ipqa.sh" "$stage"
tar --format=ustar --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -C "$stage" -cf - LICENSE install.sh ipqa.sh | gzip -n > "$archive"
chmod 644 "$archive"
mv -fT -- "$archive" "$output"
