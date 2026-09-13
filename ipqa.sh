#!/usr/bin/env bash
# ==============================================================================
# IP Quality Archive (IPQA) - IP 质量存档监测系统
# Description: 基于 IPQuality 的 IP 质量历史存档与终端可视化监测工具
# GitHub: https://github.com/xykt/IPQuality
# ==============================================================================

# 基础环境与路径配置
IPQA_HOME="${IPQA_DIR:-$HOME/.ipqa}"
CONFIG_FILE="$IPQA_HOME/config.sh"
DATA_DIR="$IPQA_HOME/data"
V4_DIR="$DATA_DIR/v4"
V6_DIR="$DATA_DIR/v6"
LOGS_DIR="$IPQA_HOME/logs"
ALERT_LOG="$DATA_DIR/alerts.log"
IP_SCRIPT="$IPQA_HOME/ip.sh"
LOG_FILE="$LOGS_DIR/ipqa.log"

# 创建运行目录
mkdir -p "$V4_DIR" "$V6_DIR" "$LOGS_DIR"

# ANSI 颜色与文字样式定义
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_UNDERLINE="\033[4m"

C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_MAGENTA="\033[35m"
C_CYAN="\033[36m"
C_WHITE="\033[37m"
C_GRAY="\033[90m"
C_ORANGE="\033[38;5;208m"

BG_RED="\033[41m"
BG_GREEN="\033[42m"
BG_YELLOW="\033[43m"
BG_BLUE="\033[44m"
BG_CYAN="\033[46m"

# 符号定义
SYM_DOT_GREEN="${C_GREEN}●${C_RESET}"
SYM_DOT_ORANGE="${C_ORANGE}●${C_RESET}"
SYM_DOT_YELLOW="${C_YELLOW}●${C_RESET}"
SYM_DOT_RED="${C_RED}●${C_RESET}"
SYM_DOT_GRAY="${C_GRAY}○${C_RESET}"
SYM_MARK_RED="${C_RED}◉${C_RESET}"
SYM_CHECK="${C_GREEN}✓${C_RESET}"
SYM_CROSS="${C_RED}✗${C_RESET}"
SYM_WARN="${C_YELLOW}⚠️${C_RESET}"

draw_divider() {
    local len="${1:-60}"
    local line
    line=$(printf '─%.0s' $(seq 1 "$len" 2>/dev/null) 2>/dev/null)
    if [[ -z "$line" ]]; then
        for ((d_i=0; d_i<len; d_i++)); do line+="─"; done
    fi
    echo -e "${C_GRAY}${line}${C_RESET}"
}

count_json_files() {
    local dir="$1"
    [[ -d "$dir" ]] || { echo 0; return; }
    find "$dir" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l
}

print_module_header() {
    local title="$1"
    echo -e "${C_CYAN}${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_BOLD}${title}${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}\n"
}

# ==============================================================================
# 配置管理
# ==============================================================================
load_config() {
    # 默认值
    CHECK_INTERVAL_HOURS=24
    HAS_V6="auto"
    V6_CHECK_COUNT=0
    V6_PROBE_INTERVAL=10
    SCORE_DIFF_THRESHOLD=10
    EXPECTED_YOUTUBE_REGION=""
    EXPECTED_NETFLIX_REGION=""
    KEEP_MAX_ARCHIVES=0

    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    else
        save_config
    fi
}

save_config() {
    cat <<EOF > "$CONFIG_FILE"
# IPQA Configuration
CHECK_INTERVAL_HOURS=${CHECK_INTERVAL_HOURS:-24}
HAS_V6="${HAS_V6:-auto}"
V6_CHECK_COUNT=${V6_CHECK_COUNT:-0}
V6_PROBE_INTERVAL=${V6_PROBE_INTERVAL:-10}
SCORE_DIFF_THRESHOLD=${SCORE_DIFF_THRESHOLD:-10}
EXPECTED_YOUTUBE_REGION="${EXPECTED_YOUTUBE_REGION:-}"
EXPECTED_NETFLIX_REGION="${EXPECTED_NETFLIX_REGION:-}"
KEEP_MAX_ARCHIVES=${KEEP_MAX_ARCHIVES:-0}
EOF
}

# ==============================================================================
# 工具函数
# ==============================================================================
pad_cell() {
    local text="$1"
    local target_width="${2:-8}"
    local w
    w=$(printf "%s" "$text" | wc -L)
    local pad=$(( target_width - w ))
    [[ $pad -lt 0 ]] && pad=0
    printf "%s%*s" "$text" "$pad" ""
}

fmt_type_badge() {
    local val="$1"
    local col_width="$2"
    if [[ -z "$val" || "$val" == "null" || "$val" == "--" ]]; then
        printf "%-${col_width}s" ""
        return
    fi
    local bg="$BG_YELLOW"
    if [[ "$val" =~ (机房|Hosting|Data Center|CDN|Transit) ]]; then
        bg="$BG_RED"
    elif [[ "$val" =~ (家宽|ISP|原生|Mobile|手机) ]]; then
        bg="$BG_GREEN"
    fi
    local badge="${bg}${C_WHITE} ${val} ${C_RESET}"
    local val_len
    val_len=$(printf "%s" "$val" | wc -L)
    local total_len=$(( val_len + 2 ))
    local pad=$(( col_width - total_len ))
    (( pad < 1 )) && pad=1
    local spaces=""
    for (( s=0; s<pad; s++ )); do spaces+=" "; done
    echo -ne "${badge}${spaces}"
}


# 自动计算服务器当前时区下对应“北京时间凌晨 04:00”的小时数 (0-23)
get_beijing_4am_local_hour() {
    local h
    h=$(date -d 'TZ="Asia/Shanghai" 04:00' +%H 2>/dev/null | sed 's/^0//')
    if [[ -z "$h" || ! "$h" =~ ^[0-9]+$ ]]; then
        local z
        z=$(date +%z)
        local sign="${z:0:1}"
        local zh="${z:1:2}"
        local zm="${z:3:2}"
        local local_offset_sec=$(( (10#$zh * 3600) + (10#$zm * 60) ))
        [[ "$sign" == "-" ]] && local_offset_sec=$(( -local_offset_sec ))
        local local_sec=$(( -14400 + local_offset_sec ))
        local mod_sec=$(( local_sec % 86400 ))
        (( mod_sec < 0 )) && mod_sec=$(( mod_sec + 86400 ))
        h=$(( mod_sec / 3600 ))
    fi
    echo "$h"
}

log_msg() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$ts] [$level] $msg" >> "$LOG_FILE"
}

check_dependencies() {
    local missing=()
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${C_RED}错误: 缺少必要依赖: ${missing[*]}${C_RESET}"
        echo -e "请先安装: ${C_YELLOW}apt install -y ${missing[*]}${C_RESET} 或 ${C_YELLOW}yum install -y ${missing[*]}${C_RESET}"
        exit 1
    fi
}

patch_ip_script() {
    [[ ! -f "$IP_SCRIPT" ]] && return

    # 1. 修复上游 ip.sh 未将 IP2Location 公司类型写入 JSON 的 bug
    if ! grep -q 'Company: { IP2LOCATION' "$IP_SCRIPT" 2>/dev/null; then
        sed -i '/Company: { ipapi:/a \type_updates+=".Type |= . * { Company: { IP2LOCATION: \\"$(clean_ansi "${ip2location[scomtype]:-null}")\\" } } | "' "$IP_SCRIPT" 2>/dev/null || true
    fi

    # 2. 修复上游 ip.sh 在 Check_DNS_3 中因缺少 dig 或超时将原生解锁误判为 DNS 解锁的 bug
    if grep -q 'if \[ "$resultdnstext" == "0" \];then' "$IP_SCRIPT" 2>/dev/null; then
        sed -i 's/if \[ "$resultdnstext" == "0" \];then/if [ "$resultdnstext" == "0" ] || [ -z "$resultdnstext" ];then/g' "$IP_SCRIPT" 2>/dev/null || true
    fi

    # 3. 修复上游 ip.sh 在 Check_DNS_IP 中因未解析到 IP 将原生解锁误判为 DNS 解锁的 bug
    sed -i -e '/function Check_DNS_IP/,/function Check_DNS_1/{ /else/{ n; s/echo 0/echo 1/; } }' "$IP_SCRIPT" 2>/dev/null || true

    # 4. 修复上游 ip.sh 中 Youtube 地区硬编码内嵌 Font_Red/Font_Green 导致 JSON 存储 1mCN2m 等 ANSI 残渣的 bug
    sed -i 's/youtube\[uregion\]="  \$Font_Red\[CN\]\$Font_Green   "/youtube[uregion]="  [CN]   "/g' "$IP_SCRIPT" 2>/dev/null || true
}

ensure_ip_script() {
    if [[ ! -f "$IP_SCRIPT" ]]; then
        echo -e "${C_CYAN}正在初始化并下载 IPQuality 上游脚本缓存...${C_RESET}"
        # 优先检查本地同仓库是否有源码
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -f "$script_dir/ip.sh" ]]; then
            cp "$script_dir/ip.sh" "$IP_SCRIPT"
        elif [[ -f "$script_dir/IP-Quality-Detection-Project/ip.sh" ]]; then
            cp "$script_dir/IP-Quality-Detection-Project/ip.sh" "$IP_SCRIPT"
        else
            curl -sL https://IP.Check.Place -o "$IP_SCRIPT" || curl -sL https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh -o "$IP_SCRIPT"
        fi
        sed -i 's/\r$//' "$IP_SCRIPT" 2>/dev/null || true
        chmod +x "$IP_SCRIPT"
        patch_ip_script
    else
        patch_ip_script
    fi
    if [[ ! -f "$IP_SCRIPT" ]]; then
        echo -e "${C_RED}错误: 无法获取 IPQuality 脚本缓存 ($IP_SCRIPT)${C_RESET}"
        return 1
    fi
    return 0
}

# 每天自动静默更新 IPQA 脚本及 IPQuality 检测核心 (静默执行)
auto_update_if_needed() {
    local quiet="${1:-true}"
    local stamp_file="$IPQA_HOME/.last_auto_update"
    if [[ ! -f "$stamp_file" && -f "$IPQA_HOME/.last_core_update" ]]; then
        mv "$IPQA_HOME/.last_core_update" "$stamp_file" 2>/dev/null || true
    fi

    local now_sec
    now_sec=$(date +%s)
    local last_update=0
    [[ -f "$stamp_file" ]] && last_update=$(cat "$stamp_file" 2>/dev/null || echo 0)

    # 上次更新距离现在超过 1 天 (86400 秒) 或核心文件不存在时自动静默更新
    if [[ ! -f "$IP_SCRIPT" ]] || (( now_sec - last_update >= 86400 )); then
        [[ "$quiet" == "false" ]] && echo -e "${C_CYAN}🔄 距上次更新已超 1 天，正在静默更新脚本与检测核心...${C_RESET}"
        log_msg "INFO" "触发 1 天周期自动静默更新脚本与检测核心"

        # 1. 自动同步 IPQuality 检测核心 (ip.sh)
        local tmp_ip="$IPQA_HOME/ip.sh.tmp"
        if curl -sL https://IP.Check.Place -o "$tmp_ip" 2>/dev/null || curl -sL https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh -o "$tmp_ip" 2>/dev/null; then
            mv "$tmp_ip" "$IP_SCRIPT"
            sed -i 's/\r$//' "$IP_SCRIPT" 2>/dev/null || true
            chmod +x "$IP_SCRIPT"
            patch_ip_script
            local new_ver
            new_ver=$(grep -m 1 'script_version=' "$IP_SCRIPT" 2>/dev/null | cut -d '"' -f 2)
            log_msg "INFO" "1天自动更新检测核心成功，版本: ${new_ver:-未知}"
        else
            rm -f "$tmp_ip"
            log_msg "WARN" "1天自动更新检测核心网络超时，继续使用本地核心"
        fi

        # 2. 自动同步 IPQA 脚本 (ipqa.sh)
        local tmp_ipqa="$IPQA_HOME/ipqa.sh.tmp"
        if curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/ipqa.sh -o "$tmp_ipqa" 2>/dev/null; then
            if bash -n "$tmp_ipqa" 2>/dev/null; then
                mv "$tmp_ipqa" "$IPQA_HOME/ipqa.sh"
                sed -i 's/\r$//' "$IPQA_HOME/ipqa.sh" 2>/dev/null || true
                chmod +x "$IPQA_HOME/ipqa.sh"
                log_msg "INFO" "1天自动静默更新 IPQA 脚本成功"
            else
                rm -f "$tmp_ipqa"
                log_msg "WARN" "自动更新 IPQA 脚本语法校验失败，保留当前脚本"
            fi
        else
            rm -f "$tmp_ipqa"
            log_msg "WARN" "自动更新 IPQA 脚本网络超时，继续使用当前脚本"
        fi

        echo "$now_sec" > "$stamp_file"
        [[ "$quiet" == "false" ]] && echo -e "${C_GREEN}✔ IPQA 脚本与检测核心已完成自动静默更新${C_RESET}\n"
    fi
}

# 验证 JSON 有效性
validate_json() {
    local file="$1"
    if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
        return 1
    fi
    jq empty "$file" >/dev/null 2>&1
}

