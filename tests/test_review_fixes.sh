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
mv "$fixture/custom/data" "$fixture/direct-data"
ln -s "$fixture/custom/ipqa.sh" "$fixture/ipqa-link"
env -u IPQA_DIR bash "$fixture/ipqa-link" --help >/dev/null
[[ -d "$fixture/custom/data/v4" ]]
echo 'PASS: installer SSH guard, custom/symlink paths'
