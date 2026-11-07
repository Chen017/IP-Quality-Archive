#!/usr/bin/env bash
# Install, upgrade and uninstall the extracted bundle without touching the host.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'Usage: bash tests/test_install_bundle.sh BUNDLE.tar.gz' >&2; exit 2; }
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export IPQA_TEST_ROOT="$fixture" HOME="$fixture/home" IPQA_DIR="$fixture/custom install"
export IPQA_OS_RELEASE_FILE="$fixture/os-release"
mkdir -p "$HOME" "$fixture/bundle" "$fixture/remote"
printf 'ID=debian\n' > "$IPQA_OS_RELEASE_FILE"
printf '* * * * * echo keep\n' > "$fixture/crontab"

ln() {
    [[ "${*: -1}" == "$HOME/.local/bin/ipqa" ]] || return 1
    command ln "$@"
}
rm() {
    local arg
    for arg in "$@"; do
        [[ "$arg" == -* || "$arg" == "$IPQA_TEST_ROOT" || "$arg" == "$IPQA_TEST_ROOT/"* ]] || return 1
    done
    command rm "$@"
}
sudo() { return 1; }
apt-get() { touch "$IPQA_TEST_ROOT/unexpected-apt"; return 1; }
curl() {
    case "${*: -3:1}" in
        https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/ipqa.sh)
            cp -- "$IPQA_TEST_ROOT/bundle/ipqa.sh" "${@: -1}" ;;
        *) touch "$IPQA_TEST_ROOT/unexpected-download"; return 1 ;;
    esac
}
crontab() {
    case "$1" in
        -l) cat "$IPQA_TEST_ROOT/crontab" ;;
        -) cat > "$IPQA_TEST_ROOT/crontab" ;;
        *) return 1 ;;
    esac
}
dig() { return 1; }
nslookup() { return 1; }
clear() { :; }
export -f ln rm sudo apt-get curl crontab dig nslookup clear

tar -xzf "$1" -C "$fixture/bundle"
[[ -s "$fixture/bundle/LICENSE" && -x "$fixture/bundle/ipqa.sh" ]]
printf '#!/usr/bin/env bash\nscript_version="bundle-test"\n# %3100s\n' '' > "$fixture/bundle/ip.sh"

run_installer() {
    if ! bash "$fixture/bundle/install.sh" --yes "$@" > "$fixture/install.log" 2>&1; then
        cat "$fixture/install.log" >&2
        return 1
    fi
}
run_installer --disable-auto-update
cmp "$fixture/bundle/ipqa.sh" "$IPQA_DIR/ipqa.sh"
[[ -x "$IPQA_DIR/ip.sh" && "$HOME/.local/bin/ipqa" -ef "$IPQA_DIR/ipqa.sh" ]]
grep -qx 'AUTO_UPDATE_SCRIPT=false' "$IPQA_DIR/config.sh"
env -u IPQA_DIR bash "$HOME/.local/bin/ipqa" --test >/dev/null

printf '{"Head":{"IP":"192.0.2.1"}}\n' > "$IPQA_DIR/data/v4/2026-10-28_000100.json"
cp -- "$IPQA_DIR/config.sh" "$fixture/config.before"
printf '# update from local bundle\n' >> "$fixture/bundle/ipqa.sh"
run_installer --enable-auto-update
cmp "$fixture/bundle/ipqa.sh" "$IPQA_DIR/ipqa.sh"
cmp "$fixture/config.before" "$IPQA_DIR/config.sh"
[[ -f "$IPQA_DIR/data/v4/2026-10-28_000100.json" ]]

run_installer --uninstall
[[ ! -L "$HOME/.local/bin/ipqa" && -f "$IPQA_DIR/data/v4/2026-10-28_000100.json" ]]
run_installer --uninstall --purge
[[ ! -e "$IPQA_DIR" ]]
grep -Fxq '* * * * * echo keep' "$fixture/crontab"

# A custom runtime data directory is not necessarily an IPQA installation.
mkdir -p "$IPQA_DIR"
touch "$IPQA_DIR/keep"
if printf 'y\ny\n' | bash "$fixture/bundle/ipqa.sh" --uninstall > "$fixture/uninstall.log" 2>&1; then
    echo 'FAIL: runtime accepted purge of an unverified directory' >&2
    exit 1
fi
[[ -f "$IPQA_DIR/keep" ]]
grep -q '目标不是可验证的 IPQA 安装目录' "$fixture/uninstall.log"

# Standalone installer path: validated remote bytes must not be moved INTO a
# directory called ipqa.sh or reported as installed.
cp -- "$fixture/bundle/install.sh" "$fixture/remote/install.sh"
mkdir "$IPQA_DIR/ipqa.sh"
if bash "$fixture/remote/install.sh" --yes > "$fixture/remote.log" 2>&1; then
    echo 'FAIL: standalone install succeeded with a blocked destination' >&2
    exit 1
fi
grep -q '无法获取有效的 ipqa.sh' "$fixture/remote.log"
[[ -z $(find "$IPQA_DIR" -name '*.tmp.*' -print -quit) ]]
[[ ! -e "$fixture/unexpected-apt" && ! -e "$fixture/unexpected-download" ]]
echo 'PASS: bundle install, upgrade and uninstall, purge guard, standalone promotion failure'