# 获取最新一份有效 JSON
get_latest_archive() {
    local dir="$1"
    [[ ! -d "$dir" ]] && return 1
    local latest
    latest=$(find "$dir" -maxdepth 1 -name '*.json' 2>/dev/null | sort -r | head -n 1)
    if [[ -n "$latest" && -f "$latest" ]]; then
        echo "$latest"
        return 0
    fi
    return 1
}

# 格式化日期显示
fmt_timestamp() {
    local raw="$1" # YYYY-MM-DD_HHMMSS
    if [[ "$raw" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
    else
        echo "$raw"
    fi
}

fmt_short_date() {
    local raw="$1" # YYYY-MM-DD_HHMMSS
    if [[ "$raw" =~ ^[0-9]{4}-([0-9]{2})-([0-9]{2})_([0-9]{2})([0-9]{2}) ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
    else
        echo "$raw"
    fi
}

fmt_short_time() {
    local raw="$1" # YYYY-MM-DD_HHMMSS
    if [[ "$raw" =~ ^[0-9]{4}-([0-9]{2})-([0-9]{2})_([0-9]{2})([0-9]{2}) ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]} ${BASH_REMATCH[3]}:${BASH_REMATCH[4]}"
    else
        echo "$raw"
    fi
}

# 清理地区字符串中的 ANSI 乱码与异常格式 (例如 1mCN2m, \x1b[31m[CN]\x1b[32m 等)
clean_region_str() {
    local raw="$1"
    [[ -z "$raw" || "$raw" == "null" || "$raw" == "--" ]] && echo "--" && return
    local cleaned
    cleaned=$(echo "$raw" | sed -r -e 's/\x1b\[?[0-9;]*m?//g' -e 's/\\033\[?[0-9;]*m?//g' -e 's/[0-9]+m//g')
    if [[ "$cleaned" =~ ([A-Za-z]{2}) ]]; then
        echo "${BASH_REMATCH[1]^^}"
    else
        cleaned=$(echo "$cleaned" | tr -d '[] ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [[ -z "$cleaned" || "$cleaned" == "null" ]] && cleaned="--"
        echo "$cleaned"
    fi
}

# ==============================================================================
# 告警与变化对比引擎
# ==============================================================================
add_alert() {
    local level="$1"
    local msg="$2"
    local ip_ver="$3"
    local now
    now=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$now|$level|$msg|$ip_ver" >> "$ALERT_LOG"
    log_msg "ALERT-$level" "[$ip_ver] $msg"
}

get_recent_alerts() {
    local count="${1:-5}"
    if [[ -f "$ALERT_LOG" ]]; then
        sort -t'|' -k1 "$ALERT_LOG" 2>/dev/null | tail -n "$count"
    fi
}

compare_and_alert() {
    local dir="$1"
    local new_file="$2"
    local ip_ver="$3"

    # 获取前一份有效存档文件（排除当前 new_file）
    local prev_file
    prev_file=$(find "$dir" -maxdepth 1 -name '*.json' 2>/dev/null | sort -r | grep -v "$(basename "$new_file")" | head -n 1)

    if [[ -z "$prev_file" || ! -f "$prev_file" ]]; then
        add_alert "INFO" "首次完成数据存档监测" "$ip_ver"
        return 0
    fi

    # 1. 对比流媒体地区变化 (YouTube, Netflix, TikTok)
    local services=("Youtube" "Netflix" "TikTok")
    for svc in "${services[@]}"; do
        local old_reg new_reg
        old_reg=$(jq -r ".Media.$svc.Region // empty" "$prev_file")
        new_reg=$(jq -r ".Media.$svc.Region // empty" "$new_file")
        old_reg=$(clean_region_str "$old_reg")
        new_reg=$(clean_region_str "$new_reg")
        [[ "$old_reg" == "--" ]] && old_reg=""
        [[ "$new_reg" == "--" ]] && new_reg=""
        if [[ -n "$old_reg" && -n "$new_reg" && "$old_reg" != "$new_reg" ]]; then
            add_alert "WARNING" "$svc 地区从 [$old_reg] 变为 [$new_reg]" "$ip_ver"
        fi
    done

    # 预期地区检查
    if [[ -n "$EXPECTED_YOUTUBE_REGION" ]]; then
        local yt_reg
        yt_reg=$(jq -r ".Media.Youtube.Region // empty" "$new_file")
        yt_reg=$(clean_region_str "$yt_reg")
        [[ "$yt_reg" == "--" ]] && yt_reg=""
        if [[ -n "$yt_reg" && "$yt_reg" != "$EXPECTED_YOUTUBE_REGION" ]]; then
            add_alert "WARNING" "YouTube 地区 [$yt_reg] 不符合预期 [$EXPECTED_YOUTUBE_REGION]" "$ip_ver"
        fi
    fi
    if [[ -n "$EXPECTED_NETFLIX_REGION" ]]; then
        local nf_reg
        nf_reg=$(jq -r ".Media.Netflix.Region // empty" "$new_file")
        nf_reg=$(clean_region_str "$nf_reg")
        [[ "$nf_reg" == "--" ]] && nf_reg=""
        if [[ -n "$nf_reg" && "$nf_reg" != "$EXPECTED_NETFLIX_REGION" ]]; then
            add_alert "WARNING" "Netflix 地区 [$nf_reg] 不符合预期 [$EXPECTED_NETFLIX_REGION]" "$ip_ver"
        fi
    fi

    # 2. 对比流媒体解锁状态
    local all_media=("TikTok" "DisneyPlus" "Netflix" "Youtube" "AmazonPrimeVideo" "Reddit" "ChatGPT")
    for svc in "${all_media[@]}"; do
        local old_status new_status
        old_status=$(jq -r ".Media.$svc.Status // empty" "$prev_file")
        new_status=$(jq -r ".Media.$svc.Status // empty" "$new_file")
        if [[ -n "$old_status" && -n "$new_status" && "$old_status" != "$new_status" ]]; then
            if [[ "$new_status" =~ (失败|屏蔽|No|Failed) || ("$old_status" =~ (解锁|Yes) && "$new_status" =~ 仅自制) ]]; then
                add_alert "CRITICAL" "$svc 解锁状态发生降级: [$old_status] 变为 [$new_status]" "$ip_ver"
            else
                add_alert "INFO" "$svc 解锁状态变化: [$old_status] 变为 [$new_status]" "$ip_ver"
            fi
        fi
    done

    # 3. 对比风险评分上升
    local score_keys=("IP2LOCATION" "SCAMALYTICS" "ipapi" "AbuseIPDB" "IPQS" "DBIP")
    for sk in "${score_keys[@]}"; do
        local old_score new_score
        old_score=$(jq -r ".Score.$sk // empty" "$prev_file")
        new_score=$(jq -r ".Score.$sk // empty" "$new_file")
        old_score=$(normalize_score "$old_score")
        new_score=$(normalize_score "$new_score")
        if [[ "$old_score" =~ ^[0-9]+$ && "$new_score" =~ ^[0-9]+$ ]]; then
            local diff=$((new_score - old_score))
            if (( diff >= SCORE_DIFF_THRESHOLD )); then
                add_alert "WARNING" "$sk 风险评分大幅上升 +$diff ($old_score -> $new_score)" "$ip_ver"
            fi
        fi
    done

    # 4. 对比 IP 类型属性变化
    local old_type new_type
    old_type=$(jq -r ".Info.Type // empty" "$prev_file")
    new_type=$(jq -r ".Info.Type // empty" "$new_file")
    if [[ -n "$old_type" && -n "$new_type" && "$old_type" != "$new_type" ]]; then
        add_alert "CRITICAL" "IP 原生/广播类型发生变化: [$old_type] -> [$new_type]" "$ip_ver"
    fi

    local type_alert_dbs=("IPinfo" "ipregistry" "ipapi" "IP2LOCATION" "AbuseIPDB")
    for tadb in "${type_alert_dbs[@]}"; do
        local old_usage new_usage
        if [[ "$tadb" == "IP2LOCATION" ]]; then
            old_usage=$(jq -r '.Type.Usage.IP2LOCATION // .Type.Usage.IP2Location // empty' "$prev_file" 2>/dev/null)
            new_usage=$(jq -r '.Type.Usage.IP2LOCATION // .Type.Usage.IP2Location // empty' "$new_file" 2>/dev/null)
        else
            old_usage=$(jq -r ".Type.Usage.$tadb // empty" "$prev_file" 2>/dev/null)
            new_usage=$(jq -r ".Type.Usage.$tadb // empty" "$new_file" 2>/dev/null)
        fi
        if [[ -n "$old_usage" && -n "$new_usage" && "$old_usage" != "$new_usage" ]]; then
            add_alert "WARNING" "$tadb 使用类型属性变更为 [$new_usage] (原: $old_usage)" "$ip_ver"
        fi

        if [[ "$tadb" != "AbuseIPDB" ]]; then
            local old_comp new_comp
            if [[ "$tadb" == "IP2LOCATION" ]]; then
                old_comp=$(jq -r '.Type.Company.IP2LOCATION // .Type.Company.IP2Location // empty' "$prev_file" 2>/dev/null)
                new_comp=$(jq -r '.Type.Company.IP2LOCATION // .Type.Company.IP2Location // empty' "$new_file" 2>/dev/null)
            else
                old_comp=$(jq -r ".Type.Company.$tadb // empty" "$prev_file" 2>/dev/null)
                new_comp=$(jq -r ".Type.Company.$tadb // empty" "$new_file" 2>/dev/null)
            fi
            if [[ -n "$old_comp" && -n "$new_comp" && "$old_comp" != "$new_comp" ]]; then
                add_alert "WARNING" "$tadb 公司类型属性变更为 [$new_comp] (原: $old_comp)" "$ip_ver"
            fi
        fi
    done

    # 5. 对比风险因子新增 (Proxy, Tor, VPN, Server, Abuser, Robot)
    local factors=("Proxy" "Tor" "VPN" "Server" "Abuser" "Robot")
    for factor in "${factors[@]}"; do
        local engines=("IP2LOCATION" "ipapi" "ipregistry" "IPQS" "SCAMALYTICS" "ipdata" "IPinfo" "IPWHOIS" "DBIP")
        for eng in "${engines[@]}"; do
            local old_val new_val
            old_val=$(jq -r "if .Factor[\"$factor\"][\"$eng\"] != null then .Factor[\"$factor\"][\"$eng\"] else .Factor[\"$factor\"][\"WHOIS\"] end" "$prev_file")
            new_val=$(jq -r "if .Factor[\"$factor\"][\"$eng\"] != null then .Factor[\"$factor\"][\"$eng\"] else .Factor[\"$factor\"][\"WHOIS\"] end" "$new_file")
            if [[ "$old_val" == "false" && "$new_val" == "true" ]]; then
                add_alert "WARNING" "新增风险标记: $eng 检出 $factor 因子" "$ip_ver"
            fi
        done
    done

    # 6. 对比黑名单增加
    local old_bl new_bl
    old_bl=$(jq -r ".Mail.DNSBlacklist.Blacklisted // empty" "$prev_file")
    new_bl=$(jq -r ".Mail.DNSBlacklist.Blacklisted // empty" "$new_file")
    if [[ "$old_bl" =~ ^[0-9]+$ && "$new_bl" =~ ^[0-9]+$ ]]; then
        if (( new_bl > old_bl )); then
            add_alert "WARNING" "DNS 黑名单拦截数增加 (从 $old_bl 增至 $new_bl)" "$ip_ver"
        fi
    fi
}

# ==============================================================================
# 数据采集核心逻辑
# ==============================================================================
run_check() {
    local quiet="${1:-false}"
    local start_sec
    start_sec=$(date +%s)
    ensure_ip_script || return 1
    auto_update_if_needed "$quiet"
    load_config

    local ts
    ts=$(date +%Y-%m-%d_%H%M%S)
    local v4_out="$V4_DIR/${ts}.json"
    local v6_out="$V6_DIR/${ts}.json"

    [[ "$quiet" == "false" ]] && echo -e "${C_CYAN}▶ [1/2] 开始执行 IPv4 质量检测...${C_RESET}"
    log_msg "INFO" "开始执行 IPv4 检测: $ts"

    # 执行 IPv4 检测并输出 JSON (-y 自动安装, -n 跳过前置依赖检查, -p 隐私模式不外发链接)
    bash "$IP_SCRIPT" -4 -y -n -p -o "$v4_out" >/dev/null 2>&1

    if validate_json "$v4_out"; then
        [[ "$quiet" == "false" ]] && echo -e "${C_GREEN}✔ IPv4 检测完成并已有效存档: $(basename "$v4_out")${C_RESET}"
        log_msg "INFO" "IPv4 检测成功: $v4_out"
        compare_and_alert "$V4_DIR" "$v4_out" "IPv4"
    else
        rm -f "$v4_out"
        [[ "$quiet" == "false" ]] && echo -e "${C_YELLOW}⚠ IPv4 检测未生成有效 JSON (可能网络超时或接口受限)${C_RESET}"
        log_msg "WARN" "IPv4 检测生成数据无效，已自动清理"
    fi

    # 判断是否需要执行 IPv6 检测
    local should_check_v6=false
    if [[ "$HAS_V6" == "auto" || "$HAS_V6" == "true" ]]; then
        should_check_v6=true
    elif [[ "$HAS_V6" == "false" ]]; then
        V6_CHECK_COUNT=$((V6_CHECK_COUNT + 1))
        if (( V6_CHECK_COUNT >= V6_PROBE_INTERVAL )); then
            should_check_v6=true
            V6_CHECK_COUNT=0
            log_msg "INFO" "达到重试周期，重新探测 IPv6 可用性"
        fi
        save_config
    fi

    if [[ "$should_check_v6" == "true" ]]; then
        [[ "$quiet" == "false" ]] && echo -e "${C_CYAN}▶ [2/2] 开始执行 IPv6 质量检测...${C_RESET}"
        log_msg "INFO" "开始执行 IPv6 检测: $ts"
        bash "$IP_SCRIPT" -6 -y -n -p -o "$v6_out" >/dev/null 2>&1

        if validate_json "$v6_out"; then
            local v6_ip
            v6_ip=$(jq -r '.Head.IP // empty' "$v6_out")
            if [[ -n "$v6_ip" && "$v6_ip" != "null" ]]; then
                [[ "$quiet" == "false" ]] && echo -e "${C_GREEN}✔ IPv6 检测完成并已有效存档: $(basename "$v6_out")${C_RESET}"
                log_msg "INFO" "IPv6 检测成功: $v6_out"
                compare_and_alert "$V6_DIR" "$v6_out" "IPv6"
                HAS_V6="true"
                save_config
            else
                rm -f "$v6_out"
                [[ "$quiet" == "false" ]] && echo -e "${C_GRAY}ℹ 未检测到 IPv6 地址，跳过 v6 归档${C_RESET}"
                if [[ "$HAS_V6" == "auto" ]]; then
                    HAS_V6="false"
                    save_config
                fi
            fi
        else
            rm -f "$v6_out"
            [[ "$quiet" == "false" ]] && echo -e "${C_GRAY}ℹ 本机当前不支持 IPv6${C_RESET}"
            if [[ "$HAS_V6" == "auto" ]]; then
                HAS_V6="false"
                save_config
            fi
        fi
    else
        [[ "$quiet" == "false" ]] && echo -e "${C_GRAY}ℹ 根据配置已跳过 IPv6 检测 (HAS_V6=$HAS_V6)${C_RESET}"
    fi

    # 清理超额历史文件
    if [[ "$KEEP_MAX_ARCHIVES" -gt 0 ]]; then
        local count_v4 count_v6
        count_v4=$(count_json_files "$V4_DIR")
        if (( count_v4 > KEEP_MAX_ARCHIVES )); then
            local remove_count=$((count_v4 - KEEP_MAX_ARCHIVES))
            find "$V4_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | sort | head -n "$remove_count" | xargs rm -f 2>/dev/null
        fi
        count_v6=$(count_json_files "$V6_DIR")
        if (( count_v6 > KEEP_MAX_ARCHIVES )); then
            local remove_count=$((count_v6 - KEEP_MAX_ARCHIVES))
            find "$V6_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | sort | head -n "$remove_count" | xargs rm -f 2>/dev/null
        fi
    fi

    local end_sec
    end_sec=$(date +%s)
    local elapsed=$((end_sec - start_sec))
    [[ "$quiet" == "false" ]] && echo -e "${C_GREEN}${C_BOLD}检测完成！${C_RESET}${C_GRAY}(耗时 ${elapsed} 秒)${C_RESET}\n"
}

# ==============================================================================
# 数据加载与时间范围筛选
# ==============================================================================
# 返回符合时间范围的 JSON 文件列表数组 (由旧到新升序)
# 用法: load_archive_files <dir> <range_type> <max_points>
# 输出每行一个文件路径
load_archive_files() {
    local dir="$1"
    local range_type="${2:-2}" # 默认最近7天
    local max_points="${3:-15}"

    if [[ ! -d "$dir" ]]; then
        return 0
    fi

    local all_files
    # 按字典序排序（文件名格式为 YYYY-MM-DD_HHMMSS.json，排序即时间排序）
    mapfile -t all_files < <(ls -1 "$dir"/*.json 2>/dev/null | sort)
    local total=${#all_files[@]}
    if [[ $total -eq 0 ]]; then
        return 0
    fi

    local filtered=()
    local now_sec
    now_sec=$(date +%s)

    local cutoff_sec=0
    case "$range_type" in
        1) cutoff_sec=$((now_sec - 86400)) ;;     # 24 小时
        2) cutoff_sec=$((now_sec - 604800)) ;;    # 7 天
        3) cutoff_sec=$((now_sec - 1209600)) ;;   # 14 天
        4) cutoff_sec=$((now_sec - 2592000)) ;;   # 30 天
        5) cutoff_sec=0 ;;                        # 全部
        *) cutoff_sec=0 ;;
    esac

    for f in "${all_files[@]}"; do
        local fname
        fname=$(basename "$f" .json)
        # 解析时间戳
        if [[ "$fname" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
            local f_date="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
            local f_sec
            f_sec=$(date -d "$f_date" +%s 2>/dev/null || echo 0)
            if (( f_sec >= cutoff_sec )); then
                filtered+=("$f")
            fi
        else
            filtered+=("$f")
        fi
    done

    local count=${#filtered[@]}
    if [[ $count -eq 0 ]]; then
        # 如果过滤后为空，保底展示最新文件
        filtered=("${all_files[@]}")
        count=${#filtered[@]}
    fi

    # 如果选中的点多于 max_points，采用【变化感知关键帧自适应降采样】：
    # 优先锁定状态发生突变的关键点 (Keyframes) 及首尾点，剩余槽位等间距补充，确保突变 100% 呈现且时间轴均匀
    if (( count > max_points && max_points > 0 )); then
        local fingerprints=()
        mapfile -t fingerprints < <(
            jq -r '[
                .Info.Type,
                .Type,
                .Score,
                .Factor,
                .Media,
                .Mail.Port25,
                .Mail.DNSBlacklist.Blacklisted
            ] | tostring' "${filtered[@]}" 2>/dev/null
        )

        if [[ ${#fingerprints[@]} -eq $count ]]; then
            local is_key=()
            for ((i=0; i<count; i++)); do is_key+=(0); done
            is_key[0]=1
            is_key[$((count - 1))]=1

            local change_indices=()
            for ((i=1; i<count; i++)); do
                if [[ "${fingerprints[$i]}" != "${fingerprints[$((i - 1))]}" ]]; then
                    change_indices+=("$i")
                    is_key[$i]=1
                fi
            done

            local selected_indices=()
            for ((i=0; i<count; i++)); do
                [[ ${is_key[$i]} -eq 1 ]] && selected_indices+=("$i")
            done

            local key_count=${#selected_indices[@]}
            if (( key_count <= max_points )); then
                # 变动点数量未达上限：按最大时间空隙插入过渡点，保证整体时间轴平滑均匀
                local needed=$(( max_points - key_count ))
                while (( needed > 0 )); do
                    local max_gap=0
                    local best_insert=-1
                    for ((k=0; k<${#selected_indices[@]} - 1; k++)); do
                        local idx_a=${selected_indices[$k]}
                        local idx_b=${selected_indices[$((k + 1))]}
                        local gap=$(( idx_b - idx_a ))
                        if (( gap > max_gap && gap > 1 )); then
                            max_gap=$gap
                            best_insert=$(( idx_a + gap / 2 ))
                        fi
                    done
                    [[ $best_insert -eq -1 || $max_gap -le 1 ]] && break
                    is_key[$best_insert]=1
                    selected_indices=()
                    for ((i=0; i<count; i++)); do
                        [[ ${is_key[$i]} -eq 1 ]] && selected_indices+=("$i")
                    done
                    needed=$(( needed - 1 ))
                done
            else
                # 变动点数量超过上限：首尾锚定，中间变动点按时间轴等距精选
                local mid_needed=$(( max_points - 2 ))
                local mid_candidates=("${change_indices[@]}")
                if [[ ${#mid_candidates[@]} -gt 0 && ${mid_candidates[-1]} -eq $((count - 1)) ]]; then
                    unset 'mid_candidates[${#mid_candidates[@]}-1]'
                    mid_candidates=("${mid_candidates[@]}")
                fi
                local mid_total=${#mid_candidates[@]}
                local sampled_mid=()
                if (( mid_total > mid_needed )); then
                    for ((m=0; m<mid_needed; m++)); do
                        local c_idx=$(( m * (mid_total - 1) / (mid_needed - 1) ))
                        sampled_mid+=("${mid_candidates[$c_idx]}")
                    done
                else
                    sampled_mid=("${mid_candidates[@]}")
                fi

                is_key=()
                for ((i=0; i<count; i++)); do is_key+=(0); done
                is_key[0]=1
                is_key[$((count - 1))]=1
                for s_idx in "${sampled_mid[@]}"; do
                    is_key[$s_idx]=1
                done
                selected_indices=()
                for ((i=0; i<count; i++)); do
                    [[ ${is_key[$i]} -eq 1 ]] && selected_indices+=("$i")
                done
            fi

            for idx in "${selected_indices[@]}"; do
                printf "%s\n" "${filtered[$idx]}"
            done
            return
        fi

        # 回退保险：纯等间距采样
        local sampled=()
        for ((i=0; i<max_points; i++)); do
            local idx=$(( i * (count - 1) / (max_points - 1) ))
            sampled+=("${filtered[$idx]}")
        done
        printf "%s\n" "${sampled[@]}"
    else
        printf "%s\n" "${filtered[@]}"
    fi
}

# 选择数据时间范围 (无需选择 v4/v6，默认全部双栈展现)
select_time_range() {
    echo -e "${C_BOLD}选择数据时间范围:${C_RESET}"
    echo -e "  [1] 最近 24 小时   [4] 最近 30 天"
    echo -e "  [2] 最近 7 天      [5] 全部历史记录"
    echo -e "  [3] 最近 14 天     [0] 返回主菜单"
    echo -ne "${C_CYAN}请输入选项 [默认 2]: ${C_RESET}"
    read -r range_opt
    range_opt="${range_opt:-2}"
    if [[ "$range_opt" == "0" ]]; then
        return 1
    fi
    SELECTED_RANGE="$range_opt"
    return 0
}

# ==============================================================================
# 模块 1: IP 类型属性变化 (show_ip_type)
# ==============================================================================
render_ip_type_table() {
    local target_dir="$1"
    local target_proto="$2"

    local files=()
    mapfile -t files < <(load_archive_files "$target_dir" "$SELECTED_RANGE" 8)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${C_GRAY}暂无 $target_proto 存档数据${C_RESET}"
        return
    fi

    echo -e "${C_CYAN}${C_BOLD}▶ $target_proto IP 类型属性变化分析:${C_RESET}"

    # 提取各列时间表头
    local dates=()
    for f in "${files[@]}"; do
        dates+=("$(fmt_short_date "$(basename "$f" .json)")")
    done

    # 打印表头 (14 字符对齐)
    echo -n "  数据库 / 维度 "
    for d in "${dates[@]}"; do
        printf "│ %-8s " "$d"
    done
    printf "│ %-10s\n" "历史稳定性"
    
    local divider_len=$(( 15 + ${#dates[@]} * 11 + 14 ))
    echo -ne "  "
    draw_divider "$divider_len"

    # 数据库键值清单 (包含原生/广播、各库使用类型、各库公司类型)
    local row_keys=(
        "Info_Type"
        "Usage.IPinfo"
        "Usage.ipregistry"
        "Usage.ipapi"
        "Usage.IP2LOCATION"
        "Usage.AbuseIPDB"
        "Company.IPinfo"
        "Company.ipregistry"
        "Company.ipapi"
        "Company.IP2LOCATION"
    )
    local row_names=(
        "原生/广播    "
        "IPinfo (使用)"
        "ipreg  (使用)"
        "ipapi  (使用)"
        "IP2L   (使用)"
        "Abuse  (使用)"
        "IPinfo (公司)"
        "ipreg  (公司)"
        "ipapi  (公司)"
        "IP2L   (公司)"
    )

    local valid_row_count=0
    for idx in "${!row_keys[@]}"; do
        local rk="${row_keys[$idx]}"
        local rname="${row_names[$idx]}"

        local vals=()
        local row_has_data=false
        for f in "${files[@]}"; do
            local val=""
            if [[ "$rk" == "Info_Type" ]]; then
                val=$(jq -r '.Info.Type // "null"' "$f" 2>/dev/null | sed 's/Geo-consistent/原生IP/;s/Geo-discrepant/广播IP/')
            elif [[ "$rk" =~ ^Usage\.(.*) ]]; then
                local sub_k="${BASH_REMATCH[1]}"
                if [[ "$sub_k" == "IP2LOCATION" ]]; then
                    val=$(jq -r '.Type.Usage.IP2LOCATION // .Type.Usage.IP2Location // "null"' "$f" 2>/dev/null)
                else
                    val=$(jq -r ".Type.Usage.$sub_k // \"null\"" "$f" 2>/dev/null)
                fi
            elif [[ "$rk" =~ ^Company\.(.*) ]]; then
                local sub_k="${BASH_REMATCH[1]}"
                if [[ "$sub_k" == "IP2LOCATION" ]]; then
                    val=$(jq -r '.Type.Company.IP2LOCATION // .Type.Company.IP2Location // "null"' "$f" 2>/dev/null)
                else
                    val=$(jq -r ".Type.Company.$sub_k // \"null\"" "$f" 2>/dev/null)
                fi
            fi
            if [[ -z "$val" || "$val" == "null" || "$val" == "--" ]]; then
                val="无数据"
            else
                row_has_data=true
            fi
            vals+=("$val")
        done

        # 过滤在所选时间段中全部为无数据的维度
        [[ "$row_has_data" == "false" ]] && continue

        (( valid_row_count++ ))
        echo -n "  $rname "
        for val in "${vals[@]}"; do
            # 着色渲染 (6字符截断并用 pad_cell 对齐)
            local display_val="${val:0:6}"
            local cell_color="$C_GRAY"
            if [[ "$val" =~ (ISP|家宽|Line ISP|原生IP) ]]; then
                cell_color="$C_GREEN"
            elif [[ "$val" =~ (Data Center|Hosting|机房|广播IP|Transit) ]]; then
                cell_color="$C_RED"
            elif [[ "$val" =~ (Business|商业|Corporate) ]]; then
                cell_color="$C_YELLOW"
            fi
            local padded_val
            padded_val=$(pad_cell "$display_val" 8)
            printf "│ ${cell_color}%s${C_RESET} " "$padded_val"
        done

        # 计算稳定性
        local first_val="${vals[0]}"
        local is_stable=true
        for v in "${vals[@]}"; do
            if [[ "$v" != "$first_val" ]]; then
                is_stable=false
                break
            fi
        done

        if [[ "$is_stable" == "true" ]]; then
            printf "│ ${C_GREEN}✅ 保持稳定${C_RESET}\n"
        else
            printf "│ ${C_YELLOW}⚠️  存在变动${C_RESET}\n"
        fi
    done

    if (( valid_row_count == 0 )); then
        echo -e "  ${C_GRAY}（当前所选时间段内暂无有效类型记录）${C_RESET}"
    fi

    echo -ne "  "
    draw_divider "$divider_len"
}

show_ip_type() {
    clear
    select_time_range || return
    clear
    print_module_header "📊 IP 类型属性变化分析"

    render_ip_type_table "$V4_DIR" "IPv4"

    local v6_cnt
    v6_cnt=$(count_json_files "$V6_DIR")
    if (( v6_cnt > 0 )); then
        echo ""
        render_ip_type_table "$V6_DIR" "IPv6"
    fi

    echo -e "\n${C_GRAY}图例: ${C_GREEN}家宽/原生(绿色)${C_GRAY} | ${C_YELLOW}商业(黄色)${C_GRAY} | ${C_RED}机房/广播(红色)${C_GRAY} | 灰色(未识别/无数据)${C_RESET}\n"
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 2: 风险评分趋势 (show_risk_score)
# ==============================================================================

# 标准化评分值: 将 "1.56%" -> 2, "4.69%" -> 5, "47" -> 47, "null" -> ""
# 上游 ipapi 数据库返回的是百分比字符串而非整数，需要统一处理
normalize_score() {
    local raw="$1"
    [[ -z "$raw" || "$raw" == "null" || "$raw" == "" ]] && return
    # 纯整数直接返回
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        echo "$raw"
        return
    fi
    # 百分比格式: "1.56%" "4.69%" "0.12%" -> 提取数值部分并四舍五入为整数
    if [[ "$raw" =~ ^([0-9]+)\.?([0-9]*)%?$ ]]; then
        local int_part="${BASH_REMATCH[1]}"
        local dec_part="${BASH_REMATCH[2]}"
        # 四舍五入: 取小数点后第一位判断
        local first_dec="${dec_part:0:1}"
        if [[ -n "$first_dec" && "$first_dec" -ge 5 ]] 2>/dev/null; then
            echo $(( int_part + 1 ))
        else
            echo "$int_part"
        fi
        return
    fi
    # 纯小数 (无百分号): "1.56" -> 2
    if [[ "$raw" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        local int_part="${BASH_REMATCH[1]}"
        local dec_part="${BASH_REMATCH[2]}"
        local first_dec="${dec_part:0:1}"
        if [[ -n "$first_dec" && "$first_dec" -ge 5 ]] 2>/dev/null; then
            echo $(( int_part + 1 ))
        else
            echo "$int_part"
        fi
        return
    fi
    # 无法识别的格式，静默丢弃
}

render_bar() {
    local score
    score=$(normalize_score "$1")
    local max_width=30
    if [[ ! "$score" =~ ^[0-9]+$ ]]; then
        echo -e "${C_GRAY}┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈  无数据${C_RESET}"
        return
    fi

    # 计算柱条长度
    local bar_len=$(( score * max_width / 100 ))
    (( bar_len == 0 && score > 0 )) && bar_len=1
    local empty_len=$(( max_width - bar_len ))

    local color="$C_GREEN"
    local badge="低风险"
    if (( score > 75 )); then
        color="$C_MAGENTA"
        badge="极高风险"
    elif (( score > 50 )); then
        color="$C_RED"
        badge="高风险"
    elif (( score > 20 )); then
        color="$C_YELLOW"
        badge="中风险"
    fi

    local bar_str=""
    for ((b=0; b<bar_len; b++)); do bar_str+="█"; done
    local empty_str=""
    for ((b=0; b<empty_len; b++)); do empty_str+="░"; done

    printf "${color}%s${C_RESET}${C_GRAY}%s${C_RESET} %3d ${color}%s${C_RESET}\n" "$bar_str" "$empty_str" "$score" "$badge"
}

render_risk_score_chart() {
    local target_dir="$1"
    local target_proto="$2"

    local files=()
    mapfile -t files < <(load_archive_files "$target_dir" "$SELECTED_RANGE" 6)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${C_GRAY}暂无 $target_proto 评分存档数据${C_RESET}"
        return
    fi

    echo -e "${C_CYAN}${C_BOLD}▶ $target_proto 综合风险评分历史走势:${C_RESET}"

    local dbs=("SCAMALYTICS" "IP2LOCATION" "AbuseIPDB" "IPQS" "ipapi" "DBIP")
    local shown_db_count=0

    for db in "${dbs[@]}"; do
        # 预先检查该数据库在当前时间范围内是否有有效数值评分
        local db_has_score=false
        for f in "${files[@]}"; do
            local sc
            sc=$(jq -r ".Score.$db // \"null\"" "$f" 2>/dev/null)
            sc=$(normalize_score "$sc")
            if [[ "$sc" =~ ^[0-9]+$ ]]; then
                db_has_score=true
                break
            fi
        done
        [[ "$db_has_score" == "false" ]] && continue

        (( shown_db_count++ ))
        echo -e "${C_BOLD}  • 数据库: ${C_CYAN}$db${C_RESET} (满分 100)"
        for f in "${files[@]}"; do
            local dt
            dt=$(fmt_short_time "$(basename "$f" .json)")
            local score
            score=$(jq -r ".Score.$db // \"null\"" "$f" 2>/dev/null)
            printf "    %-12s ▏ " "$dt"
            render_bar "$score"
        done
        echo ""
    done

    if (( shown_db_count == 0 )); then
        echo -e "  ${C_GRAY}（当前所选时间段内各数据库暂无有效评分数据）${C_RESET}\n"
    fi
}

show_risk_score() {
    clear
    select_time_range || return
    clear
    print_module_header "📈 综合风险评分历史趋势"

    render_risk_score_chart "$V4_DIR" "IPv4"

    local v6_cnt
    v6_cnt=$(count_json_files "$V6_DIR")
    if (( v6_cnt > 0 )); then
        echo ""
        render_risk_score_chart "$V6_DIR" "IPv6"
    fi

    echo -e "${C_GRAY}说明: 评分越高风险越高。0-20 低风险 | 21-50 中风险 | 51-75 高风险 | 76+ 极高风险${C_RESET}\n"
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 3: 风险因子分析 (show_risk_factor)
# ==============================================================================
render_risk_factor_matrix() {
    local target_dir="$1"
    local target_proto="$2"

    local latest_file
    latest_file=$(get_latest_archive "$target_dir")
    if [[ -z "$latest_file" ]]; then
        echo -e "${C_GRAY}暂无 $target_proto 风险因子存档${C_RESET}"
        return
    fi

    echo -e "${C_CYAN}${C_BOLD}▶ $target_proto 核心风险因子综合矩阵 (最新存档: $(basename "$latest_file")):${C_RESET}"

    local engines=("IP2L" "ipapi" "ipreg" "IPQS" "SCAM" "ipdata" "IPinfo" "WHOIS" "DBIP")
    local full_engines=("IP2LOCATION" "ipapi" "ipregistry" "IPQS" "SCAMALYTICS" "ipdata" "IPinfo" "IPWHOIS" "DBIP")
    local factors=("Proxy" "Tor" "VPN" "Server" "Abuser" "Robot")

    # 打印表头
    printf "  %-10s │ " "风险因子"
    for eng in "${engines[@]}"; do
        printf "%-7s " "$eng"
    done
    echo ""
    echo -ne "  "
    draw_divider 74

    for factor in "${factors[@]}"; do
        printf "  %-10s │ " "$factor"
        for eng in "${full_engines[@]}"; do
            local val
            val=$(jq -r "if .Factor[\"$factor\"][\"$eng\"] != null then .Factor[\"$factor\"][\"$eng\"] else .Factor[\"$factor\"][\"WHOIS\"] end" "$latest_file")
            if [[ "$val" == "false" ]]; then
                printf "   %b    " "$SYM_DOT_GREEN"
            elif [[ "$val" == "true" ]]; then
                printf "   %b    " "$SYM_MARK_RED"
            else
                printf "   %b    " "$SYM_DOT_GRAY"
            fi
        done
        echo ""
    done

    echo -ne "  "
    draw_divider 74
    echo ""
}

render_risk_factor_history() {
    local target_dir="$1"
    local target_proto="$2"

    local hist_files=()
    mapfile -t hist_files < <(load_archive_files "$target_dir" "$SELECTED_RANGE" 6)
    if [[ ${#hist_files[@]} -eq 0 ]]; then
        return
    fi

    echo -e "${C_CYAN}${C_BOLD}▶ $target_proto 各风险因子历史检出趋势 (时间线):${C_RESET}"

    local dates=()
    for hf in "${hist_files[@]}"; do
        dates+=("$(fmt_short_date "$(basename "$hf" .json)")")
    done

    printf "  %-9s" "风险因子"
    for d in "${dates[@]}"; do
        printf "│  %-5s " "$d"
    done
    printf "│ %-12s\n" "历史综合表现"

    local divider_len=$(( 11 + ${#dates[@]} * 9 + 15 ))
    echo -ne "  "
    draw_divider "$divider_len"

    local full_engines=("IP2LOCATION" "ipapi" "ipregistry" "IPQS" "SCAMALYTICS" "ipdata" "IPinfo" "IPWHOIS" "DBIP")
    local factors=("Proxy" "Tor" "VPN" "Server" "Abuser" "Robot")

    for fac in "${factors[@]}"; do
        printf "  %-8s " "$fac"
        local had_detection=false
        for hf in "${hist_files[@]}"; do
            local detected_count=0
            local total_tested=0
            for eng in "${full_engines[@]}"; do
                local v
                v=$(jq -r "if .Factor[\"$fac\"][\"$eng\"] != null then .Factor[\"$fac\"][\"$eng\"] else .Factor[\"$fac\"][\"WHOIS\"] end" "$hf" 2>/dev/null)
                if [[ "$v" == "true" ]]; then
                    detected_count=$((detected_count + 1))
                    total_tested=$((total_tested + 1))
                elif [[ "$v" == "false" ]]; then
                    total_tested=$((total_tested + 1))
                fi
            done
            if (( detected_count > 0 )); then
                printf "│ ${C_RED}⚠️ %d/%d${C_RESET} " "$detected_count" "$total_tested"
                had_detection=true
            else
                printf "│ ${C_GREEN}✔ 安全${C_RESET} "
            fi
        done
        if [[ "$had_detection" == "true" ]]; then
            printf "│  ${C_YELLOW}⚠️ 曾有检出${C_RESET}\n"
        else
            printf "│  ${C_GREEN}✅ 保持安全${C_RESET}\n"
        fi
    done
    echo ""
}

show_risk_factor() {
    clear
    select_time_range || return
    clear
    print_module_header "🔬 风险因子综合矩阵与历史追踪"

    # 1. IPv4 风险因子矩阵与全量历史
    render_risk_factor_matrix "$V4_DIR" "IPv4"
    render_risk_factor_history "$V4_DIR" "IPv4"

    # 2. IPv6 (如果有) 风险因子矩阵与全量历史
    local v6_cnt
    v6_cnt=$(count_json_files "$V6_DIR")
    if (( v6_cnt > 0 )); then
        echo -e "${C_GRAY}──────────────────────────────────────────────────────────────────────${C_RESET}\n"
        render_risk_factor_matrix "$V6_DIR" "IPv6"
        render_risk_factor_history "$V6_DIR" "IPv6"
    fi

    echo -e "图例说明: ${SYM_DOT_GREEN} 安全/未检出  ${SYM_MARK_RED} 风险检出(警告)  ${SYM_DOT_GRAY} 未检测/不支持\n"
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 4: 流媒体与AI解锁 (show_media_unlock)
# ==============================================================================
render_media_unlock_table() {
    local target_dir="$1"
    local target_proto="$2"

    local files=()
    mapfile -t files < <(load_archive_files "$target_dir" "$SELECTED_RANGE" 10)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${C_GRAY}暂无 $target_proto 流媒体存档数据${C_RESET}"
        return
    fi

    echo -e "${C_CYAN}${C_BOLD}▶ $target_proto 流媒体与 AI 解锁历史监测:${C_RESET}"

    local dates=()
    for f in "${files[@]}"; do
        dates+=("$(fmt_short_date "$(basename "$f" .json)")")
    done

    # 打印时间表头
    printf "  %-14s │ " "服务名称"
    for d in "${dates[@]}"; do
        printf "%-5s " "$d"
    done
    echo ""
    local div_len=$(( 18 + ${#dates[@]} * 6 ))
    echo -ne "  "
    draw_divider "$div_len"

    local services=("TikTok" "DisneyPlus" "Netflix" "Youtube" "AmazonPrimeVideo" "Reddit" "ChatGPT")
    local display_names=("TikTok" "Disney+" "Netflix" "YouTube" "Amazon PV" "Reddit" "ChatGPT")

    local unlock_counts=()
    for ((s=0; s<${#services[@]}; s++)); do
        unlock_counts+=(0)
    done

    for idx in "${!services[@]}"; do
        local svc="${services[$idx]}"
        local sname="${display_names[$idx]}"
        printf "  %-14s │ " "$sname"

        local success_in_row=0
        for f in "${files[@]}"; do
            local status
            status=$(jq -r ".Media.$svc.Status // \"null\"" "$f")
            local mtype
            mtype=$(jq -r ".Media.$svc.Type // \"\"" "$f")

            if [[ "$status" =~ (解锁|Yes|Native) ]]; then
                if [[ "$mtype" =~ (DNS|ViaDNS|Proxy|代理解锁) ]]; then
                    printf "  %b   " "$SYM_DOT_YELLOW"
                else
                    printf "  %b   " "$SYM_DOT_GREEN"
                fi
                success_in_row=$((success_in_row + 1))
            elif [[ "$status" =~ (仅自制|Originals|NF\.Only|仅网页|仅APP|WebOnly|APPOnly|机房|IDC|待支持|Pending) ]]; then
                printf "  %b   " "$SYM_DOT_YELLOW"
                success_in_row=$((success_in_row + 1))
            elif [[ "$status" =~ (失败|屏蔽|No|Blocked|Block|Failed|中国|China|禁会员|NoPrem) ]]; then
                printf "  %b   " "$SYM_DOT_RED"
            else
                printf "  %b   " "$SYM_DOT_GRAY"
            fi
        done
        unlock_counts[$idx]=$success_in_row
        echo ""
    done

    echo -ne "  "
    draw_divider "$div_len"

    # 地区变化追踪
    echo -e "  📍 地区变化追踪 (Region Evolution):"
    for idx in "${!services[@]}"; do
        local svc="${services[$idx]}"
        local sname="${display_names[$idx]}"
        local regions=()
        for f in "${files[@]}"; do
            local reg
            reg=$(jq -r ".Media.$svc.Region // \"--\"" "$f")
            reg=$(clean_region_str "$reg")
            regions+=("$reg")
        done

        local has_change=false
        local first_reg="${regions[0]}"
        for r in "${regions[@]}"; do
            if [[ "$r" != "$first_reg" ]]; then
                has_change=true
                break
            fi
        done

        printf "    %-11s : " "$sname"
        for r in "${regions[@]}"; do
            printf "%-4s " "$r"
        done
        if [[ "$has_change" == "true" ]]; then
            echo -e "  ${C_YELLOW}${SYM_WARN} 存在漂移${C_RESET}"
        else
            echo -e "  ${C_GREEN}${SYM_CHECK} 稳定${C_RESET}"
        fi
    done
    echo ""
}

show_media_unlock() {
    clear
    select_time_range || return
    clear
    print_module_header "🎬 流媒体与 AI 解锁历史监测"

    render_media_unlock_table "$V4_DIR" "IPv4"

    local v6_cnt
    v6_cnt=$(count_json_files "$V6_DIR")
    if (( v6_cnt > 0 )); then
        render_media_unlock_table "$V6_DIR" "IPv6"
    fi

    echo -e "图例说明: ${SYM_DOT_GREEN} 原生解锁  ${SYM_DOT_YELLOW} DNS解锁 / 仅自制剧  ${SYM_DOT_RED} 失败/屏蔽  ${SYM_DOT_GRAY} 未检测\n"
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 5: 邮件连通与 DNS 黑名单监测 (show_mail_and_blacklist)
# ==============================================================================
render_mail_and_blacklist() {
    local target_dir="$1"
    local target_proto="$2"

    local files=()
    mapfile -t files < <(load_archive_files "$target_dir" "$SELECTED_RANGE" 8)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${C_GRAY}暂无 $target_proto 邮件与黑名单存档数据${C_RESET}"
        return
    fi

    echo -e "${C_CYAN}${C_BOLD}▶ $target_proto 邮件连通性与 DNS 黑名单状态:${C_RESET}"

    local latest_file="${files[-1]}"
    local p25_status
    p25_status=$(jq -r '.Mail.Port25 // "null"' "$latest_file")
    if [[ "$p25_status" == "true" ]]; then
        echo -e "  • 25 端口出站 (Port 25): ${C_GREEN}${C_BOLD}✓ 开放 (可发送外网邮件)${C_RESET}"
    elif [[ "$p25_status" == "false" ]]; then
        echo -e "  • 25 端口出站 (Port 25): ${C_RED}${C_BOLD}✗ 拦截/关闭 (IDC通常默认封禁25)${C_RESET}"
    else
        echo -e "  • 25 端口出站 (Port 25): ${C_GRAY}未检测${C_RESET}"
    fi

    # DNS 黑名单概况
    local total clean marked blacklisted
    total=$(jq -r '.Mail.DNSBlacklist.Total // 0' "$latest_file")
    clean=$(jq -r '.Mail.DNSBlacklist.Clean // 0' "$latest_file")
    marked=$(jq -r '.Mail.DNSBlacklist.Marked // 0' "$latest_file")
    blacklisted=$(jq -r '.Mail.DNSBlacklist.Blacklisted // 0' "$latest_file")

    local bl_status="${C_GREEN}全部干净通过 (0 拦截)${C_RESET}"
    if (( blacklisted > 0 )); then
        bl_status="${C_RED}检出 $blacklisted 个黑名单拦截！${C_RESET}"
    elif (( marked > 0 )); then
        bl_status="${C_YELLOW}检出 $marked 个可疑标记${C_RESET}"
    fi
    echo -e "  • 全局 DNS 黑名单概况 : $bl_status (共 $total 个数据库, 干净 $clean)"
    echo ""

    # 12 邮局连通性历史表格
    local dates=()
    for f in "${files[@]}"; do
        dates+=("$(fmt_short_date "$(basename "$f" .json)")")
    done

    printf "  %-10s │ " "邮局名称"
    for d in "${dates[@]}"; do
        printf "%-6s " "$d"
    done
    echo ""
    local div_len=$(( 15 + ${#dates[@]} * 7 ))
    echo -ne "  "
    draw_divider "$div_len"

    local mail_services=("Gmail" "Outlook" "Yahoo" "Apple" "QQ" "163" "Sohu" "Sina" "MailRU" "AOL" "GMX" "MailCOM")
    for svc in "${mail_services[@]}"; do
        printf "  %-10s │ " "$svc"
        for f in "${files[@]}"; do
            local res
            res=$(jq -r ".Mail[\"$svc\"]" "$f")
            if [[ "$res" == "true" ]]; then
                printf "  %b    " "$SYM_DOT_GREEN"
            elif [[ "$res" == "false" ]]; then
                printf "  %b    " "$SYM_DOT_RED"
            else
                printf "  %b    " "$SYM_DOT_GRAY"
            fi
        done
        echo ""
    done
    echo -ne "  "
    draw_divider "$div_len"
    echo ""
}

show_mail_and_blacklist() {
    clear
    select_time_range || return
    clear
    print_module_header "📬 邮件连通性与 DNS 黑名单监测"

    render_mail_and_blacklist "$V4_DIR" "IPv4"

    local v6_cnt
    v6_cnt=$(count_json_files "$V6_DIR")
    if (( v6_cnt > 0 )); then
        render_mail_and_blacklist "$V6_DIR" "IPv6"
    fi

    echo -e "图例说明: ${SYM_DOT_GREEN} 连通正常  ${SYM_DOT_RED} 连接失败/被拒  ${SYM_DOT_GRAY} 未检测\n"
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 7: 设置定时检测 (setup_cron)
# ==============================================================================
setup_cron() {
    clear
    load_config
    print_module_header "⚙️  设置后台定时自动检测与存档"

    local local_h
    local_h=$(get_beijing_4am_local_hour)
    local tz_name tz_offset server_time bj_time
    tz_name=$(date +%Z)
    tz_offset=$(date +%z)
    server_time=$(date '+%H:%M')
    bj_time=$(TZ="Asia/Shanghai" date '+%H:%M' 2>/dev/null || echo "--:--")

    echo -e "  ${C_GRAY}ℹ️  服务器时区: ${C_CYAN}${tz_name} (${tz_offset})${C_GRAY} │ 本机时间: ${C_BOLD}${server_time}${C_RESET}${C_GRAY} │ 北京时间: ${C_BOLD}${bj_time}${C_RESET}"
    echo -e "  ${C_YELLOW}💡 提示: 预设选项已按北京时间凌晨 04:00 自动换算 (对应本机服务器时间: ${C_BOLD}${local_h}:00${C_RESET}${C_YELLOW})${C_RESET}\n"

    # 检测当前 crontab 中是否有 ipqa 任务
    local current_cron
    current_cron=$(crontab -l 2>/dev/null | grep -E "ipqa(\.sh)? --cron" | head -n 1 || true)

    if [[ -n "$current_cron" ]]; then
        local cur_sched
        cur_sched=$(echo "$current_cron" | awk '{print $1,$2,$3,$4,$5}')
        local friendly_name="$cur_sched"
        if [[ "$cur_sched" == "0 $local_h * * *" ]]; then
            friendly_name="每天一次 (北京时间 04:00)"
        elif [[ "$cur_sched" == "0 $local_h */3 * *" ]]; then
            friendly_name="每 3 天一次 (北京时间 04:00)"
        elif [[ "$cur_sched" == "0 $local_h */7 * *" ]]; then
            friendly_name="每 7 天一次 (北京时间 04:00)"
        fi
        echo -e "当前状态: ${C_GREEN}已启用自动检测${C_RESET} [${friendly_name}]"
        echo -e "当前规则: ${C_YELLOW}$current_cron${C_RESET}\n"
    else
        echo -e "当前状态: ${C_GRAY}未配置定时检测${C_RESET}\n"
    fi

    echo -e "${C_BOLD}请选择定时检测周期:${C_RESET}"
    echo -e "  [1] 每天检测一次     (北京时间 04:00 / 本机 $local_h:00) [推荐/默认]"
    echo -e "  [2] 每 3 天检测一次  (北京时间 04:00 / 本机 $local_h:00)"
    echo -e "  [3] 每 7 天检测一次  (北京时间 04:00 / 本机 $local_h:00)"
    echo -e "  [4] 自定义 Cron 表达式"
    echo -e "  [5] 关闭/移除定时检测"
    echo -e "  [0] 返回主菜单"
    echo ""
    echo -ne "${C_CYAN}请输入选项 [默认 1]: ${C_RESET}"
    read -r opt
    opt="${opt:-1}"

    local new_cron_expr=""
    case "$opt" in
        1) new_cron_expr="0 $local_h * * *" ;;
        2) new_cron_expr="0 $local_h */3 * *" ;;
        3) new_cron_expr="0 $local_h */7 * *" ;;
        4)
            echo -ne "\n请输入 5 位 Cron 表达式 (如: 0 $local_h */5 * *): "
            read -r new_cron_expr
            ;;
        5)
            # 移除所有历史 IPQA cron (去重清理)
            local remaining
            remaining=$(crontab -l 2>/dev/null | grep -vE "ipqa(\.sh)? --cron" | grep -v "# IPQA AUTO CHECK" || true)
            if [[ -n "$remaining" ]]; then
                echo "$remaining" | crontab -
            else
                crontab -r 2>/dev/null || true
            fi
            echo -e "\n${C_GREEN}已成功移除定时检测任务！${C_RESET}"
            log_msg "INFO" "用户手动关闭了定时检测 cron 任务"
            read -r -p "按回车键返回..."
            return
            ;;
        0) return ;;
        *) echo -e "${C_RED}无效选项${C_RESET}"; sleep 1; return ;;
    esac

    if [[ -z "$new_cron_expr" ]]; then
        echo -e "${C_RED}Cron 表达式不能为空${C_RESET}"
        sleep 1
        return
    fi

    # 确定脚本执行绝对路径
    local script_path
    script_path="$(command -v ipqa 2>/dev/null || echo "$IPQA_HOME/ipqa.sh")"
    if [[ ! -x "$script_path" ]]; then
        script_path="$IPQA_HOME/ipqa.sh"
    fi

    # 清理旧的 IPQA cron 进行严格去重，再追加新配置
    local existing_cron
    existing_cron=$(crontab -l 2>/dev/null | grep -vE "ipqa(\.sh)? --cron" | grep -v "# IPQA AUTO CHECK" || true)

    {
        [[ -n "$existing_cron" ]] && echo "$existing_cron"
        echo "# IPQA AUTO CHECK - DO NOT EDIT MANUALLY"
        echo "$new_cron_expr $script_path --cron >> $LOG_FILE 2>&1"
    } | crontab -

    echo -e "\n${C_GREEN}✔ 定时检测配置成功！${C_RESET}"
    echo -e "设定规则: ${C_CYAN}$new_cron_expr $script_path --cron${C_RESET}"
    echo -e "执行周期: ${C_YELLOW}北京时间凌晨 04:00 (本机服务器时间 $local_h:00)${C_RESET}\n"
    log_msg "INFO" "配置定时任务: $new_cron_expr (北京时间 04:00 对应本机 $local_h:00)"
    read -r -p "按回车键返回..."
}

