#!/usr/bin/env bash
# Exercise the real CLI against deterministic core reports and mocked downloads.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export HOME="$fixture/home" IPQA_DIR="$fixture/install" TZ=UTC TERM=dumb
mkdir -p "$HOME" "$IPQA_DIR/data/"{v4,v6}
printf 'HAS_V6="true"\nAUTO_UPDATE_SCRIPT=false\n' > "$IPQA_DIR/config.sh"

export IPQA_TEST_CORE="$fixture/remote-core" IPQA_TEST_MAIN="$root/ipqa.sh"
export IPQA_TEST_FETCHES="$fixture/fetches"
export IPQA_TEST_TIME='2026-10-28_000100' IPQA_TEST_NETFLIX='解锁'
export IPQA_TEST_WHOIS=false
export IPQA_TEST_BLOCK_UPDATE=false
date() {
    case "$*" in
        '+%Y-%m-%d_%H%M%S') printf '%s\n' "$IPQA_TEST_TIME" ;;
        '+%s') printf '1800000000\n' ;;
        *) command date "$@" ;;
    esac
}
curl() {
    local arg candidate
    for arg in "$@"; do
        case "$arg" in
            https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh|https://IP.Check.Place)
                candidate="$IPQA_TEST_CORE"; break ;;
            https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/ipqa.sh\?*)
                candidate="$IPQA_TEST_MAIN"; break ;;
        esac
    done
    printf '%s\n' "$arg" >> "$IPQA_TEST_FETCHES"
    [[ -n "${candidate:-}" && "${*: -2:1}" == -o ]] || return 99
    cp -- "$candidate" "${@: -1}"
}
mv() {
    if [[ "$IPQA_TEST_BLOCK_UPDATE" == true && "${*: -1}" == "$IPQA_DIR/ip.sh" &&
          "${*: -2:1}" == "$IPQA_DIR/".ip.sh.tmp.* ]]; then
        return 1
    fi
    command mv "$@"
}
clear() { :; }
crontab() { return 1; }
export -f date curl mv clear crontab

cat > "$IPQA_TEST_CORE" <<'CORE'
#!/usr/bin/env bash
script_version="test"
while (( $# )); do
    case "$1" in
        -4) address=192.0.*.* ;;
        -6) address=2001:db8:*:*:*:*:* ;;
        -o) output="$2"; shift ;;
    esac
    shift
done
printf '{"Head":{"IP":"%s"},"Media":{"Netflix":{"Status":"%s"}},"Factor":{"Proxy":{"WHOIS":%s}}}\n' \
    "$address" "$IPQA_TEST_NETFLIX" "$IPQA_TEST_WHOIS" > "$output"
CORE
# Match the minimum size contract without downloading or running the upstream.
printf '# %3100s\n' '' >> "$IPQA_TEST_CORE"
cp -- "$IPQA_TEST_CORE" "$IPQA_DIR/ip.sh"
printf '# fix with the same script_version\n' >> "$IPQA_TEST_CORE"
run_ipqa() {
    if ! timeout 30s bash "$root/ipqa.sh" "$@" > "$fixture/cli.log" 2>&1; then
        cat "$fixture/cli.log" >&2
        return 1
    fi
}

run_ipqa --cron
cmp "$IPQA_TEST_CORE" "$IPQA_DIR/ip.sh"
[[ $(cat "$IPQA_DIR/.last_core_update") == 1800000000 ]]
[[ $(wc -l < "$IPQA_TEST_FETCHES") -eq 1 ]]
jq -e '.Head.IP == "192.0.*.*"' "$IPQA_DIR/data/v4/$IPQA_TEST_TIME.json" >/dev/null
jq -e '.Head.IP == "2001:db8:*:*:*:*:*"' "$IPQA_DIR/data/v6/$IPQA_TEST_TIME.json" >/dev/null
cp -- "$IPQA_DIR/ip.sh" "$fixture/good-core"

