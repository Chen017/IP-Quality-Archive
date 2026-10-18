#!/usr/bin/env bash
# Offline DB-IP cache migration, failure diagnostics and score regressions.
# shellcheck disable=SC2034 # Globals are consumed by production functions loaded with eval.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_TMP="$(mktemp -d)"
trap 'rm -rf "$TASK_TMP"' EXIT
fail() { echo "DB-IP FAIL: $*" >&2; exit 1; }

# Extract only the patched function; every curl call below is mocked.
declare -A dbip sinfo sscore
sinfo[database]=Database
sinfo[ldatabase]=0
sscore[low]=Low
sscore[medium]=Medium
sscore[high]=High
# Globals consumed by the production function loaded with eval.
# shellcheck disable=SC2034
Font_Cyan='' Font_B='' Font_I='' Font_Suffix='' CurlARG='' ibar_step=0
show_progress_bar() { :; }
kill_progress_bar() { :; }

curl() {
    local url='' arg family=''
    for arg in "$@"; do
        case "$arg" in
            -4|-6|-) family="$arg" ;;
            https://db-ip.com/*|https://api.db-ip.com/*) url="$arg" ;;
        esac
    done
    echo "$family $url" >> "$TASK_TMP/calls"
    [[ -z "$family" ]] || fail "forced connection family remains"
    case "$url" in
        https://db-ip.com/api/core/)
            case "$scenario" in
                no_key) printf '<html>No key</html>\nIPQA_DBIP_HTTP:200' ;;
                key_http) printf '<html>Denied</html>\nIPQA_DBIP_HTTP:403' ;;
                timeout) printf '\nIPQA_DBIP_HTTP:000'; return 28 ;;
                *) printf '<div data-api-key="fixture-key"></div>\nIPQA_DBIP_HTTP:200' ;;
            esac
            ;;
        https://api.db-ip.com/v2/fixture-key/self\?convertCurrencies)
            case "$scenario" in
                low|medium|high) printf '{"threatLevel":"%s","countryCode":"HK","isProxy":false,"isCrawler":false}\nIPQA_DBIP_HTTP:200' "$scenario" ;;
                api_http) printf '<html>Rate limited</html>\nIPQA_DBIP_HTTP:429' ;;
                error) printf '{"errorCode":"ACCESS_DENIED"}\nIPQA_DBIP_HTTP:200' ;;
                malformed) printf '<html>Denied</html>\nIPQA_DBIP_HTTP:200' ;;
                null) printf 'null\nIPQA_DBIP_HTTP:200' ;;
                unknown) printf '{"countryCode":"HK"}\nIPQA_DBIP_HTTP:200' ;;
                *) fail "unhandled scenario $scenario" ;;
            esac
            ;;
        *) fail "unexpected URL $url" ;;
    esac
}

