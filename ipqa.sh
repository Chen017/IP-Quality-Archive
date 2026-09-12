#!/usr/bin/env bash
# ==============================================================================
# IP Quality Archive (IPQA) - IP 质量存档监测系统
# Version: 1.0.0
# Description: 基于 IPQuality 的 IP 质量历史存档与终端可视化监测工具
# GitHub: https://github.com/xykt/IPQuality
# ==============================================================================

# 基础环境与路径配置
IPQA_VERSION="v1.0.0"
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
    local line=""
    for ((d_i=0; d_i<len; d_i++)); do line+="─"; done
    echo -e "${C_GRAY}${line}${C_RESET}"
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
    CHECK_INTERVAL_HOURS=6
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
CHECK_INTERVAL_HOURS=${CHECK_INTERVAL_HOURS:-6}
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
    fi
    if [[ ! -f "$IP_SCRIPT" ]]; then
        echo -e "${C_RED}错误: 无法获取 IPQuality 脚本缓存 ($IP_SCRIPT)${C_RESET}"
        return 1
    fi
    return 0
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
    if [[ ! -d "$dir" ]]; then
        return 1
    fi
    local latest
    latest=$(ls -1r "$dir"/*.json 2>/dev/null | head -n 1)
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
        tail -n "$count" "$ALERT_LOG" 2>/dev/null
    fi
}

compare_and_alert() {
    local dir="$1"
    local new_file="$2"
    local ip_ver="$3"

    # 获取前一份有效存档文件（排除当前 new_file）
    local prev_file
    prev_file=$(ls -1r "$dir"/*.json 2>/dev/null | grep -v "$(basename "$new_file")" | head -n 1)

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
        if [[ -n "$old_reg" && -n "$new_reg" && "$old_reg" != "$new_reg" ]]; then
            add_alert "WARNING" "$svc 地区从 [$old_reg] 变为 [$new_reg]" "$ip_ver"
        fi
    done

    # 预期地区检查
    if [[ -n "$EXPECTED_YOUTUBE_REGION" ]]; then
        local yt_reg
        yt_reg=$(jq -r ".Media.Youtube.Region // empty" "$new_file")
        if [[ -n "$yt_reg" && "$yt_reg" != "$EXPECTED_YOUTUBE_REGION" ]]; then
            add_alert "WARNING" "YouTube 地区 [$yt_reg] 不符合预期 [$EXPECTED_YOUTUBE_REGION]" "$ip_ver"
        fi
    fi
    if [[ -n "$EXPECTED_NETFLIX_REGION" ]]; then
        local nf_reg
        nf_reg=$(jq -r ".Media.Netflix.Region // empty" "$new_file")
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

    local old_usage new_usage
    old_usage=$(jq -r ".Type.Usage.IPinfo // empty" "$prev_file")
    new_usage=$(jq -r ".Type.Usage.IPinfo // empty" "$new_file")
    if [[ -n "$old_usage" && -n "$new_usage" && "$old_usage" != "$new_usage" ]]; then
        add_alert "WARNING" "IPinfo 使用类型属性变更为 [$new_usage] (原: $old_usage)" "$ip_ver"
    fi

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
    ensure_ip_script || return 1
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
        count_v4=$(ls -1 "$V4_DIR"/*.json 2>/dev/null | wc -l)
        if (( count_v4 > KEEP_MAX_ARCHIVES )); then
            local remove_count=$((count_v4 - KEEP_MAX_ARCHIVES))
            # shellcheck disable=SC2012
            ls -1t "$V4_DIR"/*.json | tail -n "$remove_count" | xargs rm -f
        fi
        count_v6=$(ls -1 "$V6_DIR"/*.json 2>/dev/null | wc -l)
        if (( count_v6 > KEEP_MAX_ARCHIVES )); then
            local remove_count=$((count_v6 - KEEP_MAX_ARCHIVES))
            # shellcheck disable=SC2012
            ls -1t "$V6_DIR"/*.json | tail -n "$remove_count" | xargs rm -f
        fi
    fi

    [[ "$quiet" == "false" ]] && echo -e "${C_GREEN}${C_BOLD}检测完成！${C_RESET}\n"
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

    # 如果选中的点多于 max_points，等间距抽样，且必须包含最后一个点
    if (( count > max_points && max_points > 0 )); then
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

# 选择时间跨度与 IP 协议
select_time_and_proto() {
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

    echo -e "\n${C_BOLD}选择 IP 协议版本:${C_RESET}"
    echo -e "  [4] IPv4 存档      [6] IPv6 存档"
    echo -ne "${C_CYAN}请输入选项 [默认 4]: ${C_RESET}"
    read -r proto_opt
    proto_opt="${proto_opt:-4}"

    if [[ "$proto_opt" == "6" ]]; then
        TARGET_DIR="$V6_DIR"
        TARGET_PROTO="IPv6"
    else
        TARGET_DIR="$V4_DIR"
        TARGET_PROTO="IPv4"
    fi
    SELECTED_RANGE="$range_opt"
    return 0
}

# ==============================================================================
# 模块 1: IP 类型属性变化 (show_ip_type)
# ==============================================================================
show_ip_type() {
    clear
    select_time_and_proto || return
    clear

    local files=()
    mapfile -t files < <(load_archive_files "$TARGET_DIR" "$SELECTED_RANGE" 8)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}未找到 $TARGET_PROTO 存档数据，请先执行一次检测 (选项 8)${C_RESET}\n"
        read -r -p "按回车键返回..."
        return
    fi

    print_module_header "📊 IP 类型属性变化分析 ($TARGET_PROTO)"

    # 提取各列时间表头
    local dates=()
    for f in "${files[@]}"; do
        dates+=("$(fmt_short_date "$(basename "$f" .json)")")
    done

    # 打印表头
    printf "%-13s" "数据库"
    for d in "${dates[@]}"; do
        printf "│ %-8s " "$d"
    done
    printf "│ %-10s\n" "历史稳定性"
    
    local divider_len=$(( 13 + ${#dates[@]} * 11 + 14 ))
    draw_divider "$divider_len"

    # 数据库键值清单
    local row_keys=("IPinfo" "ipregistry" "ipapi" "AbuseIPDB" "IP2LOCATION" "Info_Type")
    local row_names=("IPinfo" "ipregistry" "ipapi" "AbuseIPDB" "IP2LOCATION" "原生/广播")

    for idx in "${!row_keys[@]}"; do
        local rk="${row_keys[$idx]}"
        local rname="${row_names[$idx]}"
        printf "%-12s " "$rname"

        local vals=()
        for f in "${files[@]}"; do
            local val=""
            if [[ "$rk" == "Info_Type" ]]; then
                val=$(jq -r '.Info.Type // "null"' "$f" | sed 's/Geo-consistent/原生IP/;s/Geo-discrepant/广播IP/')
            else
                val=$(jq -r ".Type.Usage.$rk // \"null\"" "$f")
            fi
            [[ -z "$val" || "$val" == "null" ]] && val="无数据"
            vals+=("$val")
            
            # 着色渲染 (8字符宽度截断或展示)
            local display_val="${val:0:6}"
            if [[ "$val" =~ (ISP|家宽|Line ISP|原生IP) ]]; then
                printf "│ ${C_GREEN}%-7s${C_RESET} " "$display_val"
            elif [[ "$val" =~ (Data Center|Hosting|机房|广播IP|Transit) ]]; then
                printf "│ ${C_RED}%-7s${C_RESET} " "$display_val"
            elif [[ "$val" =~ (Business|商业|Corporate) ]]; then
                printf "│ ${C_YELLOW}%-7s${C_RESET} " "$display_val"
            else
                printf "│ ${C_GRAY}%-7s${C_RESET} " "$display_val"
            fi
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
            printf "│ ${C_YELLOW}⚠️ 存在变动${C_RESET}\n"
        fi
    done

    draw_divider "$divider_len"
    echo -e "${C_GRAY}图例: ${C_GREEN}家宽/原生(绿色)${C_GRAY} | ${C_YELLOW}商业(黄色)${C_GRAY} | ${C_RED}机房/广播(红色)${C_GRAY} | 灰色(未识别/无数据)${C_RESET}\n"
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 2: 风险评分趋势 (show_risk_score)
# ==============================================================================
render_bar() {
    local score="$1"
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

show_risk_score() {
    clear
    select_time_and_proto || return
    clear

    local files=()
    mapfile -t files < <(load_archive_files "$TARGET_DIR" "$SELECTED_RANGE" 6)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}未找到 $TARGET_PROTO 存档数据${C_RESET}\n"
        read -r -p "按回车键返回..."
        return
    fi

    print_module_header "📈 风险评分历史趋势图 ($TARGET_PROTO)"

    local dbs=("SCAMALYTICS" "IP2LOCATION" "AbuseIPDB" "IPQS" "ipapi" "DBIP")

    for db in "${dbs[@]}"; do
        echo -e "${C_BOLD}▶ 数据库: ${C_CYAN}$db${C_RESET} (满分 100)"
        for f in "${files[@]}"; do
            local dt
            dt=$(fmt_short_time "$(basename "$f" .json)")
            local score
            score=$(jq -r ".Score.$db // \"null\"" "$f")
            printf "  %-12s ▏ " "$dt"
            render_bar "$score"
        done
        echo ""
    done

    echo -e "${C_GRAY}说明: 评分越高风险越高。0-20 低风险 | 21-50 中风险 | 51-75 高风险 | 76+ 极高风险${C_RESET}\n"
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 3: 风险因子分析 (show_risk_factor)
# ==============================================================================
show_risk_factor() {
    clear
    select_time_and_proto || return
    clear

    local latest_file
    latest_file=$(get_latest_archive "$TARGET_DIR")
    if [[ -z "$latest_file" ]]; then
        echo -e "${C_YELLOW}未找到 $TARGET_PROTO 存档数据${C_RESET}\n"
        read -r -p "按回车键返回..."
        return
    fi

    print_module_header "🔬 风险因子综合矩阵 ($TARGET_PROTO)"

    echo -e "最新检测存档: ${C_YELLOW}$(basename "$latest_file")${C_RESET}\n"

    local engines=("IP2L" "ipapi" "ipreg" "IPQS" "SCAM" "ipdata" "IPinfo" "WHOIS" "DBIP")
    local full_engines=("IP2LOCATION" "ipapi" "ipregistry" "IPQS" "SCAMALYTICS" "ipdata" "IPinfo" "IPWHOIS" "DBIP")
    local factors=("Proxy" "Tor" "VPN" "Server" "Abuser" "Robot")

    # 打印表头
    printf "%-10s │ " "风险因子"
    for eng in "${engines[@]}"; do
        printf "%-7s " "$eng"
    done
    echo ""
    draw_divider 76

    for factor in "${factors[@]}"; do
        printf "%-10s │ " "$factor"
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

    draw_divider 76
    echo -e "图例说明: ${SYM_DOT_GREEN} 安全/未检出  ${SYM_MARK_RED} 风险检出(警告)  ${SYM_DOT_GRAY} 未检测/不支持\n"

    # 提供展开查看时间趋势选项
    echo -e "${C_BOLD}进一步查看各因子历史变化趋势?${C_RESET}"
    echo -e "  [1] Proxy 历史   [3] VPN 历史     [5] Abuser 历史"
    echo -e "  [2] Tor 历史     [4] Server 历史  [0] 跳过/返回"
    echo -ne "${C_CYAN}请选择: ${C_RESET}"
    read -r sub_opt

    local target_factor=""
    case "$sub_opt" in
        1) target_factor="Proxy" ;;
        2) target_factor="Tor" ;;
        3) target_factor="VPN" ;;
        4) target_factor="Server" ;;
        5) target_factor="Abuser" ;;
        *) return ;;
    esac

    clear
    echo -e "${C_BOLD}▶ 风险因子历史检出率: ${C_CYAN}$target_factor${C_RESET}\n"
    local hist_files=()
    mapfile -t hist_files < <(load_archive_files "$TARGET_DIR" "$SELECTED_RANGE" 10)

    for hf in "${hist_files[@]}"; do
        local dt
        dt=$(fmt_short_time "$(basename "$hf" .json)")
        local detected_count=0
        local total_tested=0
        for eng in "${full_engines[@]}"; do
            local v
            v=$(jq -r "if .Factor[\"$target_factor\"][\"$eng\"] != null then .Factor[\"$target_factor\"][\"$eng\"] else .Factor[\"$target_factor\"][\"WHOIS\"] end" "$hf")
            if [[ "$v" == "true" ]]; then
                detected_count=$((detected_count + 1))
                total_tested=$((total_tested + 1))
            elif [[ "$v" == "false" ]]; then
                total_tested=$((total_tested + 1))
            fi
        done

        printf "  %-12s ▏ " "$dt"
        if (( detected_count > 0 )); then
            echo -e "${C_RED}检出引擎: $detected_count / $total_tested${C_RESET} ${SYM_WARN}"
        else
            echo -e "${C_GREEN}全部通过 (0/$total_tested)${C_RESET} ${SYM_CHECK}"
        fi
    done
    echo ""
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 4: 流媒体与AI解锁 (show_media_unlock)
# ==============================================================================
show_media_unlock() {
    clear
    select_time_and_proto || return
    clear

    local files=()
    mapfile -t files < <(load_archive_files "$TARGET_DIR" "$SELECTED_RANGE" 10)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}未找到 $TARGET_PROTO 存档数据${C_RESET}\n"
        read -r -p "按回车键返回..."
        return
    fi

    print_module_header "🎬 流媒体与 AI 解锁历史监测 ($TARGET_PROTO)"

    local dates=()
    for f in "${files[@]}"; do
        dates+=("$(fmt_short_date "$(basename "$f" .json)")")
    done

    # 打印时间表头
    printf "%-16s │ " "服务名称"
    for d in "${dates[@]}"; do
        printf "%-5s " "$d"
    done
    echo ""
    local div_len=$(( 18 + ${#dates[@]} * 6 ))
    draw_divider "$div_len"

    local services=("TikTok" "DisneyPlus" "Netflix" "Youtube" "AmazonPrimeVideo" "Reddit" "ChatGPT")
    local display_names=("TikTok" "Disney+" "Netflix" "YouTube" "Amazon PV" "Reddit" "ChatGPT")

    # 统计数据
    local unlock_counts=()
    for ((s=0; s<${#services[@]}; s++)); do
        unlock_counts+=(0)
    done

    for idx in "${!services[@]}"; do
        local svc="${services[$idx]}"
        local sname="${display_names[$idx]}"
        printf "%-16s │ " "$sname"

        local success_in_row=0
        for f in "${files[@]}"; do
            local status
            status=$(jq -r ".Media.$svc.Status // \"null\"" "$f")
            local mtype
            mtype=$(jq -r ".Media.$svc.Type // \"\"" "$f")

            if [[ "$status" =~ (解锁|Yes|Native) ]]; then
                if [[ "$mtype" =~ (DNS|Proxy) ]]; then
                    printf "  %b   " "$SYM_DOT_ORANGE"
                else
                    printf "  %b   " "$SYM_DOT_GREEN"
                fi
                success_in_row=$((success_in_row + 1))
            elif [[ "$status" =~ (仅自制|Originals Only) ]]; then
                printf "  %b   " "$SYM_DOT_YELLOW"
            elif [[ "$status" =~ (失败|屏蔽|No|Blocked) ]]; then
                printf "  %b   " "$SYM_DOT_RED"
            else
                printf "  %b   " "$SYM_DOT_GRAY"
            fi
        done
        unlock_counts[$idx]=$success_in_row
        echo ""
    done

    draw_divider "$div_len"
    echo -e "图例说明: ${SYM_DOT_GREEN} 原生解锁  ${SYM_DOT_ORANGE} DNS/代理解锁  ${SYM_DOT_YELLOW} 仅自制剧  ${SYM_DOT_RED} 失败/屏蔽  ${SYM_DOT_GRAY} 未检测\n"

    # 地区变化追踪
    echo -e "${C_BOLD}📍 地区变化追踪 (Region Evolution):${C_RESET}"
    for idx in "${!services[@]}"; do
        local svc="${services[$idx]}"
        local sname="${display_names[$idx]}"
        local regions=()
        for f in "${files[@]}"; do
            local reg
            reg=$(jq -r ".Media.$svc.Region // \"--\"" "$f")
            [[ -z "$reg" || "$reg" == "null" ]] && reg="--"
            regions+=("$reg")
        done

        # 检查是否有变化
        local has_change=false
        local first_reg="${regions[0]}"
        for r in "${regions[@]}"; do
            if [[ "$r" != "$first_reg" ]]; then
                has_change=true
                break
            fi
        done

        printf "  %-12s : " "$sname"
        for r in "${regions[@]}"; do
            printf "%-4s " "$r"
        done
        if [[ "$has_change" == "true" ]]; then
            echo -e "  ${C_YELLOW}${SYM_WARN} 存在漂移${C_RESET}"
        else
            echo -e "  ${C_GREEN}${SYM_CHECK} 稳定${C_RESET}"
        fi
    done

    # 解锁率统计
    echo -e "\n${C_BOLD}📊 解锁率统计 (最近 ${#files[@]} 次检测):${C_RESET}"
    for idx in "${!services[@]}"; do
        local sname="${display_names[$idx]}"
        local count="${unlock_counts[$idx]}"
        local rate=0
        if [[ ${#files[@]} -gt 0 ]]; then
            rate=$(( count * 100 / ${#files[@]} ))
        fi
        printf "  • %-10s : %3d%%  " "$sname" "$rate"
        (( (idx + 1) % 3 == 0 )) && echo ""
    done
    echo -e "\n"
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 5: 邮局连通性 (show_mail_status)
# ==============================================================================
show_mail_status() {
    clear
    select_time_and_proto || return
    clear

    local files=()
    mapfile -t files < <(load_archive_files "$TARGET_DIR" "$SELECTED_RANGE" 8)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}未找到 $TARGET_PROTO 存档数据${C_RESET}\n"
        read -r -p "按回车键返回..."
        return
    fi

    print_module_header "📬 邮件服务器连通性矩阵 ($TARGET_PROTO)"

    # 最新 Port25 状态
    local latest_file="${files[-1]}"
    local p25_status
    p25_status=$(jq -r '.Mail.Port25' "$latest_file")
    if [[ "$p25_status" == "true" ]]; then
        echo -e "当前出站 25 端口 (Port 25): ${C_GREEN}${C_BOLD}✓ 开放 (可发送外网邮件)${C_RESET}"
    elif [[ "$p25_status" == "false" ]]; then
        echo -e "当前出站 25 端口 (Port 25): ${C_RED}${C_BOLD}✗ 拦截/关闭 (IDC通常默认封禁25)${C_RESET}"
    else
        echo -e "当前出站 25 端口 (Port 25): ${C_GRAY}未检出状态${C_RESET}"
    fi
    echo ""

    local dates=()
    for f in "${files[@]}"; do
        dates+=("$(fmt_short_date "$(basename "$f" .json)")")
    done

    printf "%-12s │ " "邮局名称"
    for d in "${dates[@]}"; do
        printf "%-6s " "$d"
    done
    echo ""
    local div_len=$(( 15 + ${#dates[@]} * 7 ))
    draw_divider "$div_len"

    local mail_services=("Gmail" "Outlook" "Yahoo" "Apple" "QQ" "163" "Sohu" "Sina" "MailRU" "AOL" "GMX" "MailCOM")
    for svc in "${mail_services[@]}"; do
        printf "%-12s │ " "$svc"
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

    draw_divider "$div_len"
    echo -e "图例说明: ${SYM_DOT_GREEN} 连通正常  ${SYM_DOT_RED} 连接失败/被拒  ${SYM_DOT_GRAY} 未检测\n"
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 6: 黑名单状态 (show_blacklist)
# ==============================================================================
show_blacklist() {
    clear
    select_time_and_proto || return
    clear

    local files=()
    mapfile -t files < <(load_archive_files "$TARGET_DIR" "$SELECTED_RANGE" 15)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}未找到 $TARGET_PROTO 存档数据${C_RESET}\n"
        read -r -p "按回车键返回..."
        return
    fi

    print_module_header "🚫 DNS 黑名单趋势与现状 ($TARGET_PROTO)"

    local latest_file="${files[-1]}"
    local total clean marked blacklisted
    total=$(jq -r '.Mail.DNSBlacklist.Total // 0' "$latest_file")
    clean=$(jq -r '.Mail.DNSBlacklist.Clean // 0' "$latest_file")
    marked=$(jq -r '.Mail.DNSBlacklist.Marked // 0' "$latest_file")
    blacklisted=$(jq -r '.Mail.DNSBlacklist.Blacklisted // 0' "$latest_file")

    echo -e "${C_BOLD}【最新检出概况】${C_RESET}"
    echo -e "  • 数据库总数: ${C_CYAN}$total${C_RESET}"
    echo -e "  • 干净通过数: ${C_GREEN}$clean${C_RESET}"
    echo -e "  • 被标记记录: ${C_YELLOW}$marked${C_RESET}"
    echo -e "  • 严重黑名单: ${C_RED}$blacklisted${C_RESET}"
    echo ""

    echo -e "${C_BOLD}【历史黑名单数量变化趋势】${C_RESET}"
    printf "  %-12s ▏ %-10s ▏ %-10s\n" "检测时间" "被标记(Mark)" "黑名单(Block)"
    printf "  ─────────────┼────────────┼─────────────\n"

    for f in "${files[@]}"; do
        local dt
        dt=$(fmt_short_time "$(basename "$f" .json)")
        local m b
        m=$(jq -r '.Mail.DNSBlacklist.Marked // 0' "$f")
        b=$(jq -r '.Mail.DNSBlacklist.Blacklisted // 0' "$f")
        
        local m_color="$C_GREEN"
        (( m > 0 )) && m_color="$C_YELLOW"
        local b_color="$C_GREEN"
        (( b > 0 )) && b_color="$C_RED"

        printf "  %-12s ▏ ${m_color}%-10s${C_RESET} ▏ ${b_color}%-10s${C_RESET}\n" "$dt" "$m" "$b"
    done
    echo ""
    read -r -p "按回车键返回主菜单..."
}

# ==============================================================================
# 模块 7: 设置定时检测 (setup_cron)
# ==============================================================================
setup_cron() {
    clear
    load_config
    print_module_header "⚙️  设置后台定时自动检测与存档"

    # 检测当前 crontab 中是否有 ipqa 任务
    local current_cron
    current_cron=$(crontab -l 2>/dev/null | grep -E "ipqa(\.sh)? --cron" | head -n 1 || true)

    if [[ -n "$current_cron" ]]; then
        echo -e "当前状态: ${C_GREEN}已启用自动检测${C_RESET}"
        echo -e "当前规则: ${C_YELLOW}$current_cron${C_RESET}\n"
    else
        echo -e "当前状态: ${C_GRAY}未配置定时检测${C_RESET}\n"
    fi

    echo -e "${C_BOLD}请选择定时检测周期:${C_RESET}"
    echo -e "  [1] 每 1 小时检测一次   (0 * * * *)"
    echo -e "  [2] 每 3 小时检测一次   (0 */3 * * *)"
    echo -e "  [3] 每 6 小时检测一次   (0 */6 * * *) [推荐]"
    echo -e "  [4] 每 12 小时检测一次  (0 */12 * * *)"
    echo -e "  [5] 每天凌晨 4 点检测   (0 4 * * *)"
    echo -e "  [6] 自定义 Cron 表达式"
    echo -e "  [7] 关闭/移除定时检测"
    echo -e "  [0] 返回主菜单"
    echo ""
    echo -ne "${C_CYAN}请输入选项: ${C_RESET}"
    read -r opt

    local new_cron_expr=""
    case "$opt" in
        1) new_cron_expr="0 * * * *" ;;
        2) new_cron_expr="0 */3 * * *" ;;
        3) new_cron_expr="0 */6 * * *" ;;
        4) new_cron_expr="0 */12 * * *" ;;
        5) new_cron_expr="0 4 * * *" ;;
        6)
            echo -ne "\n请输入 5 位 Cron 表达式 (如: 30 */4 * * *): "
            read -r new_cron_expr
            ;;
        7)
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
    echo -e "设定规则: ${C_CYAN}$new_cron_expr $script_path --cron${C_RESET}\n"
    log_msg "INFO" "配置定时任务: $new_cron_expr"
    read -r -p "按回车键返回..."
}