# Bad remote candidate: keep collecting with the cached core and retry next run.
printf '0\n' > "$IPQA_DIR/.last_core_update"
printf 'if [\n' > "$IPQA_TEST_CORE"
IPQA_TEST_TIME='2026-10-28_000200' IPQA_TEST_NETFLIX='未解锁' IPQA_TEST_WHOIS=true run_ipqa --cron
cmp "$fixture/good-core" "$IPQA_DIR/ip.sh"
[[ $(cat "$IPQA_DIR/.last_core_update") == 0 ]]
grep -q '|CRITICAL|Netflix 解锁状态发生降级: \[解锁\] 变为 \[未解锁\]|IPv4$' "$IPQA_DIR/data/alerts.log"
[[ $(grep -c '新增风险标记:.*|IPv4$' "$IPQA_DIR/data/alerts.log") -eq 1 ]]
grep -q '|WARNING|新增风险标记: IPWHOIS 检出 Proxy 因子|IPv4$' "$IPQA_DIR/data/alerts.log"

# A valid candidate can still fail promotion. Both archive destinations are
# directories, so neither report can be published and --cron must fail.
cp -- "$fixture/good-core" "$IPQA_TEST_CORE"
printf '# cannot promote yet\n' >> "$IPQA_TEST_CORE"
IPQA_TEST_TIME='2026-10-28_000300'
mkdir "$IPQA_DIR/data/"{v4,v6}"/$IPQA_TEST_TIME.json"
if IPQA_TEST_BLOCK_UPDATE=true bash "$root/ipqa.sh" --cron > "$fixture/cli.log" 2>&1; then
    echo 'FAIL: --cron succeeded without publishing either report' >&2
    exit 1
fi
cmp "$fixture/good-core" "$IPQA_DIR/ip.sh"
[[ $(cat "$IPQA_DIR/.last_core_update") == 0 ]]
grep -q '无法写入检测核心更新' "$IPQA_DIR/logs/ipqa.log"
[[ -z $(find "$IPQA_DIR/data" -name '*.tmp.*' -print -quit) ]]
[[ ! -d "$IPQA_DIR/.lock_main" ]]

# A failed main script replacement must report partial success accurately.
mkdir "$IPQA_DIR/ipqa.sh"
rm "$IPQA_DIR/.last_script_update"
if bash "$root/ipqa.sh" --update > "$fixture/cli.log" 2>&1; then
    echo 'FAIL: --update succeeded without replacing the main script' >&2
    exit 1
fi
grep -q 'IPQA 主程序更新失败，检测核心已更新' "$fixture/cli.log"
cmp "$IPQA_TEST_CORE" "$IPQA_DIR/ip.sh"
[[ ! -e "$IPQA_DIR/.last_script_update" && ! -d "$IPQA_DIR/.lock_main" ]]
[[ -z $(find "$IPQA_DIR" -name '*.tmp.*' -print -quit) ]]
echo 'PASS: CLI content sync, dual-stack archive, downgrade alerts and failed promotion'

# Real menu paths must distinguish false from unknown and count legacy WHOIS
# only when its canonical field is absent.
IPQA_DIR="$fixture/display"
mkdir -p "$IPQA_DIR/data/"{v4,v6}
cp -- "$root/ipqa.sh" "$IPQA_DIR/ipqa.sh"
cp -- "$fixture/good-core" "$IPQA_DIR/ip.sh"
printf '1800000000\n' > "$IPQA_DIR/.last_core_update"
printf '1800000000\n' > "$IPQA_DIR/.last_script_update"
cat > "$IPQA_DIR/data/v4/2026-10-28_000100.json" <<'JSON'
{
  "Head": {"IP": "192.0.2.1"},
  "Factor": {
    "Proxy": {"IPWHOIS": false, "WHOIS": true},
    "Tor": {"IPQS": false, "WHOIS": "true"},
    "VPN": {"IPQS": null}
  },
  "Mail": {"Port25": false}
}
JSON
printf '3\n5\n\n5\n5\n\n7\n1\n\n0\n0\n' | run_ipqa
grep -Eq 'Proxy .*保持安全' "$fixture/cli.log"
grep -Eq 'Tor .*1/2' "$fixture/cli.log"
grep -Eq 'VPN .*暂无数据' "$fixture/cli.log"
grep -Eq 'Proxy: .*正常.*Tor: .*检出' "$fixture/cli.log"
grep -q '拦截/关闭' "$fixture/cli.log"
grep -q '拦截/封禁' "$fixture/cli.log"
run_ipqa </dev/null
echo 'PASS: risk and mail history and snapshot distinguish false from unknown'
