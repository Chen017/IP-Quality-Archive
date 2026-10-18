#!/usr/bin/env bash
# Exercise patched upstream queries, terminal scores and JSON without networking.
# shellcheck disable=SC2034 # Globals are consumed by upstream functions loaded below.
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_TMP="$(mktemp -d)"
trap 'rm -rf "$TASK_TMP"' EXIT
fail() { echo "Lite FAIL: $*" >&2; exit 1; }

declare -A maxmind ipinfo scamalytics ipregistry ipapi abuseipdb ip2location
declare -A dbip ipdata ipqs ipwhois tiktok disney netflix youtube amazon reddit chatgpt
declare -A sinfo shead sbasic stype sscore sfactor smedia smail stail
sinfo[ldatabase]=0
sscore[low]=Low sscore[medium]=Medium sscore[high]=High
sscore[verylow]=VeryLow sscore[elevated]=Elevated sscore[veryhigh]=VeryHigh
sscore[suspicious]=Suspicious sscore[risky]=Risky sscore[highrisk]=HighRisk
CurlARG='' YY=en fullIP=1 mode_lite=0 mode_json=0 mode_privacy=1 mode_output=1 ADLines=0 IPV4work=1
script_version=fixture

for name in countRunTimes db_ipregistry generate_dms generate_googlemap_url hide_ipv4 hide_ipv6 show_progress_bar kill_progress_bar show_head show_type show_type_lite show_factor show_factor_lite show_media show_mail show_tail check_mail check_dnsbl MediaUnlockTest_TikTok MediaUnlockTest_DisneyPlus MediaUnlockTest_Netflix MediaUnlockTest_YouTube_Premium MediaUnlockTest_PrimeVideo_Region MediaUnlockTest_Reddit OpenAITest; do
    eval "$name(){ :; }"
done
db_ipinfo() { ipinfo[asn]=AS-FALLBACK; ipinfo[org]=Fallback; }
db_ipdata() { echo "ipdata|$1|$IP" >> "$TASK_TMP/calls"; }
show_basic() { echo INFO=FULL; }
show_basic_lite() { echo INFO=LITE; }
sscore_text() { sscore[text1]="$1"; }
bc() { awk '{printf "%d", $1 * 10000}'; }

curl() {
    local url='' family='' arg provider
    for arg in "$@"; do
        case "$arg" in
            -4|-6) family="${arg#-}" ;;
            https://*) url="$arg" ;;
        esac
    done
    case "$url" in
        "https://ipinfo.check.place/$IP?lang=en")
            echo "maxmind|$family|$IP" >> "$TASK_TMP/calls"
            if [[ $basic_mode == full ]]; then
                printf '{"ASN":{"AutonomousSystemNumber":"64500"},"City":{"Latitude":null,"Longitude":null}}'
            else
                printf '<html>Unavailable</html>'
            fi
            ;;
        "https://ipinfo.check.place/$IP?db="*)
            provider="${url##*?db=}"
            echo "$provider|$family|$IP" >> "$TASK_TMP/calls"
            if [[ $scenario == missing ]]; then
                printf '{"country_code":"US","is_proxy":false}'
                return 0
            fi
            case "$provider" in
                scamalytics)
                    if [[ $scenario == mixed ]]; then printf '<html>Denied</html>'
                    elif [[ $scenario == invalid ]]; then printf '{"scamalytics":{"scamalytics_score":-1}}'
                    else printf '{"scamalytics":{"scamalytics_score":37}}'; fi
                    ;;
                ipapi)
                    if [[ $scenario == mixed ]]; then printf '{"company":null,"location":{"country_code":"US"}}'
                    elif [[ $scenario == invalid ]]; then printf '{"company":{"abuser_score":"NaN (Low)"}}'
                    else printf '{"company":{"abuser_score":"0.0313 (High)","type":"hosting"},"asn":{"type":"hosting"},"location":{"country_code":"US"}}'; fi
                    ;;
                abuseipdb)
                    if [[ $scenario == invalid ]]; then printf '{"data":{"abuseConfidenceScore":101}}'
                    else printf '{"data":{"abuseConfidenceScore":0}}'; fi
                    ;;
                ip2location)
                    if [[ $scenario == mixed ]]; then printf '{"error":"NOT_SUPPORTED","fraud_score":0}'
                    elif [[ $scenario == invalid ]]; then printf '{"fraud_score":100.5}'
                    else printf '{"fraud_score":3,"country_code":"US"}'; fi
                    ;;
                ipqualityscore)
                    if [[ $scenario == mixed ]]; then printf '{"fraud_score":"null","country_code":"US","proxy":false}'
                    elif [[ $scenario == invalid ]]; then printf '{"fraud_score":true}'
                    else printf '{"fraud_score":75,"country_code":"US","proxy":false}'; fi
                    ;;
                *) fail "unexpected provider $provider" ;;
            esac
            ;;
        https://db-ip.com/api/core/)
            echo "dbip-key|$family|$IP" >> "$TASK_TMP/calls"
            printf '<div data-api-key="fixture-key"></div>\nIPQA_DBIP_HTTP:200'
            ;;
        https://api.db-ip.com/v2/fixture-key/self\?convertCurrencies)
            echo "dbip-api|$family|$IP" >> "$TASK_TMP/calls"
            printf '{"threatLevel":"low","countryCode":"US"}\nIPQA_DBIP_HTTP:200'
            ;;
        *) fail "unmocked request blocked: $url" ;;
    esac
}

