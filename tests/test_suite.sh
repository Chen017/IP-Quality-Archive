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

# N-06: 严格沙箱隔离测试环境，杜绝污染或修改真实的 ~/.ipqa
TEST_ENV_DIR="$(mktemp -d 2>/dev/null || echo "/tmp/ipqa_test.$$")"
export IPQA_DIR="$TEST_ENV_DIR/ipqa_home"
export IPQA_HOME="$IPQA_DIR"
mkdir -p "$IPQA_DIR"
trap 'rm -rf "$TEST_ENV_DIR"' EXIT

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

# 2. 生产危险路径检测测试 (M-04A, M-04B, S-14A: 直接抽取测试生产代码)
echo -e "\n[测试组 2] 生产危险路径防护测试 (M-04A, M-04B):"
eval "$(sed -n '/^is_dangerous_path()/,/^}/p' "$REPO_ROOT/ipqa.sh")"

if is_dangerous_path "/"; then
    pass "正确拦截根目录 '/'"
else
    fail "危险路径检测" "未能拦截 '/'"
fi

if is_dangerous_path "/usr/local"; then
    pass "正确拦截关键系统路径 '/usr/local' (M-04A)"
else
    fail "危险路径检测" "未能拦截 '/usr/local'"
fi

if is_dangerous_path "/usr/local/bin"; then
    pass "正确拦截系统命令路径 '/usr/local/bin' (M-04A)"
else
    fail "危险路径检测" "未能拦截 '/usr/local/bin'"
fi

if is_dangerous_path "/var/lib"; then
    pass "正确拦截系统数据路径 '/var/lib' (M-04A)"
else
    fail "危险路径检测" "未能拦截 '/var/lib'"
fi

if is_dangerous_path "$HOME"; then
    pass "正确拦截 \$HOME"
else
    fail "危险路径检测" "未能拦截 \$HOME"
fi

if is_dangerous_path "$HOME/.local"; then
    pass "正确拦截用户核心目录 '\$HOME/.local' (M-04A)"
else
    fail "危险路径检测" "未能拦截 '\$HOME/.local'"
fi

if ! is_dangerous_path "$IPQA_DIR"; then
    pass "正常放行合法安装路径 '$IPQA_DIR'"
else
    fail "危险路径检测" "误判了合法测试路径"
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

# shellcheck disable=SC2034 # t_ip, t_asn, t_org 用于保持 Unit Separator 字段位置对齐
IFS=$'\x1f' read -r t_ip t_asn t_org t_city t_region t_type <<< "$parsed_output"

if [[ "$t_city" == "" && "$t_region" == "California" && "$t_type" == "Geo-consistent" ]]; then
    pass "City 为空时，Region 与 Type 未发生左移错位"
else
    fail "空字段解析" "字段发生偏移: city='$t_city', region='$t_region', type='$t_type'"
fi

# 4. 生产配置安全解析与 Legacy 兼容测试 (N-05, S-05, S-14A)
echo -e "\n[测试组 4] 配置解析与 Legacy AUTO_UPDATE 兼容测试 (N-05, S-05):"
CONFIG_FILE="$IPQA_DIR/config.sh"
cat > "$CONFIG_FILE" << 'EOF'
AUTO_UPDATE="false"
SCORE_DIFF_THRESHOLD="15"
EOF

# 载入生产 load_config 与 save_config 函数并执行
eval "$(sed -n '/^load_config()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
eval "$(sed -n '/^save_config()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
load_config

if [[ "$AUTO_UPDATE_SCRIPT" == "false" ]]; then
    pass "成功从旧版 AUTO_UPDATE=false 回退解析并关闭脚本自动更新 (N-05)"
else
    fail "旧版配置兼容" "AUTO_UPDATE_SCRIPT 预期为 false，实际为 $AUTO_UPDATE_SCRIPT"
fi

if [[ "$SCORE_DIFF_THRESHOLD" == "15" ]]; then
    pass "正常解析数值配置 SCORE_DIFF_THRESHOLD=15"
else
    fail "配置解析" "数值解析异常: $SCORE_DIFF_THRESHOLD"
fi

# 验证别名规范化至严格布尔值 (Phase A 2.3)
cat > "$CONFIG_FILE" << 'EOF'
AUTO_UPDATE_SCRIPT="disabled"
EOF
load_config
[[ "$AUTO_UPDATE_SCRIPT" == "false" ]] && pass "AUTO_UPDATE_SCRIPT=disabled 规范化为 false" || fail "别名规范化" "disabled 解析失败: $AUTO_UPDATE_SCRIPT"

