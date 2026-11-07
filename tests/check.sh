#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

scripts=(install.sh ipqa.sh scripts/*.sh tests/*.sh)
for script in "${scripts[@]}" tests/fixtures/*.sh; do
    bash -n "$script"
done

# Fixtures are upstream excerpts. Check syntax, and lint the code we maintain.
shellcheck -S warning -e SC2181,SC1090,SC1091,SC2086 "${scripts[@]}"