# ==============================================================================
# 模块 9: 查看原始存档 (view_archives)
# ==============================================================================
view_archives() {
    clear
    select_time_and_proto || return
    clear

    local files=()
    mapfile -t files < <(ls -1r "$TARGET_DIR"/*.json 2>/dev/null)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}暂无 $TARGET_PROTO 原始存档数据${C_RESET}\n"
        read -r -p "按回车键返回..."
        return
    fi

    print_module_header "📋 历史原始存档列表 ($TARGET_PROTO)"

    local max_show=15
    local show_count=$(( ${#files[@]} < max_show ? ${#files[@]} : max_show ))

    for ((i=0; i<show_count; i++)); do
        local f="${files[$i]}"
        local dt
        dt=$(fmt_timestamp "$(basename "$f" .json)")
        local sz
        sz=$(du -h "$f" | awk '{print $1}')
        local ip
        ip=$(jq -r '.Head.IP // "null"' "$f" 2>/dev/null)
        printf "  [%2d] %-20s (大小: %-4s, IP: %s)\n" "$((i + 1))" "$dt" "$sz" "$ip"
    done

    echo -e "\n输入编号查看详情 JSON，或输入 0 返回:"
    echo -ne "${C_CYAN}请选择: ${C_RESET}"
    read -r idx_opt

    if [[ "$idx_opt" =~ ^[0-9]+$ ]] && (( idx_opt >= 1 && idx_opt <= show_count )); then
        local chosen="${files[$((idx_opt - 1))]}"
        clear
        echo -e "${C_BOLD}文件路径: $chosen${C_RESET}\n"
        if command -v jq >/dev/null 2>&1; then
            jq . "$chosen" | head -n 80
            echo -e "\n${C_GRAY}(仅展示前 80 行，完整内容位于 $chosen)${C_RESET}"
        else
            cat "$chosen"
        fi
        echo ""
        read -r -p "按回车键返回..."
    fi
}

# ==============================================================================
# 模块 u: 更新 IPQuality 脚本 (update_script)
# ==============================================================================
update_script() {
    clear
    echo -e "${C_CYAN}${C_BOLD}正在从官方源更新 IPQuality 检测引擎...${C_RESET}\n"
    local tmp_file="$IPQA_HOME/ip.sh.tmp"
    if curl -sL https://IP.Check.Place -o "$tmp_file" || curl -sL https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh -o "$tmp_file"; then
        mv "$tmp_file" "$IP_SCRIPT"
        sed -i 's/\r$//' "$IP_SCRIPT" 2>/dev/null || true
        chmod +x "$IP_SCRIPT"
        local new_ver
        new_ver=$(grep -m 1 'script_version=' "$IP_SCRIPT" | cut -d '"' -f 2)
        echo -e "${C_GREEN}✔ 更新完成！当前版本: ${C_CYAN}${new_ver:-未知}${C_RESET}\n"
        log_msg "INFO" "更新 IPQuality 脚本成功，版本: $new_ver"
    else
        rm -f "$tmp_file"
        echo -e "${C_RED}❌ 下载失败，请检查网络连接${C_RESET}\n"
    fi
    read -r -p "按回车键返回..."
}

# ==============================================================================
# 模块 c: 清理历史数据 (cleanup_data)
# ==============================================================================
cleanup_data() {
    clear
    print_module_header "🗑️  清理与维护历史数据"

    local v4_cnt v6_cnt v4_size v6_size
    v4_cnt=$(ls -1 "$V4_DIR"/*.json 2>/dev/null | wc -l)
    v6_cnt=$(ls -1 "$V6_DIR"/*.json 2>/dev/null | wc -l)
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
                    total=$(ls -1 "$d"/*.json 2>/dev/null | wc -l)
                    if (( total > keep_num )); then
                        local diff=$((total - keep_num))
                        # shellcheck disable=SC2012
                        ls -1t "$d"/*.json | tail -n "$diff" | xargs rm -f
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
        ip_v4=$(jq -r '.Head.IP // "未知"' "$latest_v4")
        asn=$(jq -r '.Info.ASN // "--"' "$latest_v4")
        org=$(jq -r '.Info.Organization // "--"' "$latest_v4")
        local city country
        city=$(jq -r '.Info.City.Name // ""' "$latest_v4")
        country=$(jq -r '.Info.Region.Name // ""' "$latest_v4")
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
        ip_v6=$(jq -r '.Head.IP // "无"' "$latest_v6")
    fi

    # 统计数量与时间跨度
    local count_v4 count_v6
    count_v4=$(ls -1 "$V4_DIR"/*.json 2>/dev/null | wc -l)
    count_v6=$(ls -1 "$V6_DIR"/*.json 2>/dev/null | wc -l)

    local oldest_file time_span="--"
    oldest_file=$(ls -1 "$V4_DIR"/*.json 2>/dev/null | head -n 1)
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
        case "$schedule" in
            "0 * * * *") cron_status="已启用 (每小时)" ;;
            "0 */3 * * *") cron_status="已启用 (每 3 小时)" ;;
            "0 */6 * * *") cron_status="已启用 (每 6 小时)" ;;
            "0 */12 * * *") cron_status="已启用 (每 12 小时)" ;;
            "0 4 * * *") cron_status="已启用 (每天)" ;;
            *) cron_status="已启用 ($schedule)" ;;
        esac
        cron_colored="${C_GREEN}${cron_status}${C_RESET}"
    fi

    local asn_display="$asn"
    [[ "$asn" =~ ^[0-9]+$ ]] && asn_display="AS$asn"

    # 打印顶部 Panel
    echo -e "${C_CYAN}${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "   ${C_BOLD}${C_GREEN}🔍 IP 质量存档监测系统 (IPQA)${C_RESET}  ${C_GRAY}${IPQA_VERSION}${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    echo -e "  ${C_CYAN}📡 节点网络:${C_RESET} ${C_BOLD}${ip_v4}${C_RESET} (IPv4)  ${C_GRAY}│${C_RESET}  ${C_BOLD}${ip_v6}${C_RESET} (IPv6)"
    echo -e "  ${C_CYAN}🏢 归属信息:${C_RESET} ${asn_display}  ${C_GRAY}│${C_RESET}  📍 ${loc}"
    echo -e "  ${C_CYAN}⏰ 上次检测:${C_RESET} ${last_check}"
    echo -e "  ${C_CYAN}📦 历史存档:${C_RESET} IPv4: ${C_GREEN}${count_v4}${C_RESET} 份  ${C_GRAY}│${C_RESET}  IPv6: ${C_GREEN}${count_v6}${C_RESET} 份"
    echo -e "  ${C_CYAN}📅 时间跨度:${C_RESET} ${time_span}"
    echo -e "  ${C_CYAN}🔄 定时检测:${C_RESET} ${cron_colored}"
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
    echo -e "  ${C_BOLD}[1]${C_RESET} 📊 IP 类型属性变化       ${C_BOLD}[7]${C_RESET} ⚙️  配置定时任务"
    echo -e "  ${C_BOLD}[2]${C_RESET} 📈 风险评分趋势图        ${C_BOLD}[8]${C_RESET} 🔄 立即执行检测"
    echo -e "  ${C_BOLD}[3]${C_RESET} 🔬 风险因子综合矩阵      ${C_BOLD}[9]${C_RESET} 📋 查看原始存档"
    echo -e "  ${C_BOLD}[4]${C_RESET} 🎬 流媒体与AI解锁        ${C_BOLD}[u]${C_RESET} 🔃 更新检测核心"
    echo -e "  ${C_BOLD}[5]${C_RESET} 📬 邮局连通性状态        ${C_BOLD}[c]${C_RESET} 🗑️  清理历史数据"
    echo -e "  ${C_BOLD}[6]${C_RESET} 🚫 黑名单历史趋势        ${C_BOLD}[0]${C_RESET} 🚪 退出程序"
    echo -e "${C_GRAY}──────────────────────────────────────────────────────────────────────${C_RESET}"
}

