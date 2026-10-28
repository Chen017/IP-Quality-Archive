#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export TZ=UTC
V4_DIR="$fixture/v4"
V6_DIR="$fixture/v6"
mkdir -p "$V4_DIR" "$V6_DIR"
for fn in parse_archive_epoch find_matching_v6 fmt_timestamp view_archives; do
    eval "$(sed -n "/^${fn}()/,/^}/p" "$root/ipqa.sh")"
done

# Historical files must not cause a date process per file on each list row.
for ((i=1; i<=80; i++)); do
    printf '{}' > "$V6_DIR/2025-01-01_$(printf '%06d' "$i").json"
done
printf '{}' > "$V6_DIR/2026-10-27_235950.json"
date() { printf '.\n' >> "$fixture/date-calls"; command date "$@"; }
[[ $(find_matching_v6 '2026-10-28_000100') == "$V6_DIR/2026-10-27_235950.json" ]]
[[ $(wc -l < "$fixture/date-calls") -le 5 ]]
[[ $(find_matching_v6 '2026-10-28_000450') == "$V6_DIR/2026-10-27_235950.json" ]]
[[ -z $(find_matching_v6 '2026-10-28_000451') ]]
printf '{}' > "$V6_DIR/2026-10-28_00-01-10.json"
[[ $(find_matching_v6 '2026-10-28_00:01:00') == "$V6_DIR/2026-10-28_00-01-10.json" ]]
printf '{}' > "$V6_DIR/2026-10-28_000100.json"
[[ $(find_matching_v6 '2026-10-28_000100') == "$V6_DIR/2026-10-28_000100.json" ]]
[[ -z $(find_matching_v6 'invalid') ]]

# Empty IPv4 region must still fall back to IPv6. Repainting the same menu
# page must reuse its parsed metadata; reopening the menu reads fresh files.
mkdir -p "$fixture/menu/v4" "$fixture/menu/v6"
V4_DIR="$fixture/menu/v4"
V6_DIR="$fixture/menu/v6"
printf '{"Head":{"IP":"192.0.2.1"},"Info":{"Region":{"Name":""}}}' > "$V4_DIR/2026-10-28_000100.json"
printf '{"Head":{"IP":"2001:db8::1"},"Info":{"Region":{"Name":"Japan"}}}' > "$V6_DIR/2026-10-28_000100.json"
# Colors are consumed by view_archives, loaded dynamically above.
# shellcheck disable=SC2034
C_YELLOW='' C_RESET='' C_BOLD='' C_GREEN='' C_CYAN='' C_GRAY=''
clear() { :; }
print_module_header() { :; }
jq() { printf '.\n' >> "$fixture/jq-calls"; command jq "$@"; }
view_archives <<< $'p\n0' > "$fixture/menu-output"
[[ $(wc -l < "$fixture/jq-calls") -eq 2 ]]
grep -q '192.0.2.1' "$fixture/menu-output"
grep -q '2001:db8::1' "$fixture/menu-output"
grep -q '(Japan)' "$fixture/menu-output"
printf '{"Head":{"IP":"192.0.2.2"}}' > "$V4_DIR/2026-10-28_000100.json"
view_archives <<< '0' > "$fixture/menu-output"
grep -q '192.0.2.2' "$fixture/menu-output"
echo 'PASS: bounded archive matching, midnight/threshold/format compatibility, menu cache and region fallback'