for patch_source in ipqa.sh install.sh; do
    eval "$(sed -n '/^patch_ip_script()/,/^}/p' "$REPO_ROOT/$patch_source")"
    for variant in upstream explicit_target runtime_patch deployed_cache legacy_guard; do
        candidate="$TASK_TMP/$patch_source-$variant.sh"
        cp "$SCRIPT_DIR/fixtures/dbip-core.sh" "$candidate"
        case "$variant" in
            explicit_target)
                sed -i 's#/self?convertCurrencies#/$IP?convertCurrencies#' "$candidate"
                ;;
            runtime_patch)
                sed -i '/api\.db-ip\.com.*self?convertCurrencies/s/ -sL / -sL -$1 /' "$candidate"
                ;;
            deployed_cache)
                sed -i 's/ -sL / -sL -$1 /; /^local tmpurl=/a\[[ -z $tmpurl ]]\&\&return 1' "$candidate"
                ;;
            legacy_guard)
                awk '
                    { print }
                    /^echo "\$RESPONSE"\|jq / {
                        print "local dbip_error dbip_ip"
                        print "dbip_ip=$(echo \"$RESPONSE\"|jq -r \".ipAddress // empty\")"
                        print "if [[ $dbip_ip != *:* ]];then"
                        print "RESPONSE=\"\""
                        print "fi"
                    }
                ' "$candidate" > "$candidate.legacy"
                mv "$candidate.legacy" "$candidate"
                ;;
        esac
        patch_ip_script "$candidate" || fail "$patch_source/$variant patch failed"
        cp "$candidate" "$candidate.once"
        patch_ip_script "$candidate" || fail "repeat patch failed"
        cmp -s "$candidate" "$candidate.once" || fail "patch is not idempotent"
        bash -n "$candidate" || fail "patched function is invalid"
        eval "$(sed -n '/^db_dbip(){/,/^}/p' "$candidate")"

        for scenario in low medium high; do
            IP=192.0.2.10
            : > "$TASK_TMP/calls"
            db_dbip 4 > /dev/null 2>"$TASK_TMP/stderr" || fail "$scenario rejected"
            case "$scenario" in low) expected=0 ;; medium) expected=50 ;; high) expected=100 ;; esac
            [[ ${dbip[score]:-missing} == "$expected" ]] || fail "$scenario score missing"
            [[ ${dbip[countrycode]:-} == HK && ${dbip[proxy]:-} == false ]] || fail "factors lost"
            [[ $(wc -l < "$TASK_TMP/calls") -eq 2 ]] || fail "extra request or retry"
            [[ ! -s "$TASK_TMP/stderr" ]] || fail "successful lookup logged an error"
        done

        for scenario in no_key key_http timeout api_http error malformed null unknown; do
            IP=192.0.2.10
            dbip[score]=100
            : > "$TASK_TMP/calls"
            db_dbip 4 > /dev/null 2>"$TASK_TMP/stderr" || :
            [[ -z ${dbip[score]:-} ]] || fail "$scenario retained stale score"
            grep -q '\[IPQA DB-IP\]' "$TASK_TMP/stderr" || fail "$scenario missing diagnostics"
            case "$scenario" in
                no_key|key_http|timeout) expected_calls=1 ;;
                *) expected_calls=2 ;;
            esac
            [[ $(wc -l < "$TASK_TMP/calls") -eq "$expected_calls" ]] || fail "$scenario request count"
            case "$scenario" in
                key_http) grep -q 'stage=key http=403' "$TASK_TMP/stderr" || fail "key status missing" ;;
                api_http) grep -q 'stage=api http=429' "$TASK_TMP/stderr" || fail "API status missing" ;;
                error) grep -q 'error=ACCESS_DENIED' "$TASK_TMP/stderr" || fail "API error missing" ;;
            esac
            ! grep -q fixture-key "$TASK_TMP/stderr" || fail "temporary key leaked"
        done

        IP=2001:db8::10
        dbip[score]=50
        : > "$TASK_TMP/calls"
        db_dbip 6 > /dev/null 2>"$TASK_TMP/stderr" || :
        [[ -z ${dbip[score]:-} && ! -s "$TASK_TMP/calls" ]] || fail "IPv6 queried /self or kept IPv4 data"
        echo "DB-IP PASS: $patch_source/$variant (scores, failures, IPv6, idempotence)"
    done
done

# Exercise the real collector with a fake core; no provider requests are made.
(
    eval "$(sed -n '/^validate_json()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
    eval "$(sed -n '/^validate_ipqa_report()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
    eval "$(sed -n '/^run_check()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
    acquire_lock() { return 0; }
    cleanup_main_lock() { :; }
    load_config() { :; }
    ensure_ip_script() { return 0; }
    auto_update_if_needed() { :; }
    save_config() { :; }
    compare_and_alert() { :; }
    log_msg() { printf '%s|%s\n' "$1" "$2" >> "$TASK_TMP/collector.log"; }
    HAS_V6=false V6_CHECK_COUNT=0 V6_PROBE_INTERVAL=10 KEEP_MAX_ARCHIVES=0
    V4_DIR="$TASK_TMP/data/v4" V6_DIR="$TASK_TMP/data/v6"
    mkdir -p "$V4_DIR" "$V6_DIR"
    IP_SCRIPT="$TASK_TMP/mock-core.sh"
    cat > "$IP_SCRIPT" <<'CORE'
#!/usr/bin/env bash
echo 'progress bar: raw output must not be logged' >&2
printf '\r\033[2K[IPQA DB-IP] stage=api http=429\n' >&2
while (( $# )); do
    if [[ "$1" == -o ]]; then
        printf '{"Head":{"IP":"192.0.2.10"},"Score":{"DBIP":"null"}}' > "$2"
        exit 0
    fi
    shift
done
CORE
    run_check true || fail "collector rejected otherwise valid report"
    grep -q 'WARN|IPv4 \[IPQA DB-IP\] stage=api http=429' "$TASK_TMP/collector.log" || fail "collector discarded DB-IP diagnostic"
    ! grep -q 'progress bar' "$TASK_TMP/collector.log" || fail "collector logged raw core stderr"
    [[ -z $(find "$V4_DIR" -name '*.stderr.*' -print) ]] || fail "stderr temporary file leaked"
    jq -e '.Score.DBIP == "null"' "$V4_DIR"/*.json >/dev/null || fail "failed score was rewritten"
    echo "DB-IP PASS: collector records diagnostics and preserves unknown scores"
)