main_loop() {
    check_dependencies
    load_config

    while true; do
        render_panel
        echo -ne "${C_CYAN}请输入指令: ${C_RESET}"
        read -r choice
        case "$choice" in
            1) show_ip_type ;;
            2) show_risk_score ;;
            3) show_risk_factor ;;
            4) show_media_unlock ;;
            5) show_mail_status ;;
            6) show_blacklist ;;
            7) setup_cron ;;
            8)
                clear
                run_check false
                read -r -p "检测完毕，按回车键返回主菜单..."
                ;;
            9) view_archives ;;
            u|U) update_script ;;
            c|C) cleanup_data ;;
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
        v4_cnt=$(ls -1 "$V4_DIR"/*.json 2>/dev/null | wc -l)
        v6_cnt=$(ls -1 "$V6_DIR"/*.json 2>/dev/null | wc -l)
        latest=$(get_latest_archive "$V4_DIR")
        echo "IPQA Status ($IPQA_VERSION)"
        echo "Archives: v4: $v4_cnt, v6: $v6_cnt"
        if [[ -n "$latest" ]]; then
            echo "Latest IP: $(jq -r '.Head.IP' "$latest")"
            echo "Latest Time: $(basename "$latest" .json)"
        fi
        ;;
    --help|-h)
        echo "IP Quality Archive (IPQA) $IPQA_VERSION"
        echo "用法: ipqa [选项]"
        echo ""
        echo "选项:"
        echo "  (无参数)      启动交互式终端图形界面 (TUI)"
        echo "  --check       立即执行一次检测并生成存档与告警"
        echo "  --cron        静默模式执行检测 (专用于 crontab 定时任务)"
        echo "  --status      查看当前存档与状态概况"
        echo "  --help, -h    显示本帮助信息"
        ;;
    *)
        main_loop
        ;;
esac
