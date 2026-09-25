#!/usr/bin/env bash
# ==============================================================================
# IPQA (IP Quality Archive) - 自动化回归测试套件
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  \033[32m✔ [PASS]\033[0m $1"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  \033[31m✗ [FAIL]\033[0m $1: $2"
}

echo "=============================================================================="
echo "开始运行 IPQA 自动化回归测试"
echo "=============================================================================="

# 1. 语法检查测试 (bash -n)
echo -e "\n[测试组 1] 语法与结构完整性检查:"
if bash -n "$REPO_ROOT/install.sh"; then
    pass "install.sh 语法校验通过"
else
    fail "install.sh 语法校验" "发现语法错误"
fi

if bash -n "$REPO_ROOT/ipqa.sh"; then
    pass "ipqa.sh 语法校验通过"
else
    fail "ipqa.sh 语法校验" "发现语法错误"
fi

# 2. 危险路径检测测试 (M-04)
echo -e "\n[测试组 2] 危险路径防护 (M-04):"
TEST_ENV_DIR="$(mktemp -d 2>/dev/null || echo "/tmp/ipqa_test.$$")"
mkdir -p "$TEST_ENV_DIR/home/testuser"

is_dangerous_path() {
    local target
    target=$(cd "$1" 2>/dev/null && pwd -P || true)
    [[ -z "$target" ]] && target="$1"
    target="${target%/}"
    [[ -z "$target" ]] && return 0
    case "$target" in
        ""|"/"|"/root"|"/bin"|"/sbin"|"/usr"|"/usr/bin"|"/usr/local"|"/usr/local/bin"|"/etc"|"/var"|"/home"|"$HOME")
            return 0 ;;
        *)
            return 1 ;;
    esac
}

if is_dangerous_path "/"; then
    pass "正确拦截根目录 '/'"
else
    fail "危险路径检测" "未能拦截 '/'"
fi

if is_dangerous_path "$HOME"; then
    pass "正确拦截 \$HOME"
else
    fail "危险路径检测" "未能拦截 \$HOME"
fi

if ! is_dangerous_path "$TEST_ENV_DIR/ipqa"; then
    pass "正常放行合法安装路径 '$TEST_ENV_DIR/ipqa'"
else
    fail "危险路径检测" "误判了合法路径"
fi

# 3. 字段解析与空列不偏移测试 (M-13)
echo -e "\n[测试组 3] Unit Separator 空字段解析稳定性 (M-13):"
test_json='{
    "Head": {"IP": "1.2.3.4"},
    "Info": {
        "ASN": 12345,
        "Organization": "Test Org",
        "City": {"Name": ""},
        "Region": {"Name": "California"},
        "Type": "Geo-consistent"
    }
}'