# ==============================================================================
# 模块 6: 查看历史存档快照 (view_archives - 图形图表化美化版，双栈合并展示)
# ==============================================================================
render_single_archive_card() {
    local f="$1"
    local proto_tag="$2"
    [[ ! -f "$f" ]] && return

    local ip asn org city country ip_type
    IFS=$'\t' read -r ip asn org city country ip_type < <(
        jq -r '[
            (.Head.IP // "未知"),
            (.Info.ASN // "--"),
            (.Info.Organization // "--"),
            (.Info.City.Name // ""),
            (.Info.Region.Name // ""),
            (.Info.Type // "--")
        ] | @tsv' "$f" 2>/dev/null
    )
    [[ "$asn" =~ ^[0-9]+$ ]] && asn="AS$asn"
    [[ "$city" == "null" ]] && city=""
    [[ "$country" == "null" ]] && country=""
    local loc="未知"
    if [[ -n "$city" && -n "$country" ]]; then loc="$city, $country"; elif [[ -n "$country" ]]; then loc="$country"; elif [[ -n "$city" ]]; then loc="$city"; fi

    ip_type=$(echo "$ip_type" | sed 's/Geo-consistent/原生IP/;s/Geo-discrepant/广播IP/')

    local proto_color="$C_GREEN"
    [[ "$proto_tag" == "IPv6" ]] && proto_color="$C_CYAN"

    echo -e "${proto_color}${C_BOLD}┌── [$proto_tag 检测快照卡片] ──────────────────────────────────────────┐${C_RESET}"
    echo -e "  ${C_CYAN}📡 节点 IP  :${C_RESET} ${C_BOLD}${ip}${C_RESET} ($proto_tag)"
    echo -e "  ${C_CYAN}🏢 组织/ASN :${C_RESET} ${asn} (${org})"
    echo -e "  ${C_CYAN}📍 地理位置 :${C_RESET} ${loc}"
    if [[ -n "$ip_type" && "$ip_type" != "--" && "$ip_type" != "null" && "$ip_type" != "未知" ]]; then
        local type_badge="$SYM_DOT_GREEN ${C_GREEN}${ip_type}${C_RESET}"
        [[ "$ip_type" =~ (广播IP|Discrepant) ]] && type_badge="$SYM_DOT_RED ${C_RED}${ip_type}${C_RESET}"
        echo -e "  ${C_CYAN}🌐 网络类型 :${C_RESET} ${type_badge}"
    fi

    # IP 类型属性 (展示 IPinfo, ipregistry, ipapi, IP2Location, AbuseIPDB 5大检测商)
    local active_type_dbs=()
    local type_usage_vals=()
    local type_comp_vals=()
    local type_col_widths=()
    local has_any_comp=false

    local type_data
    type_data=$(jq -r '
        .Type as $t |
        [
            ("IPinfo\t" + ($t.Usage.IPinfo // "") + "\t" + ($t.Company.IPinfo // "")),
            ("ipregistry\t" + ($t.Usage.ipregistry // "") + "\t" + ($t.Company.ipregistry // "")),
            ("ipapi\t" + ($t.Usage.ipapi // "") + "\t" + ($t.Company.ipapi // "")),
            ("IP2Location\t" + ($t.Usage.IP2LOCATION // $t.Usage.IP2Location // "") + "\t" + ($t.Company.IP2LOCATION // $t.Company.IP2Location // "")),
            ("AbuseIPDB\t" + ($t.Usage.AbuseIPDB // "") + "\t" + ($t.Company.AbuseIPDB // ""))
        ] | .[]
    ' "$f" 2>/dev/null)

    while IFS=$'\t' read -r tdb u c; do
        [[ -z "$tdb" ]] && continue
        [[ "$u" == "null" || "$u" == "--" ]] && u=""
        [[ "$c" == "null" || "$c" == "--" ]] && c=""
        if [[ -z "$u" && -z "$c" ]]; then
            continue
        fi

        active_type_dbs+=("$tdb")
        type_usage_vals+=("$u")
        type_comp_vals+=("$c")
        [[ -n "$c" ]] && has_any_comp=true

        local w=$(( ${#tdb} + 3 ))
        (( w < 12 )) && w=12
        type_col_widths+=("$w")
    done <<< "$type_data"

    if [[ ${#active_type_dbs[@]} -gt 0 ]]; then
        echo -e "  ${C_GRAY}── 🏷️ IP 类型属性 ──────────────────────────────────────────────────${C_RESET}"
        echo -ne "    ${C_CYAN}数据库:   ${C_RESET}"
        for (( i=0; i<${#active_type_dbs[@]}; i++ )); do
            local db="${active_type_dbs[$i]}"
            local w="${type_col_widths[$i]}"
            printf "%-${w}s" "$db"
        done
        echo ""

        echo -ne "    ${C_CYAN}使用类型: ${C_RESET}"
        for (( i=0; i<${#active_type_dbs[@]}; i++ )); do
            local u="${type_usage_vals[$i]}"
            local w="${type_col_widths[$i]}"
            fmt_type_badge "$u" "$w"
        done
        echo ""

        if [[ "$has_any_comp" == "true" ]]; then
            echo -ne "    ${C_CYAN}公司类型: ${C_RESET}"
            for (( i=0; i<${#active_type_dbs[@]}; i++ )); do
                local c="${type_comp_vals[$i]}"
                local w="${type_col_widths[$i]}"
                fmt_type_badge "$c" "$w"
            done
            echo ""
        fi
    fi

    # 风控评分 (仅展示具有有效数值评分的数据库，无数据的数据库直接隐藏)
    echo -e "  ${C_GRAY}── 📊 权威风控评分 ─────────────────────────────────────────────────${C_RESET}"
    local score_count=0
    local score_data
    score_data=$(jq -r '
        .Score as $s |
        ["SCAMALYTICS", "IP2LOCATION", "AbuseIPDB", "IPQS", "ipapi", "DBIP"] | map(
            . as $k | "\($k)\t\($s[$k] // "")"
        ) | .[]
    ' "$f" 2>/dev/null)
    while IFS=$'\t' read -r sdb sc; do
        sc=$(normalize_score "$sc")
        if [[ "$sc" =~ ^[0-9]+$ ]]; then
            printf "    • %-13s ▏ " "$sdb"
            render_bar "$sc"
            (( score_count++ ))
        fi
    done <<< "$score_data"
    if (( score_count == 0 )); then
        echo -e "    ${C_GRAY}• 暂无各权威数据库有效风控评分数据${C_RESET}"
    fi

    # 风险因子 (一次性提取 6 大安全因子检出状态)
    echo -e "  ${C_GRAY}── 🔬 核心安全因子 ─────────────────────────────────────────────────${C_RESET}"
    local factor_line="   "
    local factor_data
    factor_data=$(jq -r '
        .Factor as $f |
        ["Proxy", "Tor", "VPN", "Server", "Abuser", "Robot"] | map(
            . as $fac |
            "\($fac)\t\([ "IP2LOCATION", "ipapi", "ipregistry", "IPQS", "SCAMALYTICS", "ipdata", "IPinfo", "IPWHOIS", "DBIP", "WHOIS" ] | any(
                . as $eng |
                ($f[$fac][$eng] // false) == true or ($f[$fac][$eng] // false) == "true"
            ))"
        ) | .[]
    ' "$f" 2>/dev/null)
    while IFS=$'\t' read -r fac is_detected; do
        [[ -z "$fac" ]] && continue
        if [[ "$is_detected" == "true" ]]; then
            factor_line+=" ${fac}: ${C_RED}● 检出${C_RESET}  "
        else
            factor_line+=" ${fac}: ${C_GREEN}● 正常${C_RESET}  "
        fi
    done <<< "$factor_data"
    echo -e "$factor_line"

    # 流媒体解锁 (支持绿色原生解锁、黄色DNS解锁/仅自制剧、红色屏蔽失败)
    echo -e "  ${C_GRAY}── 🎬 流媒体与 AI 解锁 ─────────────────────────────────────────────${C_RESET}"
    local media_data
    media_data=$(jq -r '
        .Media as $m |
        [
            ("Youtube\tYouTube\t" + ($m.Youtube.Status // "未知") + "\t" + ($m.Youtube.Region // "") + "\t" + ($m.Youtube.Type // "")),
            ("Netflix\tNetflix\t" + ($m.Netflix.Status // "未知") + "\t" + ($m.Netflix.Region // "") + "\t" + ($m.Netflix.Type // "")),
            ("DisneyPlus\tDisney+\t" + ($m.DisneyPlus.Status // "未知") + "\t" + ($m.DisneyPlus.Region // "") + "\t" + ($m.DisneyPlus.Type // "")),
            ("TikTok\tTikTok\t" + ($m.TikTok.Status // "未知") + "\t" + ($m.TikTok.Region // "") + "\t" + ($m.TikTok.Type // "")),
            ("ChatGPT\tChatGPT\t" + ($m.ChatGPT.Status // "未知") + "\t" + ($m.ChatGPT.Region // "") + "\t" + ($m.ChatGPT.Type // "")),
            ("Reddit\tReddit\t" + ($m.Reddit.Status // "未知") + "\t" + ($m.Reddit.Region // "") + "\t" + ($m.Reddit.Type // ""))
        ] | .[]
    ' "$f" 2>/dev/null)

    while IFS=$'\t' read -r m_key m_name st reg m_type; do
        [[ -z "$m_key" ]] && continue
        [[ "$reg" == "null" ]] && reg=""
        [[ "$m_type" == "null" ]] && m_type=""
        reg=$(clean_region_str "$reg")
        [[ "$reg" == "--" ]] && reg=""

        local st_badge=""
        if [[ "$st" =~ (解锁|Yes|Native) ]]; then
            if [[ "$m_type" =~ (DNS|ViaDNS|代理解锁) ]]; then
                # DNS 分流解锁：黄色高亮
                st_badge="${C_YELLOW}⚡ DNS解锁${C_RESET}"
                [[ -n "$reg" ]] && st_badge+=" ${C_CYAN}[$reg]${C_RESET}"
            else
                # 原生解锁：绿色高亮
                st_badge="${C_GREEN}✓ 解锁${C_RESET}"
                [[ -n "$reg" ]] && st_badge+=" ${C_CYAN}[$reg]${C_RESET}"
            fi
        elif [[ "$st" =~ (仅自制|Originals|NF\.Only) ]]; then
            # 仅自制剧：黄色高亮
            if [[ "$m_type" =~ (DNS|ViaDNS) ]]; then
                st_badge="${C_YELLOW}⚠️ 仅自制剧 (DNS)${C_RESET}"
            else
                st_badge="${C_YELLOW}⚠️ 仅自制剧${C_RESET}"
            fi
            [[ -n "$reg" ]] && st_badge+=" ${C_CYAN}[$reg]${C_RESET}"
        elif [[ "$st" =~ (仅网页|WebOnly) ]]; then
            st_badge="${C_YELLOW}⚠️ 仅网页${C_RESET}"
            [[ -n "$reg" ]] && st_badge+=" ${C_CYAN}[$reg]${C_RESET}"
        elif [[ "$st" =~ (仅APP|APPOnly) ]]; then
            st_badge="${C_YELLOW}⚠️ 仅APP${C_RESET}"
            [[ -n "$reg" ]] && st_badge+=" ${C_CYAN}[$reg]${C_RESET}"
        elif [[ "$st" =~ (机房|IDC) ]]; then
            st_badge="${C_YELLOW}⚠️ 机房解锁${C_RESET}"
            [[ -n "$reg" ]] && st_badge+=" ${C_CYAN}[$reg]${C_RESET}"
        elif [[ "$st" =~ (待支持|Pending) ]]; then
            st_badge="${C_YELLOW}⏳ 待支持${C_RESET}"
            [[ -n "$reg" ]] && st_badge+=" ${C_CYAN}[$reg]${C_RESET}"
        elif [[ "$st" =~ (失败|屏蔽|No|Blocked|Block|Failed) ]]; then
            st_badge="${C_RED}✗ 屏蔽/失败${C_RESET}"
        elif [[ "$st" =~ (中国|China) ]]; then
            st_badge="${C_RED}✗ 中国区受限${C_RESET}"
        elif [[ "$st" =~ (禁会员|NoPrem) ]]; then
            st_badge="${C_RED}✗ 禁会员${C_RESET}"
        else
            st_badge="${C_GRAY}$st${C_RESET}"
            [[ -n "$reg" ]] && st_badge+=" ${C_CYAN}[$reg]${C_RESET}"
        fi
        printf "    • %-10s: %b\n" "$m_name" "$st_badge"
    done <<< "$media_data"

    # 邮件与 DNS 黑名单
    echo -e "  ${C_GRAY}── 📬 邮件连通与 DNS 黑名单 ─────────────────────────────────────────${C_RESET}"
    local p25 bl_total bl_blk
    IFS=$'\t' read -r p25 bl_total bl_blk < <(
        jq -r '[
            (.Mail.Port25 // "null"),
            (.Mail.DNSBlacklist.Total // 0),
            (.Mail.DNSBlacklist.Blacklisted // 0)
        ] | @tsv' "$f" 2>/dev/null
    )
    if [[ "$p25" == "true" ]]; then
        echo -e "    • 25 端口出站 (Port 25): ${C_GREEN}✓ 开放${C_RESET}"
    elif [[ "$p25" == "false" ]]; then
        echo -e "    • 25 端口出站 (Port 25): ${C_RED}✗ 拦截/封禁${C_RESET}"
    else
        echo -e "    • 25 端口出站 (Port 25): ${C_GRAY}未检出${C_RESET}"
    fi

    if (( bl_blk == 0 )); then
        echo -e "    • DNS 黑名单拦截       : ${C_GREEN}0 / $bl_total 数据库 (全部干净通过)${C_RESET}"
    else
        echo -e "    • DNS 黑名单拦截       : ${C_RED}$bl_blk / $bl_total 数据库检出拦截！${C_RESET}"
    fi
    echo -e "${proto_color}└──────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

find_matching_v6() {
    local target_ts="$1"
    local direct="$V6_DIR/${target_ts}.json"
    if [[ -f "$direct" ]]; then
        echo "$direct"
        return
    fi
    for f6 in "$V6_DIR"/*.json; do
        [[ ! -f "$f6" ]] && continue
        local fn6
        fn6=$(basename "$f6" .json)
        # 简单比对前 13 个字符 (YYYY-MM-DD_HH)
        if [[ "${fn6:0:13}" == "${target_ts:0:13}" ]]; then
            echo "$f6"
            return
        fi
    done
    echo ""
}

render_archive_snapshot() {
    local v4_f="$1"
    local v6_f="$2"
    local ts="$3"

    clear
    local dt
    dt=$(fmt_timestamp "$ts")
    print_module_header "📋 历史存档双栈快照: $dt"

    local rendered=false
    if [[ -f "$v4_f" ]]; then
        render_single_archive_card "$v4_f" "IPv4"
        rendered=true
    fi

    if [[ -n "$v6_f" && -f "$v6_f" ]]; then
        [[ "$rendered" == "true" ]] && echo ""
        render_single_archive_card "$v6_f" "IPv6"
        rendered=true
    fi

    if [[ "$rendered" == "false" ]]; then
        echo -e "${C_YELLOW}未找到该时段的有效存档文件${C_RESET}\n"
        read -r -p "按回车键返回..."
        return
    fi

    echo ""
    echo -ne "操作: ${C_CYAN}[j]${C_RESET} 查看底层原始 JSON | ${C_CYAN}[0/回车]${C_RESET} 返回列表: "
    read -r sub_view
    if [[ "$sub_view" == "j" || "$sub_view" == "J" ]]; then
        local target_f="$v4_f"
        if [[ -f "$v4_f" && -n "$v6_f" && -f "$v6_f" ]]; then
            echo -ne "请选择要查看的协议 JSON: ${C_GREEN}[1] IPv4${C_RESET}  ${C_CYAN}[2] IPv6${C_RESET} [默认 1]: "
            read -r j_choice
            [[ "$j_choice" == "2" ]] && target_f="$v6_f"
        elif [[ -n "$v6_f" && -f "$v6_f" ]]; then
            target_f="$v6_f"
        fi

        clear
        echo -e "${C_BOLD}文件路径: $target_f${C_RESET}\n"
        if command -v less >/dev/null 2>&1; then
            jq . "$target_f" 2>/dev/null | less -R
        elif command -v jq >/dev/null 2>&1; then
            jq . "$target_f" | head -n 80
            echo -e "\n${C_GRAY}(展示前 80 行，完整文件位于 $target_f)${C_RESET}"
        else
            cat "$target_f"
        fi
        echo ""
        read -r -p "按回车键返回..."
    fi
}

view_archives() {
    # 收集全部不重复的时间戳 (双栈一体，无需区分选择)
    local all_ts=()
    for f in "$V4_DIR"/*.json; do
        [[ -f "$f" ]] && all_ts+=("$(basename "$f" .json)")
    done
    for f in "$V6_DIR"/*.json; do
        [[ -f "$f" ]] && all_ts+=("$(basename "$f" .json)")
    done

    if [[ ${#all_ts[@]} -eq 0 ]]; then
        clear
        print_module_header "📋 历史存档图表快照查看"
        echo -e "${C_YELLOW}暂无任何历史存档数据，请先执行一次检测 (选项 8)${C_RESET}\n"
        read -r -p "按回车键返回..."
        return
    fi

    local sorted_ts=()
    mapfile -t sorted_ts < <(printf "%s\n" "${all_ts[@]}" | sort -u -r)

    local page=0
    local page_size=15
    local total_count=${#sorted_ts[@]}
    local total_pages=$(( (total_count + page_size - 1) / page_size ))

    while true; do
        clear
        print_module_header "📋 历史存档图表快照查看"

        local start_idx=$((page * page_size))
        local end_idx=$((start_idx + page_size))
        (( end_idx > total_count )) && end_idx=$total_count

        echo -e "最近检测归档列表 (共 ${total_count} 条，第 $((page + 1))/${total_pages} 页):\n"
        for ((i=start_idx; i<end_idx; i++)); do
            local ts="${sorted_ts[$i]}"
            local dt
            dt=$(fmt_timestamp "$ts")

            local f_v4="$V4_DIR/${ts}.json"
            local f_v6
            f_v6=$(find_matching_v6 "$ts")

            local ip_v4="无"
            local ip_v6="无"
            local loc_str=""

            if [[ -f "$f_v4" ]]; then
                ip_v4=$(jq -r '.Head.IP // "未知"' "$f_v4" 2>/dev/null)
                loc_str=$(jq -r '.Info.Region.Name // ""' "$f_v4" 2>/dev/null)
            fi
            if [[ -n "$f_v6" && -f "$f_v6" ]]; then
                ip_v6=$(jq -r '.Head.IP // "未知"' "$f_v6" 2>/dev/null)
                [[ -z "$loc_str" || "$loc_str" == "null" ]] && loc_str=$(jq -r '.Info.Region.Name // ""' "$f_v6" 2>/dev/null)
            fi
            [[ "$loc_str" == "null" ]] && loc_str=""

            printf "  ${C_BOLD}[%2d]${C_RESET} %-19s │ ${C_GREEN}v4:${C_RESET} %-15s │ ${C_CYAN}v6:${C_RESET} %-18s │ %s\n" \
                "$((i + 1))" "$dt" "${ip_v4:0:15}" "${ip_v6:0:18}" "${loc_str:+($loc_str)}"
        done

        echo ""
        local nav_hint=""
        (( page + 1 < total_pages )) && nav_hint+="[n] 下一页 | "
        (( page > 0 )) && nav_hint+="[p] 上一页 | "
        echo -e "${C_GRAY}──────────────────────────────────────────────────────────────────────${C_RESET}"
        echo -ne "${C_CYAN}操作: [编号] 查看快照 | ${nav_hint}[0/回车] 返回主菜单: ${C_RESET}"
        read -r opt_act

        if [[ "$opt_act" == "0" || -z "$opt_act" ]]; then
            break
        elif [[ "$opt_act" == "n" || "$opt_act" == "N" ]]; then
            if (( page + 1 < total_pages )); then
                page=$((page + 1))
            fi
        elif [[ "$opt_act" == "p" || "$opt_act" == "P" ]]; then
            if (( page > 0 )); then
                page=$((page - 1))
            fi
        elif [[ "$opt_act" =~ ^[0-9]+$ ]] && (( opt_act >= 1 && opt_act <= total_count )); then
            local chosen_ts="${sorted_ts[$((opt_act - 1))]}"
            local sel_v4="$V4_DIR/${chosen_ts}.json"
            local sel_v6
            sel_v6=$(find_matching_v6 "$chosen_ts")
            render_archive_snapshot "$sel_v4" "$sel_v6" "$chosen_ts"
        fi
    done
}

# ==============================================================================
# 模块 9: 清理历史数据 (cleanup_data)
# ==============================================================================
cleanup_data() {
    clear
    print_module_header "🗑️  清理与维护历史数据"

    local v4_cnt v6_cnt v4_size v6_size
    v4_cnt=$(count_json_files "$V4_DIR")
    v6_cnt=$(count_json_files "$V6_DIR")
    v4_size=$(du -sh "$V4_DIR" 2>/dev/null | awk '{print $1}')
    v6_size=$(du -sh "$V6_DIR" 2>/dev/null | awk '{print $1}')

    echo -e "当前存储统计:"
    echo -e "  • IPv4 存档: ${C_CYAN}$v4_cnt${C_RESET} 份 (占用: ${C_YELLOW}${v4_size:-0}${C_RESET})"
    echo -e "  • IPv6 存档: ${C_CYAN}$v6_cnt${C_RESET} 份 (占用: ${C_YELLOW}${v6_size:-0}${C_RESET})\n"

    echo -e "${C_BOLD}请选择清理操作:${C_RESET}"
    echo -e "  [1] 删除 30 天前的旧存档"
    echo -e "  [2] 删除 90 天前的旧存档"
    echo -e "  [3] 删除 180 天前的旧存档"
    echo -e "  [4] 仅保留最新 N 份存档"
    echo -e "  [5] 清空所有历史存档数据 (${C_RED}危险${C_RESET})"
    echo -e "  [6] 清空告警日志 (alerts.log)"
    echo -e "  [0] 返回主菜单"
    echo ""
    echo -ne "${C_CYAN}请输入选项: ${C_RESET}"
    read -r c_opt

    case "$c_opt" in
        1)
            find "$V4_DIR" "$V6_DIR" -type f -name "*.json" -mtime +30 -delete 2>/dev/null
            echo -e "\n${C_GREEN}已清理 30 天前的数据！${C_RESET}"
            ;;
        2)
            find "$V4_DIR" "$V6_DIR" -type f -name "*.json" -mtime +90 -delete 2>/dev/null
            echo -e "\n${C_GREEN}已清理 90 天前的数据！${C_RESET}"
            ;;
        3)
            find "$V4_DIR" "$V6_DIR" -type f -name "*.json" -mtime +180 -delete 2>/dev/null
            echo -e "\n${C_GREEN}已清理 180 天前的数据！${C_RESET}"
            ;;
        4)
            echo -ne "请输入保留的存档份数: "
            read -r keep_num
            if [[ "$keep_num" =~ ^[0-9]+$ ]] && (( keep_num > 0 )); then
                for d in "$V4_DIR" "$V6_DIR"; do
                    local total
                    total=$(count_json_files "$d")
                    if (( total > keep_num )); then
                        local diff=$((total - keep_num))
                        find "$d" -maxdepth 1 -name '*.json' 2>/dev/null | sort | head -n "$diff" | xargs rm -f 2>/dev/null
                    fi
                done
                echo -e "\n${C_GREEN}已保留最近 $keep_num 份存档，清理完成！${C_RESET}"
            fi
            ;;
        5)
            echo -ne "${C_RED}确认要删除全部数据吗？(y/N): ${C_RESET}"
            read -r confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                rm -f "$V4_DIR"/*.json "$V6_DIR"/*.json
                echo -e "\n${C_GREEN}历史数据已全部清空！${C_RESET}"
            fi
            ;;
        6)
            > "$ALERT_LOG"
            echo -e "\n${C_GREEN}告警日志已清空！${C_RESET}"
            ;;
        0) return ;;
        *) echo -e "${C_RED}无效选项${C_RESET}" ;;
    esac
    read -r -p "按回车键返回..."
}

# ==============================================================================
# 模块 x: 卸载 IPQA (uninstall_ipqa)
# ==============================================================================
uninstall_ipqa() {
    clear
    print_module_header "🧹 卸载 IP 质量存档监测系统 (IPQA)"
    echo -e "${C_YELLOW}${C_BOLD}⚠️  警告: 即将执行 IPQA 监测系统卸载流程！${C_RESET}\n"
    echo -e "卸载操作将执行:"
    echo -e "  1. 自动移除 crontab 中所有 IPQA 定时检测任务"
    echo -e "  2. 自动删除系统全局命令软链接 (/usr/local/bin/ipqa, ~/.local/bin/ipqa)"
    echo -e "  3. 可选：彻底清除所有历史存档数据与配置 (~/.ipqa)\n"

    echo -ne "${C_RED}确认要卸载 IPQA 吗? [y/N]: ${C_RESET}"
    read -r confirm_un
    if [[ "$confirm_un" != "y" && "$confirm_un" != "Y" ]]; then
        echo -e "\n${C_GRAY}已取消卸载。${C_RESET}"
        sleep 1
        return
    fi

    echo -e "\n${C_CYAN}▶ [1/3] 正在清理定时任务...${C_RESET}"
    local remaining
    remaining=$(crontab -l 2>/dev/null | grep -vE "ipqa(\.sh)? --cron" | grep -v "# IPQA AUTO CHECK" || true)
    if [[ -n "$remaining" ]]; then
        echo "$remaining" | crontab -
    else
        crontab -r 2>/dev/null || true
    fi
    echo -e "${C_GREEN}✔ 定时检测任务已成功移除${C_RESET}"

    echo -e "\n${C_CYAN}▶ [2/3] 正在删除全局命令软链接...${C_RESET}"
    local links=("/usr/local/bin/ipqa" "$HOME/.local/bin/ipqa" "$HOME/bin/ipqa")
    for link in "${links[@]}"; do
        if [[ -L "$link" || -f "$link" ]]; then
            rm -f "$link" 2>/dev/null || sudo rm -f "$link" 2>/dev/null || true
            echo -e "${C_GREEN}✔ 已删除 $link${C_RESET}"
        fi
    done

    echo -e "\n${C_CYAN}▶ [3/3] 数据与配置目录清理${C_RESET}"
    echo -ne "${C_YELLOW}是否删除所有历史检测存档与配置 ($IPQA_HOME)? [y/N]: ${C_RESET}"
    read -r rm_data
    if [[ "$rm_data" == "y" || "$rm_data" == "Y" ]]; then
        rm -rf "$IPQA_HOME"
        echo -e "${C_GREEN}✔ 已彻底删除 $IPQA_HOME${C_RESET}"
    else
        echo -e "${C_GRAY}ℹ️ 已保留历史存档与配置目录: $IPQA_HOME${C_RESET}"
    fi

    echo -e "\n${C_GREEN}${C_BOLD}✔ IPQA 已完全卸载！感谢使用。${C_RESET}\n"
    exit 0
}

# ==============================================================================
# 在线更新 IPQA (update_ipqa)
# ==============================================================================
update_ipqa() {
    clear
    print_module_header "🔄 在线更新 IPQA 系统与检测核心"
    echo -e "${C_CYAN}正在检查并下载 IPQA 主程序最新版本...${C_RESET}"
    local tmp_file="$IPQA_HOME/ipqa.sh.tmp"
    if curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/ipqa.sh -o "$tmp_file"; then
        if bash -n "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$IPQA_HOME/ipqa.sh"
            sed -i 's/\r$//' "$IPQA_HOME/ipqa.sh" 2>/dev/null || true
            chmod +x "$IPQA_HOME/ipqa.sh"
            echo -e "${C_GREEN}✔ IPQA 主程序已更新至最新版本${C_RESET}"
        else
            rm -f "$tmp_file"
            echo -e "${C_RED}错误: 下载的主程序脚本校验失败${C_RESET}\n"
            exit 1
        fi
    else
        echo -e "${C_RED}错误: 无法连接 GitHub 下载主程序，请检查网络${C_RESET}\n"
        exit 1
    fi

    echo -e "\n${C_CYAN}正在同步 IPQuality 检测核心最新版本...${C_RESET}"
    local tmp_core="$IPQA_HOME/ip.sh.tmp"
    if curl -sL https://IP.Check.Place -o "$tmp_core" 2>/dev/null || curl -sL https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh -o "$tmp_core" 2>/dev/null; then
        mv "$tmp_core" "$IP_SCRIPT"
        sed -i 's/\r$//' "$IP_SCRIPT" 2>/dev/null || true
        chmod +x "$IP_SCRIPT"
        patch_ip_script
        date +%s > "$IPQA_HOME/.last_auto_update" 2>/dev/null || true
        rm -f "$IPQA_HOME/.last_core_update" 2>/dev/null || true
        echo -e "${C_GREEN}✔ IPQuality 检测核心已成功同步至最新版本！${C_RESET}"
    else
        rm -f "$tmp_core"
        echo -e "${C_YELLOW}⚠ 检测核心下载超时，已保留本地版本${C_RESET}"
    fi

    echo -e "\n${C_GREEN}${C_BOLD}🎉 IPQA 系统及检测核心已全部更新完成！${C_RESET}\n"
    exit 0
}

# ==============================================================================
# 主菜单 Panel 渲染
# ==============================================================================
render_panel() {
    clear
    load_config

    # 获取最新 v4 和 v6 存档
    local latest_v4 latest_v6
    latest_v4=$(get_latest_archive "$V4_DIR")
    latest_v6=$(get_latest_archive "$V6_DIR")

    local ip_v4="未检测"
    local ip_v6="无"
    local asn="--"
    local org="--"
    local loc="--"
    local last_check="从无检测记录"

    if [[ -n "$latest_v4" ]]; then
        IFS=$'\t' read -r ip_v4 asn org city country < <(
            jq -r '[
                (.Head.IP // "未知"),
                (.Info.ASN // "--"),
                (.Info.Organization // "--"),
                (.Info.City.Name // ""),
                (.Info.Region.Name // "")
            ] | @tsv' "$latest_v4" 2>/dev/null
        )
        [[ "$city" == "null" ]] && city=""
        [[ "$country" == "null" ]] && country=""
        if [[ -n "$city" && -n "$country" ]]; then
            loc="$city, $country"
        elif [[ -n "$country" ]]; then
            loc="$country"
        elif [[ -n "$city" ]]; then
            loc="$city"
        else
            loc="未知"
        fi
        last_check=$(fmt_timestamp "$(basename "$latest_v4" .json)")
    fi

    if [[ -n "$latest_v6" ]]; then
        ip_v6=$(jq -r '.Head.IP // "无"' "$latest_v6" 2>/dev/null)
    fi

    # 统计数量与时间跨度
    local count_v4 count_v6
    count_v4=$(count_json_files "$V4_DIR")
    count_v6=$(count_json_files "$V6_DIR")

    local oldest_file time_span="--"
    oldest_file=$(find "$V4_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | sort | head -n 1)
    if [[ -n "$oldest_file" && -n "$latest_v4" ]]; then
        local d1 d2
        d1=$(fmt_short_date "$(basename "$oldest_file" .json)")
        d2=$(fmt_short_date "$(basename "$latest_v4" .json)")
        time_span="$d1 ~ $d2"
    fi

    # 定时检测状态 (提取执行周期并显示友好名称)
    local cron_status="未开启"
    local cron_colored="${C_GRAY}未开启${C_RESET}"
    local cron_line
    cron_line=$(crontab -l 2>/dev/null | grep -E "ipqa(\.sh)? --cron" | head -n 1 || true)
    if [[ -n "$cron_line" ]]; then
        local schedule
        schedule=$(echo "$cron_line" | awk '{print $1,$2,$3,$4,$5}')
        local local_h
        local_h=$(get_beijing_4am_local_hour)
        if [[ "$schedule" == "0 $local_h * * *" ]]; then
            cron_status="每天 (北京 04:00)"
        elif [[ "$schedule" == "0 $local_h */3 * *" ]]; then
            cron_status="每 3 天 (北京 04:00)"
        elif [[ "$schedule" == "0 $local_h */7 * *" ]]; then
            cron_status="每 7 天 (北京 04:00)"
        else
            cron_status="$schedule"
        fi
        cron_colored="${C_GREEN}开启 [${cron_status}]${C_RESET}"
    fi

    local asn_display="$asn"
    [[ "$asn" =~ ^[0-9]+$ ]] && asn_display="AS$asn"

    # 获取检测核心版本
    local core_ver=""
    if [[ -f "$IP_SCRIPT" ]]; then
        core_ver=$(grep -m 1 'script_version=' "$IP_SCRIPT" 2>/dev/null | cut -d '"' -f 2)
    fi
    local ver_display=""
    if [[ -n "$core_ver" ]]; then
        ver_display="(Core: ${core_ver})"
    fi

    # 打印顶部 Panel
    echo -e "${C_CYAN}${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "   ${C_BOLD}${C_GREEN}🔍 IP 质量存档监测系统 (IPQA)${C_RESET}  ${C_GRAY}${ver_display}${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    echo -e "  ${C_CYAN}📡 节点网络:${C_RESET} ${C_BOLD}${ip_v4}${C_RESET} (IPv4)  ${C_GRAY}│${C_RESET}  ${C_BOLD}${ip_v6}${C_RESET} (IPv6)"
    echo -e "  ${C_CYAN}🏢 归属信息:${C_RESET} ${asn_display}  ${C_GRAY}│${C_RESET}  📍 ${loc}"
    echo -e "  ${C_CYAN}⏰ 上次检测:${C_RESET} ${last_check}"
    echo -e "  ${C_CYAN}📦 历史存档:${C_RESET} IPv4: ${C_GREEN}${count_v4}${C_RESET} 份  ${C_GRAY}│${C_RESET}  IPv6: ${C_GREEN}${count_v6}${C_RESET} 份"
    echo -e "  ${C_CYAN}📅 时间跨度:${C_RESET} ${time_span}"
    echo -e "  ${C_CYAN}🔄 定时检测:${C_RESET} ${cron_colored} ${C_GRAY}(每天静默自动更新脚本与核心)${C_RESET}"
    echo ""
    echo -e "${C_GRAY}── ${C_YELLOW}⚠️  最近风险变化提醒${C_RESET} ${C_GRAY}───────────────────────────────────────────────${C_RESET}"

    # 读取最近 3 条告警
    local alerts=()
    mapfile -t alerts < <(get_recent_alerts 3)
    if [[ ${#alerts[@]} -eq 0 ]]; then
        echo -e "  ${C_GREEN}• 暂无异常风险波动，IP 质量状态保持稳定${C_RESET}"
    else
        for alt in "${alerts[@]}"; do
            # 格式: 2026-09-11 12:00:00|WARNING|YouTube Region 发生变化|IPv4
            IFS='|' read -r a_time a_level a_msg a_ver <<< "$alt"
            local a_short_time
            a_short_time=$(echo "$a_time" | cut -d ' ' -f 1 | cut -d '-' -f 2,3)
            if [[ "$a_level" == "CRITICAL" ]]; then
                echo -e "  ${C_RED}• [${a_short_time}] ${a_msg}${C_RESET}"
            elif [[ "$a_level" == "WARNING" ]]; then
                echo -e "  ${C_YELLOW}• [${a_short_time}] ${a_msg}${C_RESET}"
            else
                echo -e "  ${C_CYAN}• [${a_short_time}] ${a_msg}${C_RESET}"
            fi
        done
    fi
    echo ""
    echo -e "${C_GRAY}── ${C_CYAN}📋 功能菜单导航${C_RESET} ${C_GRAY}───────────────────────────────────────────────────${C_RESET}"
    echo -e "  ${C_BOLD}[1]${C_RESET} 📊 IP 类型属性变动       ${C_BOLD}[6]${C_RESET} 📋 历史存档图表快照"
    echo -e "  ${C_BOLD}[2]${C_RESET} 📈 综合风险评分图        ${C_BOLD}[7]${C_RESET} ⚙️  配置定时任务"
    echo -e "  ${C_BOLD}[3]${C_RESET} 🔬 风险因子综合矩阵      ${C_BOLD}[8]${C_RESET} 🔄 立即执行检测"
    echo -e "  ${C_BOLD}[4]${C_RESET} 🎬 流媒体与AI解锁        ${C_BOLD}[9]${C_RESET} 🗑️  清理历史数据"
    echo -e "  ${C_BOLD}[5]${C_RESET} 📬 邮件与黑名单监测      ${C_BOLD}[0]${C_RESET} 🚪 退出系统  ${C_BOLD}[x]${C_RESET} 🧹 卸载系统"
    echo -e "${C_GRAY}──────────────────────────────────────────────────────────────────────${C_RESET}"
}

main_loop() {
    check_dependencies
    load_config
    # 每天自动静默更新脚本与检测核心 (后台运行，不阻塞界面交互)
    ( auto_update_if_needed true >/dev/null 2>&1 & )

    while true; do
        render_panel
        echo -ne "${C_CYAN}请输入指令: ${C_RESET}"
        read -r choice
        case "$choice" in
            1) show_ip_type ;;
            2) show_risk_score ;;
            3) show_risk_factor ;;
            4) show_media_unlock ;;
            5) show_mail_and_blacklist ;;
            6) view_archives ;;
            7) setup_cron ;;
            8)
                clear
                run_check false
                read -r -p "检测完毕，按回车键返回主菜单..."
                ;;
            9) cleanup_data ;;
            x|X) uninstall_ipqa ;;
            0|q|Q)
                echo -e "\n感谢使用 IPQA，再见！"
                exit 0
                ;;
            *)
                echo -e "${C_RED}无效输入，请重试${C_RESET}"
                sleep 0.8
                ;;
        esac
    done
}

# ==============================================================================
# 命令行参数入口
# ==============================================================================
case "$1" in
    --cron)
        check_dependencies
        run_check true
        ;;
    --check)
        check_dependencies
        run_check false
        ;;
    --status)
        check_dependencies
        load_config
        v4_cnt=$(count_json_files "$V4_DIR")
        v6_cnt=$(count_json_files "$V6_DIR")
        latest=$(get_latest_archive "$V4_DIR")
        echo "IPQA Status"
        echo "Archives: v4: $v4_cnt, v6: $v6_cnt"
        if [[ -n "$latest" ]]; then
            echo "Latest IP: $(jq -r '.Head.IP' "$latest")"
            echo "Latest Time: $(basename "$latest" .json)"
        fi
        ;;
    --update)
        update_ipqa
        ;;
    --uninstall)
        uninstall_ipqa
        ;;
    --help|-h)
        echo "IP Quality Archive (IPQA)"
        echo "用法: ipqa [选项]"
        echo ""
        echo "选项:"
        echo "  (无参数)      启动交互式终端图形界面 (TUI)"
        echo "  --check       立即执行一次检测并生成存档与告警"
        echo "  --cron        静默模式执行检测 (专用于 crontab 定时任务，自动同步最新核心)"
        echo "  --status      查看当前存档与状态概况"
        echo "  --update      一键从 GitHub 在线更新 IPQA 主程序"
        echo "  --uninstall   干净卸载 IPQA 并清理任务与软链接"
        echo "  --help, -h    显示本帮助信息"
        ;;
    --test)
        ;;
    *)
        main_loop
        ;;
esac
