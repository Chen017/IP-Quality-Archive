#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(sed -n '/^is_dangerous_path()/,/^}/p' "$root/install.sh")"
is_dangerous_path "$HOME/.ssh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/custom"
cp "$root/ipqa.sh" "$fixture/custom/ipqa.sh"
touch "$fixture/custom/config.sh"
env -u IPQA_DIR bash "$fixture/custom/ipqa.sh" --help >/dev/null
[[ -d "$fixture/custom/data/v4" ]]
ln -s "$fixture/custom/ipqa.sh" "$fixture/ipqa-link"
env -u IPQA_DIR bash "$fixture/ipqa-link" --help >/dev/null
printf '%s\n' '{"Factor":{"Proxy":{"WHOIS":true}}}' > "$fixture/report.json"
prev_file="$fixture/report.json"
factor=Proxy
query="$(sed -n '/old_val=$(jq -r.*Factor/p' "$root/ipqa.sh" | head -n 1)"
eng=IPQS
eval "$query"
[[ "$old_val" == null ]]
eng=IPWHOIS
eval "$query"
[[ "$old_val" == true ]]
echo 'PASS: installer SSH guard, custom/symlink paths, isolated WHOIS alias'