cat > "$CONFIG_FILE" << 'EOF'
AUTO_UPDATE_SCRIPT="off"
EOF
load_config
[[ "$AUTO_UPDATE_SCRIPT" == "false" ]] && pass "AUTO_UPDATE_SCRIPT=off 规范化为 false" || fail "别名规范化" "off 解析失败: $AUTO_UPDATE_SCRIPT"

cat > "$CONFIG_FILE" << 'EOF'
AUTO_UPDATE_SCRIPT="enable"
EOF
load_config
[[ "$AUTO_UPDATE_SCRIPT" == "true" ]] && pass "AUTO_UPDATE_SCRIPT=enable 规范化为 true" || fail "别名规范化" "enable 解析失败: $AUTO_UPDATE_SCRIPT"

# 规范值优先于旧版值
cat > "$CONFIG_FILE" << 'EOF'
AUTO_UPDATE_SCRIPT="true"
AUTO_UPDATE="false"
EOF
load_config
[[ "$AUTO_UPDATE_SCRIPT" == "true" ]] && pass "AUTO_UPDATE_SCRIPT 优先于 legacy AUTO_UPDATE" || fail "别名优先级" "预期 true 实际: $AUTO_UPDATE_SCRIPT"

# save_config 仅持久化标准 true/false
cat > "$CONFIG_FILE" << 'EOF'
AUTO_UPDATE_SCRIPT="disabled"
EOF
load_config
save_config
saved_val=$(grep '^AUTO_UPDATE_SCRIPT=' "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')
[[ "$saved_val" == "false" ]] && pass "save_config 仅持久化规范布尔值 false" || fail "配置回写规范化" "预期 false 实际: $saved_val"

# 验证 normalize_score 解析与四舍五入 (Phase B 3.3)
eval "$(sed -n '/^normalize_score()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
[[ "$(normalize_score "47")" == "47" ]] && pass "normalize_score 正常解析整数: 47 -> 47" || fail "normalize_score" "整数解析异常"
[[ "$(normalize_score "1.56")" == "2" ]] && pass "normalize_score 正常解析并四舍五入纯小数: 1.56 -> 2" || fail "normalize_score" "纯小数解析异常"
[[ "$(normalize_score "1.56%")" == "2" ]] && pass "normalize_score 正常解析并四舍五入百分比: 1.56% -> 2" || fail "normalize_score" "百分比解析异常"
[[ "$(normalize_score "0.12%")" == "0" ]] && pass "normalize_score 正常解析小数百分比: 0.12% -> 0" || fail "normalize_score" "小数百分比解析异常"
[[ "$(normalize_score "invalid_text")" == "" ]] && pass "normalize_score 正常静默丢弃非法文本" || fail "normalize_score" "非法文本未静默丢弃"

# 验证 CLI auto-update 相关选项语义 (Phase D 5.5)
auto_status_out=$(bash "$REPO_ROOT/ipqa.sh" --auto-update 2>&1 || true)
if [[ "$auto_status_out" =~ "当前脚本自动更新状态" ]]; then
    pass "ipqa --auto-update 仅报告状态信息"
else
    fail "CLI --auto-update" "未能输出状态信息: $auto_status_out"
fi

if ! bash "$REPO_ROOT/ipqa.sh" --auto-update enable >/dev/null 2>&1; then
    pass "ipqa --auto-update 携带额外参数时被正确拦截并退出非 0"
else
    fail "CLI --auto-update" "携带多余参数未报错"
fi

bash "$REPO_ROOT/ipqa.sh" --enable-auto-update >/dev/null 2>&1 || true
saved_en=$(grep '^AUTO_UPDATE_SCRIPT=' "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
[[ "$saved_en" == "true" ]] && pass "ipqa --enable-auto-update 成功持久化配置为 true" || fail "CLI --enable-auto-update" "配置未持久化为 true: $saved_en"

bash "$REPO_ROOT/ipqa.sh" --disable-auto-update >/dev/null 2>&1 || true
saved_dis=$(grep '^AUTO_UPDATE_SCRIPT=' "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
[[ "$saved_dis" == "false" ]] && pass "ipqa --disable-auto-update 成功持久化配置为 false" || fail "CLI --disable-auto-update" "配置未持久化为 false: $saved_dis"

bash "$REPO_ROOT/ipqa.sh" --enable-auto-update >/dev/null 2>&1 || true
if ! bash "$REPO_ROOT/ipqa.sh" --no-auto-update >/dev/null 2>&1; then
    saved_after_no=$(grep '^AUTO_UPDATE_SCRIPT=' "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    if [[ "$saved_after_no" == "true" ]]; then
        pass "单独执行 ipqa --no-auto-update 被拦截且未静默持久化修改配置"
    else
        fail "CLI --no-auto-update" "单独执行虽报错但配置被篡改: $saved_after_no"
    fi
else
    fail "CLI --no-auto-update" "单独执行未被拦截报错"
fi

# 5. 时间范围过滤与关键帧自适应降采样测试 (N-02, N-03, S-03)
echo -e "\n[测试组 5] 时间范围过滤与关键帧采样测试 (N-02, N-03):"
SAMPLE_DIR="$TEST_ENV_DIR/sample_archives"
mkdir -p "$SAMPLE_DIR"

eval "$(sed -n '/^validate_json()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
eval "$(sed -n '/^load_archive_files()/,/^}/p' "$REPO_ROOT/ipqa.sh")"

# 创建测试数据：5 天前旧文件与 1 小时前新文件
old_ts=$(date -d "5 days ago" +%Y-%m-%d_%H%M%S 2>/dev/null || echo "2026-09-01_120000")
new_ts=$(date -d "1 hour ago" +%Y-%m-%d_%H%M%S 2>/dev/null || echo "2026-09-25_110000")

echo '{"Head":{"IP":"1.1.1.1"},"Type":"isp","Score":10,"Factor":{},"Media":{},"Mail":{"Port25":"Yes","DNSBlacklist":{"Blacklisted":0}}}' > "$SAMPLE_DIR/${old_ts}.json"
echo '{"Head":{"IP":"1.1.1.1"},"Type":"isp","Score":20,"Factor":{},"Media":{},"Mail":{"Port25":"Yes","DNSBlacklist":{"Blacklisted":0}}}' > "$SAMPLE_DIR/${new_ts}.json"

# 测试 24 小时过滤 (range_type=1)
mapfile -t files_24h < <(load_archive_files "$SAMPLE_DIR" 1 10)
if [[ ${#files_24h[@]} -eq 1 && "${files_24h[0]}" == *"${new_ts}.json"* ]]; then
    pass "load_archive_files 正确完成 24h 时间范围过滤并排除历史文件 (N-02)"
else
    fail "时间范围过滤" "预期仅匹配最新文件，实际结果数: ${#files_24h[@]}"
fi

# 测试关键帧自适应降采样 (N-03: 当变动点数超过 max_points 时不丢失中间点)
SAMPLING_DIR="$TEST_ENV_DIR/sampling_test"
mkdir -p "$SAMPLING_DIR"
for ((i=1; i<=10; i++)); do
    f_date=$(printf "2026-09-%02d_120000" "$i")
    echo "{\"Head\":{\"IP\":\"1.1.1.1\"},\"Type\":\"t$i\",\"Score\":$((i*10)),\"Factor\":{},\"Media\":{},\"Mail\":{\"Port25\":\"Yes\",\"DNSBlacklist\":{\"Blacklisted\":$i}}}" > "$SAMPLING_DIR/${f_date}.json"
done

mapfile -t sampled_res < <(load_archive_files "$SAMPLING_DIR" 5 5)
if [[ ${#sampled_res[@]} -eq 5 ]]; then
    pass "关键帧变动点超过上限时成功降采样至预期 5 个槽位 (N-03)"
else
    fail "关键帧降采样" "预期返回 5 个采样点，实际返回 ${#sampled_res[@]} 个"
fi

# 测试 >250 份历史文件场景下的降采样与突变点保留 (Phase A 2.1)
LARGE_SAMPLING_DIR="$TEST_ENV_DIR/sampling_large_260"
mkdir -p "$LARGE_SAMPLING_DIR"
base_payload='{"Head":{"IP":"1.1.1.1"},"Type":"isp","Score":10,"Factor":{},"Media":{},"Mail":{"Port25":"Yes","DNSBlacklist":{"Blacklisted":0}}}'
changed_payload='{"Head":{"IP":"1.1.1.1"},"Type":"hosting","Score":90,"Factor":{},"Media":{},"Mail":{"Port25":"No","DNSBlacklist":{"Blacklisted":5}}}'

for ((i=1; i<=260; i++)); do
    f_date=$(printf "2026-08-01_%06d" "$i")
    if [[ $i -eq 130 ]]; then
        echo "$changed_payload" > "$LARGE_SAMPLING_DIR/${f_date}.json"
    else
        echo "$base_payload" > "$LARGE_SAMPLING_DIR/${f_date}.json"
    fi
done

mapfile -t large_res < <(load_archive_files "$LARGE_SAMPLING_DIR" 5 8)
first_file=$(basename "${large_res[0]}")
last_file=$(basename "${large_res[-1]}")
has_changed_point=false
for lf in "${large_res[@]}"; do
    [[ "$lf" == *"000130.json" ]] && has_changed_point=true
done

if [[ ${#large_res[@]} -eq 8 && "$first_file" == *"000001.json" && "$last_file" == *"000260.json" && "$has_changed_point" == "true" ]]; then
    pass "超过 250 份历史文件正常完成降采样并保留首尾与关键变化点 (Phase A 2.1)"
else
    fail "超量历史降采样" "预期 8 个点且包含首尾及 130 突变点，实际总数: ${#large_res[@]}, 首: $first_file, 尾: $last_file, 包含突变点: $has_changed_point"
fi

# 6. Cron 正则与路径转义测试 (N-01, M-19, M-20, UI-01)
echo -e "\n[测试组 6] Cron 规则识别、转义与半小时时区换算 (N-01, M-19, M-20, UI-01):"
cron_cmd_quoted='"../ipqa" --cron'
cron_cmd_unquoted='../ipqa.sh --cron'
cron_regex='ipqa(\.sh)?["'\''[:space:]]+--cron'

if [[ "$cron_cmd_quoted" =~ $cron_regex ]] && [[ "$cron_cmd_unquoted" =~ $cron_regex ]]; then
    pass "Cron 正则成功同时兼容带引号与不带引号的执行指令 (N-01)"
else
    fail "Cron 正则匹配" "未能正确匹配引号规则"
fi

eval "$(sed -n '/^get_beijing_4am_local_hour()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
eval "$(sed -n '/^get_beijing_00_local_minute()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
eval "$(sed -n '/^get_cron_friendly_name()/,/^}/p' "$REPO_ROOT/ipqa.sh")"

# 验证友好名称解析 (UI-01)
dyn_cron='30 * * * * [ "$(TZ='\''Asia/Shanghai'\'' date +\%H:\%M)" = "04:00" ] && "/usr/local/bin/ipqa" --cron'
friendly=$(get_cron_friendly_name "$dyn_cron")
if [[ "$friendly" == *"北京 04:00"* ]]; then
    pass "正确识别动态北京时间 Cron 规则的友好描述 (UI-01): '$friendly'"
else
    fail "Cron 友好描述" "未能识别动态规则: $friendly"
fi

# 验证三种官方预设的真实 Cron 规则友好名称识别 (Phase A 2.2)
preset_daily='00 * * * * [ "$(TZ='\''Asia/Shanghai'\'' date +\%H:\%M)" = "04:00" ] && "/usr/local/bin/ipqa" --cron >> "/root/.ipqa/logs/ipqa.log" 2>&1'
preset_3day='00 * * * * [ "$(TZ='\''Asia/Shanghai'\'' date +\%H:\%M)" = "04:00" ] && [ $(( ($(date +\%s) / 86400) \% 3 )) -eq 0 ] && "/usr/local/bin/ipqa" --cron >> "/root/.ipqa/logs/ipqa.log" 2>&1'
preset_weekly='00 * * * * [ "$(TZ='\''Asia/Shanghai'\'' date +\%H:\%M)" = "04:00" ] && [ "$(TZ='\''Asia/Shanghai'\'' date +\%u)" = "7" ] && "/usr/local/bin/ipqa" --cron >> "/root/.ipqa/logs/ipqa.log" 2>&1'

name_daily=$(get_cron_friendly_name "$preset_daily")
name_3day=$(get_cron_friendly_name "$preset_3day")
name_weekly=$(get_cron_friendly_name "$preset_weekly")

[[ "$name_daily" == "每天 (北京 04:00)" ]] && pass "正确识别预设 [1] 每天规则: '$name_daily'" || fail "Cron预设名称" "每天规则解析失败: $name_daily"
[[ "$name_3day" == "每 3 天一次 (北京 04:00)" ]] && pass "正确识别预设 [2] 每 3 天规则: '$name_3day'" || fail "Cron预设名称" "每3天规则解析失败: $name_3day"
[[ "$name_weekly" == "每 7 天一次 (北京 04:00)" ]] && pass "正确识别预设 [3] 每 7 天规则: '$name_weekly'" || fail "Cron预设名称" "每7天规则解析失败: $name_weekly"

# 验证不同时区下北京时间到本地分钟换算 (Phase H 9.1)
for tz_test in "UTC" "Asia/Shanghai" "Asia/Kolkata" "Asia/Kathmandu" "IST-5:30" "NPT-5:45" "NST3:30"; do
    calc_min=$(TZ="$tz_test" get_beijing_00_local_minute)
    if [[ ! "$calc_min" =~ ^[0-5][0-9]$ ]]; then
        fail "分钟换算" "时区 $tz_test 下换算分钟超出有效区间 [00-59]: $calc_min"
    fi
done

min_half=$(TZ="IST-5:30" get_beijing_00_local_minute)
min_45=$(TZ="NPT-5:45" get_beijing_00_local_minute)
min_neg_half=$(TZ="NST3:30" get_beijing_00_local_minute)
min_utc=$(TZ="UTC" get_beijing_00_local_minute)

if [[ "$min_utc" == "00" && "$min_half" == "30" && "$min_45" == "45" && "$min_neg_half" == "30" ]]; then
    pass "get_beijing_00_local_minute 在整点、+30m、+45m、-30m 时区下均能精确计算分钟且处于 00-59 (Phase H 9.1)"
else
    fail "分钟换算" "非整小时换算异常: UTC=$min_utc, IST-5:30=$min_half, NPT-5:45=$min_45, NST3:30=$min_neg_half"
fi

# 验证 crontab 过滤逻辑严格剔除 IPQA 标记与所有格式的 IPQA 定时命令，并保留非相关项 (Phase F 7.4)
eval "$(sed -n '/^get_crontab_without_ipqa()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
synthetic_crontab=$(cat << 'EOF'
0 2 * * * /usr/bin/backup-data.sh >> /var/log/backup.log 2>&1
# IPQA AUTO CHECK
00 * * * * [ "$(TZ='Asia/Shanghai' date +\%H:\%M)" = "04:00" ] && "/usr/local/bin/ipqa" --cron >> "/root/.ipqa/logs/ipqa.log" 2>&1
30 4 * * * /opt/ipqa/ipqa.sh --cron
15 3 * * * /usr/bin/certbot renew --quiet
EOF
)

crontab() {
    if [[ "$1" == "-l" ]]; then
        echo "$synthetic_crontab"
        return 0
    fi
    return 1
}

filtered_cron=$(get_crontab_without_ipqa)
unset -f crontab

if [[ "$filtered_cron" == *"backup-data.sh"* && "$filtered_cron" == *"certbot renew"* && ! "$filtered_cron" =~ "ipqa" && ! "$filtered_cron" =~ "IPQA AUTO CHECK" ]]; then
    pass "get_crontab_without_ipqa 成功彻底过滤 IPQA 标记与带引号/无引号 Cron 命令，且保留无关定时任务 (Phase F 7.4)"
else
    fail "Crontab过滤" "过滤残留或误删正常定时任务: $filtered_cron"
fi

# 7. 生产日志脱敏与终端控制符过滤测试 (S-17)
echo -e "\n[测试组 7] 终端控制字符彻底脱敏测试 (S-17):"
ALERT_LOG="$IPQA_DIR/alerts.log"
# shellcheck disable=SC2034 # 供 eval 载入的 log_msg 及 rotate_logs_if_needed 动态使用
LOG_FILE="$IPQA_DIR/ipqa.log"
eval "$(sed -n '/^log_msg()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
eval "$(sed -n '/^rotate_logs_if_needed()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
eval "$(sed -n '/^add_alert()/,/^}/p' "$REPO_ROOT/ipqa.sh")"

test_payload=$(printf "Test\x1b]0;TitleHack\x07\x1b[2J\x1b[31;1mCRITICAL|INJECT\nNEXTLINE")
add_alert "CRITICAL" "$test_payload" "IPv4"

logged_alert=$(cat "$ALERT_LOG" 2>/dev/null || echo "")
if [[ ! "$logged_alert" =~ TitleHack && ! "$logged_alert" =~ $'\x1b' && ! "$logged_alert" =~ $'\n' ]]; then
    pass "add_alert 彻底剔除 OSC/CSI 终端序列与控制符注入 (S-17)"
else
    fail "日志脱敏" "检测到残留控制字符: '$logged_alert'"
fi

# 8. 生产原子互斥锁与 Stale-Lock 恢复测试 (M-08A, M-08B)
echo -e "\n[测试组 8] 生产原子互斥锁、Stale-Lock 恢复与跨进程互斥 (M-08A, M-08B):"
eval "$(sed -n '/^get_current_pid()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
eval "$(sed -n '/^acquire_lock()/,/^}/p' "$REPO_ROOT/ipqa.sh")"
eval "$(sed -n '/^release_lock()/,/^}/p' "$REPO_ROOT/ipqa.sh")"

if acquire_lock "test_mutex"; then
    pass "成功获取主原子锁"
else
    fail "原子锁" "未能获取空闲锁"
fi

# 测试可重入嵌套深度
if acquire_lock "test_mutex"; then
    pass "支持同一进程可重入嵌套加锁 (深度加深)"
else
    fail "原子锁" "可重入加锁失败"
fi

release_lock "test_mutex"
# 此时深度应仍为 1，锁目录仍应存在
if [[ -d "$IPQA_DIR/.lock_test_mutex" ]]; then
    pass "内层解锁保留外层锁状态"
else
    fail "原子锁" "内层解锁错误移除了外层锁目录"
fi

release_lock "test_mutex"
if [[ ! -d "$IPQA_DIR/.lock_test_mutex" ]]; then
    pass "外层解锁彻底释放锁目录"
else
    fail "原子锁" "外层解锁未释放锁目录"
fi

# 测试 Stale-Lock 恢复
mkdir -p "$IPQA_DIR/.lock_test_mutex"
echo "999999" > "$IPQA_DIR/.lock_test_mutex/pid" # 假设一个已不存在的 PID
if acquire_lock "test_mutex"; then
    pass "检测到失效 PID 时成功原子竞争并夺取 Stale 锁 (M-08B)"
    release_lock "test_mutex"
else
    fail "Stale 锁恢复" "未能恢复死亡进程的锁"
fi

# 多进程真实锁竞争测试 (子进程 A 持锁，子进程 B 竞争必须失败，A 释放后 B 成功)
LOCK_TEST_DIR="$TEST_ENV_DIR/lock_race_test"
mkdir -p "$LOCK_TEST_DIR"
(
    export IPQA_HOME="$LOCK_TEST_DIR"
    acquire_lock "main"
    sleep 1
    release_lock "main"
) &
PID_A=$!

# 等待 Process A 成功持锁
for ((try=0; try<20; try++)); do
    [[ -f "$LOCK_TEST_DIR/.lock_main/pid" ]] && break
    sleep 0.05
done

# Process B 尝试加锁 (不同进程，PID 与 BASHPID 均不同)
B_ACQUIRED=0
if (
    export IPQA_HOME="$LOCK_TEST_DIR"
    acquire_lock "main"
) 2>/dev/null; then
    B_ACQUIRED=1
fi

if [[ "$B_ACQUIRED" -eq 0 ]]; then
    pass "Process A 持锁期间，Process B 竞争主锁被成功拦截且未误判为重入"
else
    fail "主锁跨进程互斥" "Process B 在 Process A 持锁期间错误获取了锁"
fi

# 等待 Process A 释放
wait "$PID_A" 2>/dev/null || true

# Process B 再次尝试加锁，此时必须成功
B_SUCCESS_AFTER=0
if (
    export IPQA_HOME="$LOCK_TEST_DIR"
    if acquire_lock "main"; then
        release_lock "main"
        exit 0
    else
        exit 1
    fi
) 2>/dev/null; then
    B_SUCCESS_AFTER=1
fi

if [[ "$B_SUCCESS_AFTER" -eq 1 ]]; then
    pass "Process A 释放主锁后，Process B 成功获得主锁"
else
    fail "主锁释放后竞争" "Process A 释放后 Process B 仍无法获取锁"
fi

# 9. 系统自检指令测试 (Q-03, N-06: 沙箱隔离下运行)
echo -e "\n[测试组 9] 系统环境与自检指令 (--test):"
if bash "$REPO_ROOT/ipqa.sh" --test >/dev/null 2>&1; then
    pass "ipqa --test 在隔离测试环境下成功运行并返回 0 (N-06)"
else
    fail "系统自检" "ipqa --test 返回非 0 状态"
fi

# 10. 无变化语义中性表达测试 (状态不健康时不报良好)
echo -e "\n[测试组 10] 无变化语义中性表达测试 (不健康状态无变化时不误报良好):"
UNHEALTHY_DIR="$TEST_ENV_DIR/unhealthy_archives"
mkdir -p "$UNHEALTHY_DIR"
UNHEALTHY_V4="$UNHEALTHY_DIR/v4"
UNHEALTHY_V6="$UNHEALTHY_DIR/v6"
mkdir -p "$UNHEALTHY_V4" "$UNHEALTHY_V6"

d1="2026-09-24"
d2="2026-09-25"
unhealthy_json='{
    "Head": {"IP": "198.51.100.1"},
    "Type": "DataCenter",
    "Score": 85,
    "Factor": {"VPN": "Yes", "Tor": "Yes"},
    "Media": {"Netflix": {"Status": "Blocked", "Region": "US"}, "Youtube": {"Status": "Blocked", "Region": "US"}},
    "Mail": {"Port25": "No", "DNSBlacklist": {"Blacklisted": 5}}
}'

echo "$unhealthy_json" > "$UNHEALTHY_V4/${d1}_120000.json"
echo "$unhealthy_json" > "$UNHEALTHY_V4/${d2}_120000.json"

ALERT_LOG="$UNHEALTHY_DIR/alerts.log"
touch "$ALERT_LOG"
# shellcheck disable=SC2034 # 终端颜色变量供 eval 载入的 render_daily_alerts_summary 动态使用
C_RESET="" C_GREEN="" C_GRAY="" C_YELLOW="" C_RED="" C_BOLD=""
eval "$(sed -n '/^render_daily_alerts_summary()/,/^}/p' "$REPO_ROOT/ipqa.sh")"

output_summary=$(
    # shellcheck disable=SC2034 # 目录变量供 eval 载入的 render_daily_alerts_summary 动态使用
    V4_DIR="$UNHEALTHY_V4"
    # shellcheck disable=SC2034
    V6_DIR="$UNHEALTHY_V6"
    render_daily_alerts_summary 1 2>/dev/null || true
)

if [[ "$output_summary" =~ (无|未发现) ]] && [[ ! "$output_summary" =~ (良好|稳定良好|一切正常) ]]; then
    pass "不健康但无变化时，摘要输出中性描述且不包含'良好'/'稳定良好'/'一切正常'"
else
    fail "无变化语义中性化" "检测到不合时宜的正面评语: '$output_summary'"
fi

# 11. 检测核心 candidate 校验、Patch 与替换保护测试
echo -e "\n[测试组 11] 检测核心 candidate 校验、Patch 与替换保护测试:"
PATCH_TEST_DIR="$TEST_ENV_DIR/patch_test"
mkdir -p "$PATCH_TEST_DIR"
FORMAL_CORE="$PATCH_TEST_DIR/ip.sh"
echo '#!/usr/bin/env bash' > "$FORMAL_CORE"
echo '# Original formal core' >> "$FORMAL_CORE"
echo 'echo "formal core ok"' >> "$FORMAL_CORE"
chmod 755 "$FORMAL_CORE"

eval "$(sed -n '/^patch_ip_script()/,/^}/p' "$REPO_ROOT/ipqa.sh")"

# 1. 正常 candidate (含待修补的 YouTube ANSI 污染): patch 前合法，patch 成功后语法仍合法 -> 成功原子替换
CANDIDATE_VALID="$PATCH_TEST_DIR/candidate_valid.sh"
cat > "$CANDIDATE_VALID" << 'EOF'
#!/usr/bin/env bash
# script_version="2.0"
# IPQuality Check_DNS
youtube[uregion]="  $Font_Red[CN]$Font_Green   "
echo "core logic"
EOF

if bash -n "$CANDIDATE_VALID" && patch_ip_script "$CANDIDATE_VALID" && bash -n "$CANDIDATE_VALID" && grep -q 'youtube\[uregion\]="  \[CN\]   "' "$CANDIDATE_VALID" && ! grep -q 'Font_Red' "$CANDIDATE_VALID"; then
    mv -f "$CANDIDATE_VALID" "$FORMAL_CORE"
    pass "有效 candidate 成功应用 YouTube patch 并通过后验 bash -n，成功原子替换正式核心"
else
    fail "Core Patch" "合法 candidate patch 或验证失败"
fi

# 2. 异常 candidate: 语法错误 candidate 在替换前被校验拦截 -> 不得覆盖正式核心 (Phase H 9.2)
CANDIDATE_BROKEN="$PATCH_TEST_DIR/candidate_broken.sh"
cat > "$CANDIDATE_BROKEN" << 'EOF'
#!/usr/bin/env bash
# script_version="2.1"
# IPQuality Check_DNS
youtube[uregion]="  $Font_Red[CN]$Font_Green   "
if [[ broken syntax unbalanced
EOF

candidate_replaced=false
if bash -n "$CANDIDATE_BROKEN" 2>/dev/null && patch_ip_script "$CANDIDATE_BROKEN" 2>/dev/null && bash -n "$CANDIDATE_BROKEN" 2>/dev/null; then
    mv -f "$CANDIDATE_BROKEN" "$FORMAL_CORE"
    candidate_replaced=true
else
    rm -f "$CANDIDATE_BROKEN"
fi

if [[ "$candidate_replaced" == "false" ]] && grep -q 'youtube\[uregion\]="  \[CN\]   "' "$FORMAL_CORE"; then
    pass "语法错误 candidate 校验失败并在替换前被拦截，正式核心完整保留不受污染"
else
    fail "Core Patch 防御" "语法错误 candidate 未被拦截或正式核心被污染"
fi

# 12. Debian/Ubuntu-only 系统支持与未知发行版拒绝测试
echo -e "\n[测试组 12] Debian/Ubuntu-only 系统支持与未知发行版拒绝测试:"
eval "$(sed -n '/^check_os_support()/,/^}/p' "$REPO_ROOT/install.sh")"

OS_RELEASE_DEBIAN="$TEST_ENV_DIR/os_release_debian"
echo 'ID=debian' > "$OS_RELEASE_DEBIAN"
if IPQA_OS_RELEASE_FILE="$OS_RELEASE_DEBIAN" check_os_support >/dev/null 2>&1; then
    pass "成功放行 Debian 系统"
else
    fail "系统支持" "Debian 被误拦截"
fi

OS_RELEASE_UBUNTU="$TEST_ENV_DIR/os_release_ubuntu"
echo 'ID=ubuntu' > "$OS_RELEASE_UBUNTU"
if IPQA_OS_RELEASE_FILE="$OS_RELEASE_UBUNTU" check_os_support >/dev/null 2>&1; then
    pass "成功放行 Ubuntu 系统"
else
    fail "系统支持" "Ubuntu 被误拦截"
fi

OS_RELEASE_ALPINE="$TEST_ENV_DIR/os_release_alpine"
echo 'ID=alpine' > "$OS_RELEASE_ALPINE"
if ! IPQA_OS_RELEASE_FILE="$OS_RELEASE_ALPINE" check_os_support >/dev/null 2>&1; then
    pass "成功拦截 Alpine Linux 并明确退出非 0"
else
    fail "系统支持" "未能拦截 Alpine 系统"
fi

OS_RELEASE_CENTOS="$TEST_ENV_DIR/os_release_centos"
echo 'ID=centos' > "$OS_RELEASE_CENTOS"
if ! IPQA_OS_RELEASE_FILE="$OS_RELEASE_CENTOS" check_os_support >/dev/null 2>&1; then
    pass "成功拦截 CentOS/RHEL 系统并明确退出非 0"
else
    fail "系统支持" "未能拦截 CentOS 系统"
fi

# 检查代码库是否彻底移除 Alpine / apk 相关分支
if ! grep -qiE 'apk add|apk update|command -v apk' "$REPO_ROOT/install.sh" "$REPO_ROOT/ipqa.sh"; then
    pass "代码库已彻底剔除 apk 相关包管理器映射与安装分支"
else
    fail "Alpine 代码残留" "在生产代码中仍检测到 apk 相关逻辑"
fi

echo -e "\n=============================================================================="
echo "测试结果汇总: 总计 $TESTS_RUN 项测试, 通过: $TESTS_PASSED, 失败: $TESTS_FAILED"
echo "=============================================================================="

if [[ "$TESTS_FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