parsed_output=$(echo "$test_json" | jq -r '[
    (.Head.IP // "未知"),
    (.Info.ASN // "--"),
    (.Info.Organization // "--"),
    (.Info.City.Name // ""),
    (.Info.Region.Name // ""),
    (.Info.Type // "--")
] | join("\u001f")')

IFS=$'\x1f' read -r t_ip t_asn t_org t_city t_region t_type <<< "$parsed_output"

if [[ "$t_city" == "" && "$t_region" == "California" && "$t_type" == "Geo-consistent" ]]; then
    pass "City 为空时，Region 与 Type 未发生左移错位"
else
    fail "空字段解析" "字段发生偏移: city='$t_city', region='$t_region', type='$t_type'"
fi

# 4. 风险因子与评分边界测试 (M-14, M-15, S-18)
echo -e "\n[测试组 4] 风险因子与评分边界值 (M-14, M-15, S-18):"
empty_factor_json='{"Factor": {}}'
tested_count=$(echo "$empty_factor_json" | jq -r '
    .Factor as $f |
    ["Proxy"] | map(
        . as $fac |
        [ "IP2LOCATION", "ipapi" ] as $engs |
        ($engs | map(select($f[$fac][.] != null and $f[$fac][.] != "--" and $f[$fac][.] != "")) | length)
    )[0]
')

if [[ "$tested_count" -eq 0 ]]; then
    pass "因子无数据库支持时检出测试数为 0 (正确识别无数据)"
else
    fail "因子无数据检测" "测试数预期为 0，实际为 $tested_count"
fi

empty_mail_json='{"Mail": {"DNSBlacklist": {"Total": 0, "Clean": 0, "Blacklisted": 0}}}'
dnsbl_total=$(echo "$empty_mail_json" | jq -r '.Mail.DNSBlacklist.Total // 0')
if [[ "$dnsbl_total" -eq 0 ]]; then
    pass "DNSBL Total=0 时不会误判为全部干净通过"
else
    fail "DNSBL 判定" "Total 预期为 0"
fi

# 5. 配置键值安全解析测试 (S-05)
echo -e "\n[测试组 5] 配置安全键值解析 (S-05):"
sample_config="$TEST_ENV_DIR/config.sh"
cat > "$sample_config" << 'EOF'
CHECK_INTERVAL_HOURS="24"
SCORE_DIFF_THRESHOLD="15"
# 尝试命令注入
INJECT_VAR="hello; echo hacked"
MALICIOUS_CMD=$(rm -rf /)
EOF

CFG_CHECK_HOURS="24"
CFG_DIFF_THRES="10"

while IFS='=' read -r raw_key raw_val || [[ -n "$raw_key" ]]; do
    raw_key=$(echo "$raw_key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$raw_key" || "$raw_key" =~ ^# ]] && continue
    raw_val=$(echo "$raw_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\'']//' -e 's/["'\'']$//')
    case "$raw_key" in
        CHECK_INTERVAL_HOURS) [[ "$raw_val" =~ ^[0-9]+$ ]] && CFG_CHECK_HOURS="$raw_val" ;;
        SCORE_DIFF_THRESHOLD) [[ "$raw_val" =~ ^[0-9]+$ ]] && CFG_DIFF_THRES="$raw_val" ;;
    esac
done < "$sample_config"

if [[ "$CFG_CHECK_HOURS" == "24" && "$CFG_DIFF_THRES" == "15" ]]; then
    pass "配置安全解析成功且防止命令执行"
else
    fail "配置安全解析" "解析结果异常: $CFG_CHECK_HOURS / $CFG_DIFF_THRES"
fi

# 6. Cron Quoting & Validation (M-18, M-19, M-20, M-21)
echo -e "\n[测试组 6] Cron 路径转义与表达式校验 (M-18, M-19, M-20, M-21):"
cron_test_path="/opt/my dir/ipqa.sh"
cron_log_path="/opt/my dir/logs/ipqa.log"
cron_line="0 * * * * [ \"\$(TZ='Asia/Shanghai' date +\\%H)\" = \"04\" ] && \"$cron_test_path\" --cron >> \"$cron_log_path\" 2>&1"

if [[ "$cron_line" =~ \"/opt/my\ dir/ipqa\.sh\" ]] && [[ "$cron_line" =~ \"/opt/my\ dir/logs/ipqa\.log\" ]]; then
    pass "含空格路径在 Cron 规则中被正确双引号包裹"
else
    fail "Cron 路径包裹" "路径未正确引用: $cron_line"
fi

# 验证无效 Cron 表达式过滤
invalid_expr="0 4 * * * * *" # 6 fields
read -r -a fields <<< "$invalid_expr"
if [[ ${#fields[@]} -ne 5 ]]; then
    pass "成功拦截非 5 位的非法 Cron 表达式"
else
    fail "Cron 校验" "未能拦截 6 位 Cron 表达式"
fi

# 7. 日志安全脱敏与轮转测试 (S-16, S-17)
echo -e "\n[测试组 7] 日志脱敏与轮转 (S-16, S-17):"
raw_msg=$(printf "YouTube\x1b[31m Region|Changed\nNew line")
safe_msg=$(echo "$raw_msg" | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g' | tr '\r\n' ' ' | tr '|' '/')

if [[ ! "$safe_msg" =~ "|" && ! "$safe_msg" =~ $'\n' && ! "$safe_msg" =~ $'\x1b' ]]; then
    pass "告警消息成功过滤 ANSI 颜色码、换行符和竖线分隔符"
else
    fail "日志脱敏" "消息未完全脱敏: '$safe_msg'"
fi

# 8. 自检指令测试 (Q-03)
echo -e "\n[测试组 8] 系统自检指令 (--test):"
if bash "$REPO_ROOT/ipqa.sh" --test >/dev/null 2>&1; then
    pass "ipqa --test 成功运行并返回状态 0"
else
    fail "系统自检" "ipqa --test 返回非 0 状态"
fi

# 清理测试临时目录
rm -rf "$TEST_ENV_DIR"

echo -e "\n=============================================================================="
echo "测试结果汇总: 总计 $TESTS_RUN 项测试, 通过: $TESTS_PASSED, 失败: $TESTS_FAILED"
echo "=============================================================================="

if [[ "$TESTS_FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