for patch_source in ipqa.sh install.sh; do
    eval "$(sed -n '/^patch_ip_script()/,/^}/p' "$REPO_ROOT/$patch_source")"
    candidate="$TASK_TMP/$patch_source"
    cat "$SCRIPT_DIR/fixtures/dbip-core.sh" "$SCRIPT_DIR/fixtures/lite-core.sh" > "$candidate"
    patch_ip_script "$candidate" || fail "$patch_source patch failed"
    cp "$candidate" "$candidate.once"
    patch_ip_script "$candidate" || fail "repeat patch failed"
    cmp -s "$candidate" "$candidate.once" || fail "patch is not idempotent"
    source "$candidate"
    # ANSI formatting is covered by the main suite; these fixtures contain no escapes.
    clean_ansi() { printf '%s' "$1"; }

    for case_name in lite6-success lite4-success lite6-mixed lite6-missing full6-success; do
        basic_mode=lite scenario=success family=6
        case "$case_name" in
            lite4-success) family=4 ;;
            lite6-mixed) scenario=mixed ;;
            lite6-missing) scenario=missing ;;
            full6-success) basic_mode=full ;;
        esac
        if [[ $family == 6 ]]; then IP=2001:db8::10; else IP=192.0.2.10; fi
        outputfile="$TASK_TMP/$patch_source-$case_name.json"
        : > "$TASK_TMP/calls"
        # Upstream runs without errexit; failed providers must not stop later ones.
        if ! check_IP "$IP" "$family" > "$TASK_TMP/report" 2>"$TASK_TMP/stderr"; then
            fail "$patch_source/$case_name collector failed"
        fi
        [[ ! -s "$TASK_TMP/stderr" ]] || { cat "$TASK_TMP/stderr" >&2; fail "$case_name parse/arithmetic error"; }
        for provider in maxmind scamalytics ipapi abuseipdb ip2location ipqualityscore; do
            [[ $(grep -Fc "$provider|$family|$IP" "$TASK_TMP/calls") -eq 1 ]] || fail "$case_name $provider skipped/retried or wrong target"
        done
        if [[ $basic_mode == lite ]]; then
            [[ $mode_lite == 1 ]] || fail "basic fallback disabled"
            grep -q INFO=LITE "$TASK_TMP/report" || fail "Lite basic report lost"
            jq -e '.Info.ASN == "AS-FALLBACK"' "$outputfile" >/dev/null || fail "Lite JSON info lost"
            ! grep -q '^ipdata|' "$TASK_TMP/calls" || fail "unrelated Lite queries enabled"
        else
            [[ $mode_lite == 0 ]] || fail "full mode changed"
            jq -e '.Info.ASN == "64500"' "$outputfile" >/dev/null || fail "full JSON info changed"
            [[ $(grep -c '^ipdata|' "$TASK_TMP/calls") -eq 1 ]] || fail "full query removed"
        fi
        if [[ $family == 6 ]]; then
            ! grep -q '^dbip-' "$TASK_TMP/calls" || fail "IPv6 queried DB-IP self"
            jq -e '.Score.DBIP == "null"' "$outputfile" >/dev/null || fail "IPv4 DB-IP score leaked"
        else
            jq -e '.Score.DBIP == "0"' "$outputfile" >/dev/null || fail "IPv4 DB-IP regressed"
        fi
        case "$scenario" in
            success)
                jq -e '.Score.SCAMALYTICS == "37" and .Score.IP2LOCATION == "3" and .Score.AbuseIPDB == "0" and .Score.IPQS == "75" and .Score.ipapi == "3.13%"' "$outputfile" >/dev/null || fail "$case_name scores lost in JSON"
                for label in Scamalytics IP2Location AbuseIPDB IPQS ipapi; do
                    grep -q "$label" "$TASK_TMP/report" || fail "Lite hides $label"
                done
                ;;
            mixed)
                jq -e '.Score.SCAMALYTICS == "null" and .Score.ipapi == "null" and .Score.IP2LOCATION == "null" and .Score.IPQS == "null" and .Score.AbuseIPDB == "0" and .Factor.CountryCode.IPQS == "US" and .Factor.Proxy.IPQS == false' "$outputfile" >/dev/null || fail "failed providers stopped others or produced fake scores"
                ;;
            missing)
                jq -e '.Score | [.SCAMALYTICS,.ipapi,.AbuseIPDB,.IP2LOCATION,.IPQS] | all(. == "null")' "$outputfile" >/dev/null || fail "missing scores became zero"
                ! grep -q 'Low' "$TASK_TMP/report" || fail "missing scores displayed as low risk"
                ;;
        esac
        echo "Lite PASS: $patch_source/$case_name (queries, display, JSON, target family)"
    done

    scenario=invalid
    for function in db_scamalytics db_ipapi db_abuseipdb db_ip2location db_ipqs; do
        "$function" 6 > /dev/null 2>"$TASK_TMP/stderr" || :
        [[ ! -s "$TASK_TMP/stderr" ]] || fail "invalid score arithmetic error"
    done
    [[ -z ${scamalytics[score]} && -z ${ipapi[score]} && -z ${abuseipdb[score]} && -z ${ip2location[score]} && -z ${ipqs[score]} ]] || fail "out-of-range/non-numeric scores accepted"
    echo "Lite PASS: $patch_source invalid scores remain unknown"
done
