#!/usr/bin/env bash
# ==============================================================================
# IP Quality Archive (IPQA) - IP 质量存档监测系统
# Description: 基于 IPQuality 的 IP 质量历史存档与终端可视化监测工具
# GitHub: https://github.com/xykt/IPQuality
# ==============================================================================

# 检查是否为危险或系统根路径 (M-04A: 全面覆盖系统与关键用户路径)
is_dangerous_path() {
    local target="$1"
    [[ -z "$target" ]] && return 0
    local canon
    if [[ -d "$target" ]]; then
        canon=$(cd "$target" 2>/dev/null && pwd -P || true)
    elif [[ -d "$(dirname "$target" 2>/dev/null)" ]]; then
        local p_dir base
        p_dir=$(cd "$(dirname "$target")" 2>/dev/null && pwd -P || true)
        base=$(basename "$target")
        canon="${p_dir%/}/$base"
    else
        canon="$target"
    fi
    [[ -z "$canon" ]] && canon="$target"
    canon="${canon%/}"
    [[ -z "$canon" ]] && canon="/"

    case "$canon" in
        /|/root|/home|/etc|/var|/usr|/bin|/sbin|/lib|/lib64|/boot|/dev|/sys|/proc|/tmp|/run|/opt|/srv|/mnt|/media|"$HOME")
            return 0
            ;;
        /usr/*|/var/*|/etc/*|/opt/*|/home/*)
            case "$canon" in
                /usr/local|/usr/local/bin|/usr/local/sbin|/usr/local/lib|/usr/local/share|/usr/local/include|/usr/bin|/usr/sbin|/usr/lib|/usr/share)
                    return 0
                    ;;
                /var/lib|/var/log|/var/run|/var/tmp|/var/spool|/var/cache|/var/backups)
                    return 0
                    ;;
                /etc/cron*|/etc/systemd*|/etc/default|/etc/network*|/etc/ssl)
                    return 0
                    ;;
                /opt/local|/opt/bin)
                    return 0
                    ;;
            esac
            ;;
    esac

    # 保护关键用户目录
    if [[ -n "$HOME" ]]; then
        local h="${HOME%/}"
        case "$canon" in
            "$h"|"$h/.local"|"$h/.local/bin"|"$h/.config"|"$h/bin"|"$h/.ssh"|"$h/Desktop"|"$h/Documents"|"$h/Downloads")
                return 0
                ;;
        esac
    fi

    # 拦截一级根目录 (如 /data, /storage)
    if [[ "$canon" =~ ^/[^/]+$ ]]; then
        return 0
    fi
    return 1
}

# 基础环境与路径配置
IPQA_HOME="${IPQA_DIR:-$HOME/.ipqa}"

# M-04B: 在任何 mkdir 或 chmod 之前必须先行进行危险路径判定
if is_dangerous_path "$IPQA_HOME"; then
    echo "错误: IPQA 目标路径 '$IPQA_HOME' 为受保护系统路径或危险路径，已拒绝操作。" >&2
    exit 1
fi

CONFIG_FILE="$IPQA_HOME/config.sh"
DATA_DIR="$IPQA_HOME/data"
V4_DIR="$DATA_DIR/v4"
V6_DIR="$DATA_DIR/v6"
LOGS_DIR="$IPQA_HOME/logs"
ALERT_LOG="$DATA_DIR/alerts.log"
IP_SCRIPT="$IPQA_HOME/ip.sh"
LOG_FILE="$LOGS_DIR/ipqa.log"

# 创建运行目录并设置安全权限 (S-10)
mkdir -p "$V4_DIR" "$V6_DIR" "$LOGS_DIR"
chmod 700 "$IPQA_HOME" "$DATA_DIR" "$V4_DIR" "$V6_DIR" "$LOGS_DIR" 2>/dev/null || true
[[ -f "$CONFIG_FILE" ]] && chmod 600 "$CONFIG_FILE" 2>/dev/null || true

# 统一定义当前 Bash 执行进程身份 (解决 subshell 与后台任务 PID 身份一致性)
get_current_pid() {
    if [[ -n "${1:-}" ]]; then
        printf -v "$1" '%s' "${BASHPID:-$$}"
    else
        printf '%s\n' "${BASHPID:-$$}"
    fi
}

# 进程并发锁控制 (M-08A, M-08B: 统一主锁、原子恢复、所有者校验与可重入嵌套深度支持)
acquire_lock() {
    local lock_name="${1:-main}"
    local my_pid
    get_current_pid my_pid
    local depth_var="_LOCK_DEPTH_${lock_name}_${my_pid}"
    local current_depth="${!depth_var:-0}"

    if (( current_depth > 0 )); then
        eval "${depth_var}=\$(( current_depth + 1 ))"
        return 0
    fi

    local lock_dir="$IPQA_HOME/.lock_${lock_name}"
    local pid_file="$lock_dir/pid"

    # 1. 尝试原子创建锁目录
    if mkdir "$lock_dir" 2>/dev/null; then
        echo "$my_pid" > "$pid_file" 2>/dev/null || true
        eval "${depth_var}=1"
        return 0
    fi

    # 2. 如果锁已存在，检查是否由当前进程持有 (可重入)
    if [[ -f "$pid_file" ]]; then
        local current_lock_pid
        current_lock_pid=$(cat "$pid_file" 2>/dev/null || true)
        if [[ "$current_lock_pid" == "$my_pid" ]]; then
            eval "${depth_var}=1"
            return 0
        fi

        # 3. 检查持有者是否已死亡 (stale-lock 原子恢复 M-08B)
        if [[ -n "$current_lock_pid" ]] && ! kill -0 "$current_lock_pid" 2>/dev/null; then
            local stale_mv="$IPQA_HOME/.lock_stale_${lock_name}_${my_pid}.$RANDOM"
            if mv "$lock_dir" "$stale_mv" 2>/dev/null; then
                rm -rf "$stale_mv" 2>/dev/null || true
                if mkdir "$lock_dir" 2>/dev/null; then
                    echo "$my_pid" > "$pid_file" 2>/dev/null || true
                    eval "${depth_var}=1"
                    return 0
                fi
            fi
        fi
    fi

    return 1
}

release_lock() {
    local lock_name="${1:-main}"
    local force="${2:-false}"
    local my_pid
    get_current_pid my_pid
    local depth_var="_LOCK_DEPTH_${lock_name}_${my_pid}"
    local current_depth="${!depth_var:-0}"

    if [[ "$force" != "true" ]] && (( current_depth > 1 )); then
        eval "${depth_var}=\$(( current_depth - 1 ))"
        return 0
    fi

    eval "${depth_var}=0"
    local lock_dir="$IPQA_HOME/.lock_${lock_name}"
    local pid_file="$lock_dir/pid"

    if [[ -f "$pid_file" ]]; then
        local lock_pid
        lock_pid=$(cat "$pid_file" 2>/dev/null || true)
        # 仅允许持锁者清理自己的锁 (M-08B)
        if [[ "$lock_pid" == "$my_pid" || "$force" == "true" ]]; then
            rm -rf "$lock_dir" 2>/dev/null || true
        fi
    elif [[ -d "$lock_dir" ]]; then
        rm -rf "$lock_dir" 2>/dev/null || true
    fi
}

cleanup_main_lock() {
    release_lock "main"
}

handle_interrupt() {
    cleanup_main_lock
    exit 130
}

handle_term() {
    cleanup_main_lock
    exit 143
}

# 日志自动轮转控制 (S-16, 单文件上限 5MB)
rotate_logs_if_needed() {
    local max_size=$(( 5 * 1024 * 1024 ))
    local log_f
    for log_f in "$LOG_FILE" "$ALERT_LOG"; do
        if [[ -f "$log_f" ]]; then
            local f_size
            f_size=$(wc -c < "$log_f" 2>/dev/null || echo 0)
            if (( f_size > max_size )); then
                rm -f "${log_f}.2" 2>/dev/null || true
                [[ -f "${log_f}.1" ]] && mv "${log_f}.1" "${log_f}.2" 2>/dev/null || true
                mv "$log_f" "${log_f}.1" 2>/dev/null || true
                touch "$log_f" 2>/dev/null || true
                chmod 600 "$log_f" 2>/dev/null || true
            fi
        fi
    done
}

# ANSI 颜色与文字样式定义 (Q-02B: 清理未使用变量)
C_RESET="\033[0m"
C_BOLD="\033[1m"

C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_MAGENTA="\033[35m"
C_CYAN="\033[36m"
C_WHITE="\033[37m"
C_GRAY="\033[90m"
C_ORANGE="\033[38;5;208m"

BG_RED="\033[41m"
BG_GREEN="\033[42m"
BG_YELLOW="\033[43m"

# 符号定义
SYM_DOT_GREEN="${C_GREEN}●${C_RESET}"
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
# 配置管理 (S-04, S-05: 安全键值解析与转义，避免执行任意代码)
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
    AUTO_UPDATE_SCRIPT="true"

    local parsed_script_update=""
    local parsed_legacy_update=""

    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='=' read -r raw_key raw_val || [[ -n "$raw_key" ]]; do
            raw_key=$(echo "$raw_key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [[ -z "$raw_key" || "$raw_key" =~ ^# ]] && continue
            raw_val=$(echo "$raw_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            raw_val="${raw_val#\"}"
            raw_val="${raw_val%\"}"
            raw_val="${raw_val#\'}"
            raw_val="${raw_val%\'}"
            case "$raw_key" in
                CHECK_INTERVAL_HOURS) [[ "$raw_val" =~ ^[0-9]+$ ]] && CHECK_INTERVAL_HOURS="$raw_val" ;;
                HAS_V6) [[ "$raw_val" =~ ^(auto|true|false)$ ]] && HAS_V6="$raw_val" ;;
                V6_CHECK_COUNT) [[ "$raw_val" =~ ^[0-9]+$ ]] && V6_CHECK_COUNT="$raw_val" ;;
                V6_PROBE_INTERVAL) [[ "$raw_val" =~ ^[0-9]+$ ]] && V6_PROBE_INTERVAL="$raw_val" ;;
                SCORE_DIFF_THRESHOLD) [[ "$raw_val" =~ ^[0-9]+$ ]] && SCORE_DIFF_THRESHOLD="$raw_val" ;;
                EXPECTED_YOUTUBE_REGION) EXPECTED_YOUTUBE_REGION=$(echo "$raw_val" | tr -cd 'a-zA-Z0-9_-') ;;
                EXPECTED_NETFLIX_REGION) EXPECTED_NETFLIX_REGION=$(echo "$raw_val" | tr -cd 'a-zA-Z0-9_-') ;;
                KEEP_MAX_ARCHIVES) [[ "$raw_val" =~ ^[0-9]+$ ]] && KEEP_MAX_ARCHIVES="$raw_val" ;;
                AUTO_UPDATE_SCRIPT) [[ "$raw_val" =~ ^(true|false|on|off|1|0|enable|disable|disabled)$ ]] && parsed_script_update="$raw_val" ;;
                AUTO_UPDATE) [[ "$raw_val" =~ ^(true|false|on|off|1|0|enable|disable|disabled)$ ]] && parsed_legacy_update="$raw_val" ;;
            esac
        done < "$CONFIG_FILE"
        if [[ -n "$parsed_script_update" ]]; then
            AUTO_UPDATE_SCRIPT="$parsed_script_update"
        elif [[ -n "$parsed_legacy_update" ]]; then
            AUTO_UPDATE_SCRIPT="$parsed_legacy_update"
        else
            AUTO_UPDATE_SCRIPT="true"
        fi
    else
        save_config
    fi
}

save_config() {
    local safe_v6 safe_yt safe_nf safe_auto
    safe_v6=$(echo "$HAS_V6" | tr -cd 'a-zA-Z0-9_-')
    safe_yt=$(echo "$EXPECTED_YOUTUBE_REGION" | tr -cd 'a-zA-Z0-9_-')
    safe_nf=$(echo "$EXPECTED_NETFLIX_REGION" | tr -cd 'a-zA-Z0-9_-')
    safe_auto=$(echo "$AUTO_UPDATE_SCRIPT" | tr -cd 'a-zA-Z0-9_-')
    local safe_check_int safe_v6_cnt safe_v6_probe safe_score_diff safe_keep
    safe_check_int=$(( 10#${CHECK_INTERVAL_HOURS:-24} ))
    safe_v6_cnt=$(( 10#${V6_CHECK_COUNT:-0} ))
    safe_v6_probe=$(( 10#${V6_PROBE_INTERVAL:-10} ))
    safe_score_diff=$(( 10#${SCORE_DIFF_THRESHOLD:-10} ))
    safe_keep=$(( 10#${KEEP_MAX_ARCHIVES:-0} ))

    cat <<EOF > "$CONFIG_FILE"
# IPQA Configuration
CHECK_INTERVAL_HOURS=$safe_check_int
HAS_V6="${safe_v6:-auto}"
V6_CHECK_COUNT=$safe_v6_cnt
V6_PROBE_INTERVAL=$safe_v6_probe
SCORE_DIFF_THRESHOLD=$safe_score_diff
EXPECTED_YOUTUBE_REGION="$safe_yt"
EXPECTED_NETFLIX_REGION="$safe_nf"
KEEP_MAX_ARCHIVES=$safe_keep
AUTO_UPDATE_SCRIPT="${safe_auto:-true}"
EOF
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
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
    case "$val" in
        "Data Center/Web Hosting/Transit"|"Web Hosting") val="Hosting" ;;
        "Fixed Line ISP") val="Line ISP" ;;
        "Content Delivery Network") val="CDN" ;;
        "University/College/School") val="Education" ;;
    esac
    local bg="$BG_YELLOW"
    if [[ "$val" =~ (机房|Hosting|Data Center|CDN|Transit|Datacenter) ]]; then
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
    local bj_epoch local_h_calc
    bj_epoch=$(TZ="Asia/Shanghai" date -d "today 04:00" +%s 2>/dev/null || echo 0)
    if (( bj_epoch > 0 )); then
        local_h_calc=$(date -d "@$bj_epoch" +%H 2>/dev/null | sed 's/^0//')
        if [[ -n "$local_h_calc" && "$local_h_calc" =~ ^[0-9]+$ ]]; then
            echo "$local_h_calc"
            return
        fi
    fi
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
    echo "$(( mod_sec / 3600 ))"
}

# 自动计算服务器当前时区下对应“北京时间 00 分”的本地分钟数 (0-59) (M-19)
get_beijing_00_local_minute() {
    local z
    z=$(date +%z 2>/dev/null || echo "+0800")
    local sign="${z:0:1}"
    local zm="${z:3:2}"
    local m=$(( 10#${zm:-0} ))
    if [[ "$sign" == "-" ]]; then
        m=$(( (60 - (m % 60)) % 60 ))
    else
        m=$(( m % 60 ))
    fi
    printf "%02d" "$m"
}

# 提取 Cron 任务的友好展示名称 (UI-01, N-01)
get_cron_friendly_name() {
    local cron_str="$1"
    [[ -z "$cron_str" ]] && echo "未配置" && return

    local local_h
    local_h=$(get_beijing_4am_local_hour)

    if [[ "$cron_str" =~ Asia/Shanghai && ( "$cron_str" =~ 04:00 || "$cron_str" =~ \+.*04 ) ]]; then
        if [[ "$cron_str" =~ (%|\\%|\/)[[:space:]]*3 ]]; then
            echo "每 3 天一次 (北京 04:00)"
        elif [[ "$cron_str" =~ (%u|\\%u)[[:space:]]*7 ]]; then
            echo "每 7 天一次 (北京 04:00)"
        else
            echo "每天 (北京 04:00)"
        fi
    elif [[ "$cron_str" =~ ^[0-9]+[[:space:]]+${local_h}[[:space:]]+\*[[:space:]]+\*[[:space:]]+\* ]]; then
        echo "每天 (本机固定 $local_h:00)"
    elif [[ "$cron_str" =~ ^[0-9]+[[:space:]]+${local_h}[[:space:]]+\*/3 ]]; then
        echo "每 3 天 (本机固定 $local_h:00)"
    elif [[ "$cron_str" =~ ^[0-9]+[[:space:]]+${local_h}[[:space:]]+\*/7 ]]; then
        echo "每 7 天 (本机固定 $local_h:00)"
    else
        local schedule
        schedule=$(echo "$cron_str" | awk '{print $1,$2,$3,$4,$5}')
        echo "${schedule:-自定义规则}"
    fi
}

log_msg() {
    local level="$1"
    shift
    local msg="$*"
    rotate_logs_if_needed
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
        echo -e "请先安装: ${C_YELLOW}apt-get install -y ${missing[*]}${C_RESET}"
        exit 1
    fi
}

patch_ip_script() {
    local target="${1:-$IP_SCRIPT}"
    [[ ! -f "$target" ]] && return 1

    # 1. 修复上游 ip.sh 未将 IP2Location 公司类型写入 JSON 的 bug
    if ! grep -q 'Company: { IP2LOCATION' "$target" 2>/dev/null; then
        sed -i '/Company: { ipapi:/a \type_updates+=".Type |= . * { Company: { IP2LOCATION: \\"$(clean_ansi "${ip2location[scomtype]:-null}")\\" } } | "' "$target" 2>/dev/null || true
    fi

    # 2. 修复上游 ip.sh 在 Check_DNS_3 中因缺少 dig 或超时将原生解锁误判为 DNS 解锁的 bug
    if grep -q 'if \[ "$resultdnstext" == "0" \];then' "$target" 2>/dev/null; then
        sed -i 's/if \[ "$resultdnstext" == "0" \];then/if [ "$resultdnstext" == "0" ] || [ -z "$resultdnstext" ];then/g' "$target" 2>/dev/null || true
    fi

    # 3. 修复上游 ip.sh 在 Check_DNS_IP 中因未解析到 IP 将原生解锁误判为 DNS 解锁的 bug
    sed -i -e '/function Check_DNS_IP/,/function Check_DNS_1/{ /else/{ n; s/echo 0/echo 1/; } }' "$target" 2>/dev/null || true

    # 4. 修复上游 ip.sh 中 Youtube 地区硬编码内嵌 Font_Red/Font_Green 导致 JSON 存储 1mCN2m 等 ANSI 残渣的 bug
    sed -i 's/youtube\[uregion\]="  \$Font_Red\[CN\]\$Font_Green   "/youtube[uregion]="  [CN]   "/g' "$target" 2>/dev/null || true

    # 5. 修复上游 ip.sh 中 db_dbip 因单引号字面量 local tmpcurlarg='$CurlARG' 导致未能正确继承 -4/-6 参数的 bug
    sed -i "s/local tmpcurlarg='\$CurlARG'/local tmpcurlarg=\"\$CurlARG\"/g" "$target" 2>/dev/null || true

    # 6. 修复上游 ip.sh 中 Amazon Prime Video 地区提取贪婪匹配导致 JS 乱码与排版坍塌的 bug
    if grep -q "currentTerritory//'|cut -f3" "$target" 2>/dev/null; then
        sed -i 's@local result=\$(echo \$tmpresult|grep .*currentTerritory.*head -n 1)@local result=$(echo $tmpresult|grep -o -E '\''"currentTerritory":\\s*"[A-Za-z]{2}"'\''|head -n 1|cut -d"\\"" -f4)@g' "$target" 2>/dev/null || true
    fi

    return 0
}

ensure_ip_script() {
    if [[ -f "$IP_SCRIPT" ]]; then
        return 0
    fi

    echo -e "${C_CYAN}正在初始化并下载 IPQuality 上游脚本缓存...${C_RESET}"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local tmp_ip="$IPQA_HOME/.ip.sh.tmp.$.$RANDOM"
    local source_found=false

    if [[ -f "$script_dir/ip.sh" ]]; then
        cp "$script_dir/ip.sh" "$tmp_ip" 2>/dev/null && source_found=true
    elif [[ -f "$script_dir/IP-Quality-Detection-Project/ip.sh" ]]; then
        cp "$script_dir/IP-Quality-Detection-Project/ip.sh" "$tmp_ip" 2>/dev/null && source_found=true
    else
        if curl -fsSL --connect-timeout 8 --max-time 30 https://IP.Check.Place -o "$tmp_ip" 2>/dev/null || curl -fsSL --connect-timeout 8 --max-time 30 https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh -o "$tmp_ip" 2>/dev/null; then
            source_found=true
        fi
    fi

    if [[ "$source_found" == "true" && -f "$tmp_ip" ]]; then
        sed -i 's/\r$//' "$tmp_ip" 2>/dev/null || true
        local sz
        sz=$(wc -c < "$tmp_ip" 2>/dev/null || echo 0)
        if (( sz > 1000 )) && bash -n "$tmp_ip" 2>/dev/null && grep -qE "IPQuality|Check_DNS|script_version" "$tmp_ip" 2>/dev/null; then
            if patch_ip_script "$tmp_ip" && bash -n "$tmp_ip" 2>/dev/null; then
                chmod 755 "$tmp_ip" 2>/dev/null || chmod +x "$tmp_ip" 2>/dev/null || true
                mv -f "$tmp_ip" "$IP_SCRIPT"
            else
                rm -f "$tmp_ip" 2>/dev/null || true
                echo -e "${C_RED}错误: IPQuality 脚本 patch 或语法校验失败${C_RESET}"
                return 1
            fi
        else
            rm -f "$tmp_ip" 2>/dev/null || true
        fi
    else
        rm -f "$tmp_ip" 2>/dev/null || true
    fi

    if [[ ! -f "$IP_SCRIPT" ]]; then
        echo -e "${C_RED}错误: 无法获取有效的 IPQuality 脚本缓存 ($IP_SCRIPT)${C_RESET}"
        return 1
    fi
    return 0
}

# 每天自动静默更新 IPQA 脚本及 IPQuality 检测核心 (静默执行)
auto_update_if_needed() {
    local quiet="${1:-true}"
    [[ -z "$AUTO_UPDATE_SCRIPT" ]] && load_config

    # M-08A: 获取主执行互斥锁，避免与正在运行的检测或更新发生写写冲突
    if ! acquire_lock "main"; then
        [[ "$quiet" == "false" ]] && echo -e "${C_YELLOW}⚠ 正在进行其他检测或更新任务，跳过本次自动更新${C_RESET}"
        return 0
    fi
    local my_pid
    get_current_pid my_pid
    local depth_var="_LOCK_DEPTH_main_${my_pid}"
    local is_outer_lock=false
    [[ "${!depth_var:-0}" -eq 1 ]] && is_outer_lock=true
    if [[ "$is_outer_lock" == "true" ]]; then
        trap cleanup_main_lock EXIT
        trap handle_interrupt INT
        trap handle_term TERM
    fi

    # M-09: 核心与主脚本更新时间戳完全独立管理
    local stamp_core="$IPQA_HOME/.last_core_update"
    local stamp_script="$IPQA_HOME/.last_script_update"
    local legacy_stamp="$IPQA_HOME/.last_auto_update"
    if [[ -f "$legacy_stamp" ]]; then
        [[ ! -f "$stamp_core" ]] && cp "$legacy_stamp" "$stamp_core" 2>/dev/null || true
        [[ ! -f "$stamp_script" ]] && cp "$legacy_stamp" "$stamp_script" 2>/dev/null || true
        rm -f "$legacy_stamp" 2>/dev/null || true
    fi

    local now_sec
    now_sec=$(date +%s)
    local last_core=0
    [[ -f "$stamp_core" ]] && last_core=$(cat "$stamp_core" 2>/dev/null || echo 0)
    local last_script=0
    [[ -f "$stamp_script" ]] && last_script=$(cat "$stamp_script" 2>/dev/null || echo 0)

    local core_due=false
    local script_due=false
    if [[ ! -f "$IP_SCRIPT" ]] || (( now_sec - last_core >= 86400 )); then
        core_due=true
    fi
    if [[ ! -f "$IPQA_HOME/ipqa.sh" ]] || (( now_sec - last_script >= 86400 )); then
        script_due=true
    fi

    if [[ "$core_due" == "true" || "$script_due" == "true" ]]; then
        [[ "$quiet" == "false" ]] && echo -e "${C_CYAN}🔄 距上次更新已超 1 天，正在检查更新检测核心与脚本...${C_RESET}"

        # 1. 自动同步 IPQuality 检测核心 (ip.sh) (M-05, M-08A, M-09, S-01, S-13)
        if [[ "$core_due" == "true" ]]; then
            local tmp_ip="$IPQA_HOME/.ip.sh.tmp.$$.$RANDOM"
            # S-13: 优先进行轻量化 HEAD / Range 版本比对
            local remote_ver=""
            remote_ver=$(curl -fsSL --connect-timeout 5 --max-time 10 -r 0-1024 https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh 2>/dev/null | grep -m 1 'script_version=' | cut -d '"' -f 2 || true)
            local local_ver=""
            [[ -f "$IP_SCRIPT" ]] && local_ver=$(grep -m 1 'script_version=' "$IP_SCRIPT" 2>/dev/null | cut -d '"' -f 2 || true)

            if [[ -n "$remote_ver" && -n "$local_ver" && "$remote_ver" == "$local_ver" ]]; then
                echo "$now_sec" > "$stamp_core"
                log_msg "INFO" "IPQuality 检测核心版本已是最新 ($local_ver)，无需重复下载"
            else
                if curl -fsSL --connect-timeout 8 --max-time 30 https://IP.Check.Place -o "$tmp_ip" 2>/dev/null || curl -fsSL --connect-timeout 8 --max-time 30 https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh -o "$tmp_ip" 2>/dev/null; then
                    sed -i 's/\r$//' "$tmp_ip" 2>/dev/null || true
                    # S-01: 校验大小、语法完整性及项目特征
                    if [[ $(wc -c < "$tmp_ip" 2>/dev/null || echo 0) -gt 3000 ]] && bash -n "$tmp_ip" 2>/dev/null && grep -qE "IPQuality|Check_DNS|script_version" "$tmp_ip" 2>/dev/null; then
                        if patch_ip_script "$tmp_ip" && bash -n "$tmp_ip" 2>/dev/null; then
                            chmod 755 "$tmp_ip" 2>/dev/null || chmod +x "$tmp_ip" 2>/dev/null || true
                            if [[ -f "$IP_SCRIPT" ]] && cmp -s "$tmp_ip" "$IP_SCRIPT"; then
                                rm -f "$tmp_ip"
                                log_msg "INFO" "IPQuality 检测核心已是最新版本"
                            else
                                mv -f "$tmp_ip" "$IP_SCRIPT"
                                local new_ver
                                new_ver=$(grep -m 1 'script_version=' "$IP_SCRIPT" 2>/dev/null | cut -d '"' -f 2)
                                log_msg "INFO" "检测核心自动更新成功，版本: ${new_ver:-未知}"
                            fi
                            echo "$now_sec" > "$stamp_core"
                        else
                            rm -f "$tmp_ip"
                            log_msg "WARN" "检测核心 patch 规则应用或语法校验失败，保留本地核心"
                        fi
                    else
                        rm -f "$tmp_ip"
                        log_msg "WARN" "自动更新检测核心完整性或语法校验失败，保留本地核心"
                    fi
                else
                    rm -f "$tmp_ip"
                    log_msg "WARN" "自动更新检测核心网络超时，继续使用本地核心"
                fi
            fi
        fi

        # 2. 自动同步 IPQA 脚本 (ipqa.sh) (可受 AUTO_UPDATE_SCRIPT 控制)
        if [[ "$script_due" == "true" ]]; then
            if [[ "$OVERRIDE_AUTO_UPDATE_SCRIPT" == "false" || "$AUTO_UPDATE_SCRIPT" == "false" || "$AUTO_UPDATE_SCRIPT" == "off" || "$AUTO_UPDATE_SCRIPT" == "0" || "$AUTO_UPDATE_SCRIPT" == "disable" || "$AUTO_UPDATE_SCRIPT" == "disabled" ]]; then
                [[ "$quiet" == "false" ]] && echo -e "${C_GRAY}ℹ️  IPQA 脚本自动更新已禁用，跳过脚本自我同步${C_RESET}"
                echo "$now_sec" > "$stamp_script"
            else
                local tmp_ipqa="$IPQA_HOME/.ipqa.sh.tmp.$$.$RANDOM"
                if curl -fsSL --connect-timeout 8 --max-time 30 -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/ipqa.sh?t=$(date +%s)" -o "$tmp_ipqa" 2>/dev/null; then
                    sed -i 's/\r$//' "$tmp_ipqa" 2>/dev/null || true
                    if [[ $(wc -c < "$tmp_ipqa" 2>/dev/null || echo 0) -gt 10000 ]] && grep -qE "IP-Quality-Archive|IPQA" "$tmp_ipqa" 2>/dev/null; then
                        if [[ -f "$IPQA_HOME/ipqa.sh" ]] && cmp -s "$tmp_ipqa" "$IPQA_HOME/ipqa.sh"; then
                            rm -f "$tmp_ipqa"
                            log_msg "INFO" "IPQA 脚本已是最新版本"
                        else
                            if bash -n "$tmp_ipqa" 2>/dev/null; then
                                mv "$tmp_ipqa" "$IPQA_HOME/ipqa.sh"
                                chmod 755 "$IPQA_HOME/ipqa.sh"
                                log_msg "INFO" "自动静默更新 IPQA 脚本成功"
                            else
                                rm -f "$tmp_ipqa"
                                log_msg "WARN" "自动更新 IPQA 脚本语法校验失败，保留当前脚本"
                            fi
                        fi
                        echo "$now_sec" > "$stamp_script"
                    else
                        rm -f "$tmp_ipqa"
                        log_msg "WARN" "自动更新 IPQA 脚本校验失败，保留当前脚本"
                    fi
                else
                    rm -f "$tmp_ipqa"
                    log_msg "WARN" "自动更新 IPQA 脚本网络超时，继续使用当前脚本"
                fi
            fi
        fi

        [[ "$quiet" == "false" ]] && echo -e "${C_GREEN}✔ IPQA 自动更新检查完成${C_RESET}\n"
    fi

    cleanup_main_lock
    if [[ "$is_outer_lock" == "true" ]]; then
        trap - EXIT INT TERM
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

# 获取最新一份有效 JSON (S-03)
get_latest_archive() {
    local dir="$1"
    [[ ! -d "$dir" ]] && return 1
    local f
    while read -r f; do
        if [[ -n "$f" && -f "$f" ]] && validate_json "$f"; then
            echo "$f"
            return 0
        fi
    done < <(find "$dir" -maxdepth 1 -name '*.json' 2>/dev/null | sort -r)
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
    # 过滤 JS/JSON 异常残渣 (如包含 Minerva / Program / { / } 等)
    if [[ "$raw" == *"{"* || "$raw" == *"}"* || "$raw" == *"Minerva"* || "$raw" == *"Program"* ]]; then
        echo "--"
        return
    fi
    local cleaned
    cleaned=$(echo "$raw" | sed -r -e 's/\x1b\[?[0-9;]*m?//g' -e 's/\\033\[?[0-9;]*m?//g' -e 's/[0-9]+m//g')
    if [[ "$cleaned" =~ \[([A-Za-z]{2})\] ]]; then
        echo "${BASH_REMATCH[1]^^}"
        return
    fi
    if [[ "$cleaned" =~ ^[[:space:]]*([A-Za-z]{2})[[:space:]]*$ ]]; then
        echo "${BASH_REMATCH[1]^^}"
        return
    fi
    # Q-01: 严格匹配独立/边界两个大写字母地区代码 (如 US-CA 中的 US，或 [HK])，避免从 Global/Failed 等词汇中误提取
    if [[ "$cleaned" =~ (^|[^A-Za-z])([A-Z]{2})([^A-Za-z]|$) ]]; then
        echo "${BASH_REMATCH[2]^^}"
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

    # S-17: 彻底过滤日志与终端控制字符注入 (OSC, CSI, ESC 序列及控制字符)
    level=$(echo "$level" | tr -cd 'A-Z')
    ip_ver=$(echo "$ip_ver" | tr -cd 'a-zA-Z0-9')
    # 1. 过滤 OSC 序列: ESC ] ... (BEL 或 ESC \)
    msg=$(printf '%s' "$msg" | sed -E $'s/\x1B\\][^\x07\x1B]*(\x07|\x1B\\\\)//g')
    # 2. 过滤所有 CSI 序列: ESC [ ... [a-zA-Z]
    msg=$(printf '%s' "$msg" | sed -E $'s/\x1B\\[[0-9;?]*[a-zA-Z]//g')
    # 3. 过滤其他独立 ESC 序列
    msg=$(printf '%s' "$msg" | sed -E $'s/\x1B[^a-zA-Z0-9]//g')
    # 4. 过滤其他不可打印控制字符 (\x00-\x1F, \x7F) 并去除换行与管道符
    msg=$(printf '%s' "$msg" | tr -d '\r\n\000-\010\013\014\016-\037\177')
    msg="${msg//|//}"

    echo "$now|$level|$msg|$ip_ver" >> "$ALERT_LOG"
    log_msg "ALERT-$level" "[$ip_ver] $msg"
}

# 按天聚合最近风险变化提醒 (展示最近 target_days 天的每日变化统计与智能摘要)
render_daily_alerts_summary() {
    local target_days="${1:-3}"

    # 获取最近检测/有记录的日期列表 (最多 target_days 天，格式 YYYY-MM-DD，倒序)
    local active_dates=()
    mapfile -t active_dates < <(
        {
            if [[ -d "$V4_DIR" ]]; then
                for f in "$V4_DIR"/*.json; do
                    [[ -f "$f" ]] && basename "$f" | cut -d'_' -f1
                done
            fi
            if [[ -d "$V6_DIR" ]]; then
                for f in "$V6_DIR"/*.json; do
                    [[ -f "$f" ]] && basename "$f" | cut -d'_' -f1
                done
            fi
            if [[ -f "$ALERT_LOG" ]]; then
                cut -d' ' -f1 "$ALERT_LOG" 2>/dev/null
            fi
        } | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort -u -r | head -n "$target_days"
    )

    if [[ ${#active_dates[@]} -eq 0 ]]; then
        echo -e "  ${C_GRAY}• 暂无历史检测归档数据${C_RESET}"
        return
    fi

    for d in "${active_dates[@]}"; do
        local short_date="${d:5}"

        local day_alerts=()
        if [[ -f "$ALERT_LOG" ]]; then
            mapfile -t day_alerts < <(grep "^$d " "$ALERT_LOG" 2>/dev/null | grep -v "首次完成数据存档监测" || true)
        fi
        local count=${#day_alerts[@]}

        local has_checks=false
        if compgen -G "$V4_DIR/${d}_*.json" >/dev/null 2>&1 || compgen -G "$V6_DIR/${d}_*.json" >/dev/null 2>&1; then
            has_checks=true
        fi

        if (( count == 0 )); then
            # M-16: 区分当日是否有检测记录，避免无检测时误报各数据库状态稳定良好
            if [[ "$has_checks" == "false" ]]; then
                echo -e "  ${C_GRAY}• [${short_date}] 当日无检测记录${C_RESET}"
            elif [[ -f "$ALERT_LOG" ]] && grep -q "^$d .*首次完成数据存档监测" "$ALERT_LOG" 2>/dev/null; then
                echo -e "  ${C_GREEN}• [${short_date}] 首次完成建档监测，当前状态已记录。${C_RESET}"
            else
                echo -e "  ${C_GREEN}• [${short_date}] 无风险变动: 本次检测未发现新的状态变化。${C_RESET}"
            fi
        else
            local crit_cnt=0 warn_cnt=0 info_cnt=0
            local top_crit_msg="" top_warn_msg="" top_info_msg=""

            for alt in "${day_alerts[@]}"; do
                local a_time a_level a_msg a_ver
                IFS='|' read -r a_time a_level a_msg a_ver <<< "$alt"
                case "$a_level" in
                    CRITICAL)
                        (( ++crit_cnt ))
                        top_crit_msg="$a_msg"
                        ;;
                    WARNING)
                        (( ++warn_cnt ))
                        top_warn_msg="$a_msg"
                        ;;
                    *)
                        (( ++info_cnt ))
                        top_info_msg="$a_msg"
                        ;;
                esac
            done

            local line_color="${C_CYAN}"
            local level_label="提示变动"
            local breakdown=""
            local rep_msg=""

            if (( crit_cnt > 0 )); then
                line_color="${C_RED}"
                level_label="异常变动"
                rep_msg="$top_crit_msg"
                if (( warn_cnt > 0 )); then
                    breakdown="${crit_cnt} 严重 ${warn_cnt} 警告"
                else
                    breakdown="${crit_cnt} 严重"
                fi
            elif (( warn_cnt > 0 )); then
                line_color="${C_YELLOW}"
                level_label="风险变动"
                rep_msg="$top_warn_msg"
                if (( info_cnt > 0 )); then
                    breakdown="${warn_cnt} 警告 ${info_cnt} 提示"
                else
                    breakdown="${warn_cnt} 警告"
                fi
            else
                line_color="${C_CYAN}"
                level_label="提示变动"
                rep_msg="$top_info_msg"
                breakdown="${info_cnt} 提示"
            fi

            # 清理冗余标记并精简为清晰扼要短语 (例如 "TikTok 地区变动" 而非冗长的 "从[AL]变为[US]")
            rep_msg=$(echo "$rep_msg" | sed -r \
                -e 's/\s*\(评分:[^)]*\)//g' \
                -e 's/\s*\(原:[^)]*\)//g' \
                -e 's/ 地区从 .* 变为 .*/ 地区变动/g' \
                -e 's/ 地区变动:.*/ 地区变动/g' \
                -e 's/ 地区 \[.*\] 不符合预期 .*/ 地区异常/g' \
                -e 's/ 解锁状态发生降级.*/ 解锁降级/g' \
                -e 's/ 解锁状态变化.*/ 解锁变动/g' \
                -e 's/ 风险等级上升至.*/ 风险等级上升/g' \
                -e 's/ 风险等级上升:.*/ 风险等级上升/g' \
                -e 's/ 风险等级变动:.*/ 风险等级变动/g' \
                -e 's/ 风险等级改善恢复:.*/ 风险等级改善/g' \
                -e 's/ (原生\/广播|使用|公司)?类型发生变化.*/ 类型变动/g')
            rep_msg="${rep_msg%%: \[*}"
            rep_msg="${rep_msg%%: *}"
            rep_msg=$(echo "$rep_msg" | sed -e 's/[[:space:]]*$//')

            local full_desc="$rep_msg"
            if (( count > 1 )); then
                if (( crit_cnt > 0 )); then
                    full_desc="${rep_msg} 等 (需关注)"
                else
                    full_desc="${rep_msg} 等"
                fi
            fi

            # 宽度保护：截断超长字符串，确保终端不折行
            if [[ ${#full_desc} -gt 38 ]]; then
                full_desc="${full_desc:0:35}..."
            fi

            echo -e "  ${line_color}• [${short_date}] 检出 ${count} 项${level_label} (${breakdown}): ${full_desc}${C_RESET}"
        fi
    done
}

compare_and_alert() {
    local dir="$1"
    local new_file="$2"
    local ip_ver="$3"

    # 获取前一份有效存档文件（排除当前 new_file）(S-03)
    local prev_file=""
    local f
    while read -r f; do
        if [[ -n "$f" && "$f" != "$new_file" && -f "$f" ]] && validate_json "$f"; then
            prev_file="$f"
            break
        fi
    done < <(find "$dir" -maxdepth 1 -name '*.json' 2>/dev/null | sort -r)

    if [[ -z "$prev_file" || ! -f "$prev_file" ]]; then
        add_alert "INFO" "首次完成数据存档监测" "$ip_ver"
        return 0
    fi

    # 1. 对比流媒体地区变化 (YouTube, Netflix, TikTok, AmazonPrimeVideo)
    local services=("Youtube" "Netflix" "TikTok" "AmazonPrimeVideo")
    for svc in "${services[@]}"; do
        local old_reg new_reg
        old_reg=$(jq -r ".Media.$svc.Region // empty" "$prev_file")
        new_reg=$(jq -r ".Media.$svc.Region // empty" "$new_file")
        old_reg=$(clean_region_str "$old_reg")
        new_reg=$(clean_region_str "$new_reg")
        [[ "$old_reg" == "--" ]] && old_reg=""
        [[ "$new_reg" == "--" ]] && new_reg=""
        if [[ -n "$old_reg" && -n "$new_reg" && "$old_reg" != "$new_reg" ]]; then
            local svc_disp="$svc"
            [[ "$svc" == "AmazonPrimeVideo" ]] && svc_disp="AmazonPV"
            add_alert "WARNING" "$svc_disp 地区变动: [$old_reg] -> [$new_reg]" "$ip_ver"
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

    # 2. 对比流媒体解锁状态 (M-17: 涵盖所有解锁到受限/仅网页/机房等降级场景)
    local all_media=("TikTok" "DisneyPlus" "Netflix" "Youtube" "AmazonPrimeVideo" "Reddit" "ChatGPT")
    for svc in "${all_media[@]}"; do
        local old_status new_status
        old_status=$(jq -r ".Media.$svc.Status // empty" "$prev_file")
        new_status=$(jq -r ".Media.$svc.Status // empty" "$new_file")
        if [[ -n "$old_status" && -n "$new_status" && "$old_status" != "$new_status" ]]; then
            local svc_disp="$svc"
            [[ "$svc" == "AmazonPrimeVideo" ]] && svc_disp="AmazonPV"
            [[ "$svc" == "DisneyPlus" ]] && svc_disp="Disney+"
            if [[ "$new_status" =~ (失败|屏蔽|No|Blocked|Block|Failed|中国|China|禁会员|NoPrem) || ( "$old_status" =~ (解锁|Yes|Native) && "$new_status" =~ (仅自制|NF\.Only|仅网页|WebOnly|仅APP|APPOnly|机房|IDC|待支持|Pending) ) ]]; then
                add_alert "CRITICAL" "$svc_disp 解锁状态发生降级: [$old_status] 变为 [$new_status]" "$ip_ver"
            elif [[ "$old_status" =~ (仅自制|NF\.Only) && "$new_status" =~ (仅网页|WebOnly|仅APP|APPOnly|机房|IDC|待支持|Pending) ]]; then
                add_alert "WARNING" "$svc_disp 解锁状态发生降级: [$old_status] 变为 [$new_status]" "$ip_ver"
            elif [[ "$new_status" =~ (解锁|Yes|Native) ]]; then
                add_alert "INFO" "$svc_disp 解锁状态改善: [$old_status] 提升为 [$new_status]" "$ip_ver"
            else
                add_alert "INFO" "$svc_disp 解锁状态变化: [$old_status] 变为 [$new_status]" "$ip_ver"
            fi
        fi
    done

    # 3. 对比各风控数据库等级变动 (基于各官方标准判定等级跨越，并结合分值阈值 S-04)
    local score_keys=("IP2LOCATION" "SCAMALYTICS" "ipapi" "AbuseIPDB" "IPQS" "DBIP")
    for sk in "${score_keys[@]}"; do
        local old_raw new_raw
        old_raw=$(jq -r ".Score.$sk // empty" "$prev_file")
        new_raw=$(jq -r ".Score.$sk // empty" "$new_file")
        [[ -z "$old_raw" || "$old_raw" == "null" || -z "$new_raw" || "$new_raw" == "null" ]] && continue

        local old_badge_info new_badge_info
        old_badge_info=$(get_risk_badge "$old_raw" "$sk")
        new_badge_info=$(get_risk_badge "$new_raw" "$sk")
        [[ -z "$old_badge_info" || -z "$new_badge_info" ]] && continue

        local old_badge new_badge
        old_badge=$(echo "$old_badge_info" | cut -d'|' -f1)
        new_badge=$(echo "$new_badge_info" | cut -d'|' -f1)

        if [[ -n "$old_badge" && -n "$new_badge" && "$old_badge" != "$new_badge" ]]; then
            local old_rank new_rank
            old_rank=$(get_risk_level_rank "$old_badge")
            new_rank=$(get_risk_level_rank "$new_badge")

            if (( new_rank > old_rank )); then
                if (( new_rank >= 3 )); then
                    add_alert "CRITICAL" "$sk 风险等级上升至 [$new_badge] (原: [$old_badge], 评分: $old_raw -> $new_raw)" "$ip_ver"
                elif (( new_rank == 2 )); then
                    add_alert "WARNING" "$sk 风险等级上升: [$old_badge] 变为 [$new_badge] (评分: $old_raw -> $new_raw)" "$ip_ver"
                else
                    add_alert "INFO" "$sk 风险等级变动: [$old_badge] 变为 [$new_badge] (评分: $old_raw -> $new_raw)" "$ip_ver"
                fi
            elif (( new_rank < old_rank )); then
                add_alert "INFO" "$sk 风险等级改善恢复: [$old_badge] 恢复为 [$new_badge] (评分: $old_raw -> $new_raw)" "$ip_ver"
            fi
        elif [[ "$old_badge" == "$new_badge" ]]; then
            # S-04: 等级未跨越时，若分值绝对数值大幅跃升超过配置阈值，触发警示
            local sc_old sc_new
            sc_old=$(normalize_score "$old_raw")
            sc_new=$(normalize_score "$new_raw")
            if [[ "$sc_old" =~ ^[0-9]+$ && "$sc_new" =~ ^[0-9]+$ ]]; then
                local diff=$(( sc_new - sc_old ))
                if (( SCORE_DIFF_THRESHOLD > 0 && diff >= SCORE_DIFF_THRESHOLD )); then
                    add_alert "WARNING" "$sk 风险评分大幅上涨 +${diff} 分 (同处于 [$new_badge] 等级, 评分: $old_raw -> $new_raw)" "$ip_ver"
                fi
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

# 宿主 IPv6 能力检测 (M-11: 优先检查内核网卡全局 IPv6 地址，兼顾无 ip 命令的极简环境)
host_supports_ipv6() {
    if [[ -f /proc/net/if_inet6 ]]; then
        if awk '$1 !~ /^00000000000000000000000000000001/ && $1 !~ /^fe80/ { found=1; exit } END { exit !found }' /proc/net/if_inet6 2>/dev/null; then
            return 0
        fi
    fi
    if command -v ip >/dev/null 2>&1; then
        if ip -6 addr show scope global 2>/dev/null | grep -q "inet6" || ip -6 route show default 2>/dev/null | grep -q "default"; then
            return 0
        fi
    fi
    if command -v ifconfig >/dev/null 2>&1; then
        if ifconfig 2>/dev/null | grep -E "inet6.*(global|<global>)" | grep -vq "fe80:"; then
            return 0
        fi
    fi
    return 1
}

# ==============================================================================
# 数据采集核心逻辑
# ==============================================================================
run_check() {
    local quiet="${1:-false}"
    local start_sec
    start_sec=$(date +%s)

    # 并发锁控制 (M-08A: 使用统一 main 执行锁实现与更新操作互斥)
    if ! acquire_lock "main"; then
        if [[ "$quiet" == "true" ]]; then
            log_msg "WARN" "检测到已有 IPQA 任务或更新正在运行，跳过本次周期"
            return 0
        else
            echo -e "${C_YELLOW}⚠ 另一个 IPQA 任务或更新正在运行中，请等待其完成后重试${C_RESET}"
            return 1
        fi
    fi
    trap cleanup_main_lock EXIT
    trap handle_interrupt INT
    trap handle_term TERM

    load_config
    if ! ensure_ip_script; then
        cleanup_main_lock
        trap - EXIT INT TERM
        return 1
    fi
    auto_update_if_needed "$quiet"

    local ts
    ts=$(date +%Y-%m-%d_%H%M%S)
    local v4_out="$V4_DIR/${ts}.json"
    local v6_out="$V6_DIR/${ts}.json"
    local v4_tmp="$V4_DIR/.${ts}.tmp.$$.json"
    local v6_tmp="$V6_DIR/.${ts}.tmp.$$.json"
    local v4_success=false
    local v6_success=false

    [[ "$quiet" == "false" ]] && echo -e "${C_CYAN}▶ [1/2] 开始执行 IPv4 质量检测...${C_RESET}"
    log_msg "INFO" "开始执行 IPv4 检测: $ts"

    # 执行 IPv4 检测并输出到临时 JSON (S-03)
    bash "$IP_SCRIPT" -4 -y -n -p -o "$v4_tmp" >/dev/null 2>&1

    if validate_json "$v4_tmp"; then
        mv "$v4_tmp" "$v4_out"
        v4_success=true
        [[ "$quiet" == "false" ]] && echo -e "${C_GREEN}✔ IPv4 检测完成并已有效存档: $(basename "$v4_out")${C_RESET}"
        log_msg "INFO" "IPv4 检测成功: $v4_out"
        compare_and_alert "$V4_DIR" "$v4_out" "IPv4"
    else
        rm -f "$v4_tmp" "$v4_out" 2>/dev/null || true
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
        bash "$IP_SCRIPT" -6 -y -n -p -o "$v6_tmp" >/dev/null 2>&1

        if validate_json "$v6_tmp"; then
            local v6_ip
            v6_ip=$(jq -r '.Head.IP // empty' "$v6_tmp")
            if [[ -n "$v6_ip" && "$v6_ip" != "null" ]]; then
                mv "$v6_tmp" "$v6_out"
                v6_success=true
                [[ "$quiet" == "false" ]] && echo -e "${C_GREEN}✔ IPv6 检测完成并已有效存档: $(basename "$v6_out")${C_RESET}"
                log_msg "INFO" "IPv6 检测成功: $v6_out"
                compare_and_alert "$V6_DIR" "$v6_out" "IPv6"
                HAS_V6="true"
                save_config
            else
                rm -f "$v6_tmp" "$v6_out" 2>/dev/null || true
                # M-11: 有效 JSON 但 IP 为空时，核实宿主是否具备 IPv6 能力
                if host_supports_ipv6; then
                    [[ "$quiet" == "false" ]] && echo -e "${C_YELLOW}⚠ 本机具备 IPv6 地址但检测核心未返回有效 IPv6，保留探测状态${C_RESET}"
                    log_msg "WARN" "本机具备 IPv6 但检测核心未返回有效 IPv6 地址"
                else
                    [[ "$quiet" == "false" ]] && echo -e "${C_GRAY}ℹ 未检测到有效 IPv6 地址，跳过 v6 归档${C_RESET}"
                    if [[ "$HAS_V6" == "auto" ]]; then
                        HAS_V6="false"
                        save_config
                    fi
                fi
            fi
        else
            rm -f "$v6_tmp" "$v6_out" 2>/dev/null || true
            # M-11: 区分网络临时失败与本机是否真正支持 IPv6
            if host_supports_ipv6; then
                [[ "$quiet" == "false" ]] && echo -e "${C_YELLOW}⚠ 本机具备 IPv6 但检测未生成有效数据 (可能网络超时)，保留探测状态${C_RESET}"
                log_msg "WARN" "本机具备 IPv6 但检测核心返回无效 JSON"
            else
                [[ "$quiet" == "false" ]] && echo -e "${C_GRAY}ℹ 本机当前不支持 IPv6${C_RESET}"
                if [[ "$HAS_V6" == "auto" ]]; then
                    HAS_V6="false"
                    save_config
                fi
            fi
        fi
    else
        [[ "$quiet" == "false" ]] && echo -e "${C_GRAY}ℹ 根据配置已跳过 IPv6 检测 (HAS_V6=$HAS_V6)${C_RESET}"
    fi

    # 清理超额历史文件 (M-22: 路径空格与 NUL 安全)
    if [[ "$KEEP_MAX_ARCHIVES" -gt 0 ]]; then
        for target_clean_dir in "$V4_DIR" "$V6_DIR"; do
            local clean_files=()
            mapfile -t clean_files < <(find "$target_clean_dir" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
            local total_clean=${#clean_files[@]}
            if (( total_clean > KEEP_MAX_ARCHIVES )); then
                local remove_cnt=$(( total_clean - KEEP_MAX_ARCHIVES ))
                for (( ci=0; ci<remove_cnt; ci++ )); do
                    rm -f "${clean_files[ci]}" 2>/dev/null || true
                done
            fi
        done
    fi

    cleanup_main_lock
    trap - EXIT INT TERM

    local end_sec
    end_sec=$(date +%s)
    local elapsed=$((end_sec - start_sec))
    [[ "$quiet" == "false" ]] && echo -e "${C_GREEN}${C_BOLD}检测完成！${C_RESET}${C_GRAY}(耗时 ${elapsed} 秒)${C_RESET}\n"

    # M-07: 显式返回执行状态 (至少一项成功则为 0，全部失败为 1)
    if [[ "$v4_success" == "true" || "$v6_success" == "true" ]]; then
        return 0
    else
        return 1
    fi
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

    local now
    now=$(date +%s)
    local cutoff_sec=0
    case "$range_type" in
        1) cutoff_sec=$(( now - 86400 )) ;;       # 24h (最近24小时)
        2) cutoff_sec=$(( now - 7 * 86400 )) ;;   # 7d  (最近7天)
        3) cutoff_sec=$(( now - 14 * 86400 )) ;;  # 14d (最近14天)
        4) cutoff_sec=$(( now - 30 * 86400 )) ;;  # 30d (最近30天)
        5|all|*) cutoff_sec=0 ;;                  # 全部历史
    esac

    local all_files
    # 按字典序排序（文件名格式为 YYYY-MM-DD_HHMMSS.json，排序即时间排序）
    mapfile -t all_files < <(ls -1 "$dir"/*.json 2>/dev/null | sort)
    local total=${#all_files[@]}
    if [[ $total -eq 0 ]]; then
        return 0
    fi

    local filtered=()
    local cutoff_str=""
    if (( cutoff_sec > 0 )); then
        cutoff_str=$(date -d "@$cutoff_sec" +%Y-%m-%d_%H%M%S 2>/dev/null || echo "")
    fi

    for f in "${all_files[@]}"; do
        local fname
        fname=$(basename "$f" .json)
        if [[ -n "$cutoff_str" && "$fname" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$ ]]; then
            if [[ "$fname" < "$cutoff_str" ]]; then
                continue
            fi
        fi
        # S-03: 预先验证 JSON 完整性，跳过损坏/截断文件
        if validate_json "$f"; then
            filtered+=("$f")
        fi
    done

    local count=${#filtered[@]}
    if [[ $count -eq 0 ]]; then
        # M-12: 范围内无文件时如实返回空，不再错误重载全部历史
        return 0
    fi

    # 如果选中的点多于 max_points，采用【变化感知关键帧自适应降采样】：
    # 优先锁定状态发生突变的关键点 (Keyframes) 及首尾点，剩余槽位等间距补充，确保突变 100% 呈现且时间轴均匀
    if (( count > max_points && max_points > 0 )); then
        local fingerprints=()
        # S-12: 如果选中的文件过多 (例如 >250)，限制抽取特征的文件集避免过长 jq 等待
        local sample_for_fp=("${filtered[@]}")
        local fp_map_idx=()
        if (( count > 250 )); then
            local fp_step=$(( count / 150 ))
            for ((s=0; s<count; s+=fp_step)); do
                sample_for_fp+=("${filtered[$s]}")
                fp_map_idx+=("$s")
            done
            if [[ ${fp_map_idx[-1]} -ne $((count - 1)) ]]; then
                sample_for_fp+=("${filtered[$((count - 1))]}")
                fp_map_idx+=("$((count - 1))")
            fi
        fi

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
                # 变动点数量超过上限：首尾锚定，中间变动点按时间轴等距精选 (N-03 修复)
                local mid_candidates=("${change_indices[@]}")
                local mid_needed=$(( max_points - 2 ))
                local last_cand_idx=$(( ${#mid_candidates[@]} - 1 ))
                if [[ ${#mid_candidates[@]} -gt 0 && ${mid_candidates[last_cand_idx]} -eq $((count - 1)) ]]; then
                    unset 'mid_candidates[last_cand_idx]'
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
            printf "│  ${C_GREEN}✅ 保持稳定${C_RESET}\n"
        else
            printf "│  ${C_YELLOW}⚠️  存在变动${C_RESET}\n"
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
    # 文本风险等级格式 (如 DB-IP 返回的 "低风险" / "low" 等) -> 映射为统一数值 (0 / 50 / 100)
    case "$raw" in
        *低*|low|Low) echo 0; return ;;
        *中*|medium|Medium) echo 50; return ;;
        *高*|high|High) echo 100; return ;;
    esac
    # 无法识别的格式，静默丢弃
}

get_risk_badge() {
    local raw="$1"
    local db="$2"
    [[ -z "$raw" || "$raw" == "null" || "$raw" == "" ]] && return

    case "$db" in
        ipapi)
            # 处理百分比格式 (如 "2.34%", "0.73%", "0.10%", "5.2%") -> 转换为基点 bp (1% = 100 bp)
            local num_str="${raw%%%}"
            # S-18: 严格校验为合法浮点或整数字符串，异常值直接退出，不误判为极低风险
            if ! [[ "$num_str" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                return
            fi
            local bp=0
            if [[ "$num_str" =~ ^([0-9]+)\.?([0-9]*)$ ]]; then
                local int_p="${BASH_REMATCH[1]}"
                local dec_p="${BASH_REMATCH[2]}00"
                dec_p="${dec_p:0:2}"
                bp=$(( 10#$int_p * 100 + 10#$dec_p ))
            fi
            if (( bp < 15 )); then
                echo "极低风险|$C_GREEN"
            elif (( bp < 85 )); then
                echo "低风险|$C_GREEN"
            elif (( bp < 300 )); then
                echo "较高风险|$C_YELLOW"
            elif (( bp < 1000 )); then
                echo "高风险|$C_RED"
            else
                echo "极高风险|$C_MAGENTA"
            fi
            ;;
        IP2LOCATION)
            local sc
            sc=$(normalize_score "$raw")
            [[ ! "$sc" =~ ^[0-9]+$ ]] && return
            if (( sc < 33 )); then echo "低风险|$C_GREEN"
            elif (( sc < 66 )); then echo "中风险|$C_YELLOW"
            else echo "高风险|$C_RED"; fi
            ;;
        SCAMALYTICS)
            local sc
            sc=$(normalize_score "$raw")
            [[ ! "$sc" =~ ^[0-9]+$ ]] && return
            if (( sc < 20 )); then echo "低风险|$C_GREEN"
            elif (( sc < 60 )); then echo "中风险|$C_YELLOW"
            elif (( sc < 90 )); then echo "高风险|$C_RED"
            else echo "极高风险|$C_MAGENTA"; fi
            ;;
        AbuseIPDB)
            local sc
            sc=$(normalize_score "$raw")
            [[ ! "$sc" =~ ^[0-9]+$ ]] && return
            if (( sc < 25 )); then echo "低风险|$C_GREEN"
            elif (( sc < 75 )); then echo "高风险|$C_RED"
            else echo "建议封禁|$C_MAGENTA"; fi
            ;;
        IPQS)
            local sc
            sc=$(normalize_score "$raw")
            [[ ! "$sc" =~ ^[0-9]+$ ]] && return
            if (( sc < 75 )); then echo "低风险|$C_GREEN"
            elif (( sc < 85 )); then echo "可疑IP|$C_YELLOW"
            elif (( sc < 90 )); then echo "存在风险|$C_RED"
            else echo "高风险|$C_RED"; fi
            ;;
        DBIP)
            local sc
            sc=$(normalize_score "$raw")
            [[ ! "$sc" =~ ^[0-9]+$ ]] && return
            if (( sc == 0 )); then echo "低风险|$C_GREEN"
            elif (( sc <= 50 )); then echo "中风险|$C_YELLOW"
            else echo "高风险|$C_RED"; fi
            ;;
        *)
            local sc
            sc=$(normalize_score "$raw")
            [[ ! "$sc" =~ ^[0-9]+$ ]] && return
            if (( sc < 20 )); then echo "低风险|$C_GREEN"
            elif (( sc < 50 )); then echo "中风险|$C_YELLOW"
            elif (( sc < 75 )); then echo "高风险|$C_RED"
            else echo "极高风险|$C_MAGENTA"; fi
            ;;
    esac
}

get_risk_level_rank() {
    local badge="$1"
    case "$badge" in
        "极低风险") echo 0 ;;
        "低风险")   echo 1 ;;
        "中风险"|"较高风险"|"可疑IP") echo 2 ;;
        "存在风险"|"高风险") echo 3 ;;
        "极高风险"|"建议封禁") echo 4 ;;
        *) echo -1 ;;
    esac
}

render_bar() {
    local raw="$1"
    local db="${2:-}"
    local max_width=30

    if [[ -z "$raw" || "$raw" == "null" || "$raw" == "" ]]; then
        echo -e "${C_GRAY}┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈  无数据${C_RESET}"
        return
    fi

    local badge_info
    badge_info=$(get_risk_badge "$raw" "$db")
    if [[ -z "$badge_info" ]]; then
        echo -e "${C_GRAY}┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈  无数据${C_RESET}"
        return
    fi

    local badge color
    badge=$(echo "$badge_info" | cut -d'|' -f1)
    color=$(echo "$badge_info" | cut -d'|' -f2)

    local bar_len=0
    local disp_score=""

    if [[ "$db" == "ipapi" ]]; then
        # ipapi 特殊处理: 百分比分值 & 三段式比例尺绘图
        local num_str="${raw%%%}"
        # S-18: 严格校验为合法浮点或整数字符串，异常值直接显示无有效数据
        if ! [[ "$num_str" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            printf "%-7s  %b\n" "$raw" "${C_GRAY}无有效数据${C_RESET}"
            return
        fi
        disp_score="${num_str}%"
        local bp=0
        if [[ "$num_str" =~ ^([0-9]+)\.?([0-9]*)$ ]]; then
            local int_p="${BASH_REMATCH[1]}"
            local dec_p="${BASH_REMATCH[2]}00"
            dec_p="${dec_p:0:2}"
            bp=$(( 10#$int_p * 100 + 10#$dec_p ))
        fi
        # 三段式映射 (绿区: 0-85 -> 0-10, 黄区: 85-300 -> 10-20, 红区: 300-10000 -> 20-30)
        if (( bp < 85 )); then
            bar_len=$(( bp * 10 / 85 ))
        elif (( bp < 300 )); then
            bar_len=$(( 10 + (bp - 85) * 10 / 215 ))
        else
            bar_len=$(( 20 + (bp - 300) * 10 / 9700 ))
        fi
        (( bar_len == 0 && bp > 0 )) && bar_len=1
        (( bar_len > max_width )) && bar_len=max_width
    else
        # 常规 0-100 整数评分
        local sc
        sc=$(normalize_score "$raw")
        disp_score="$sc"
        bar_len=$(( sc * max_width / 100 ))
        (( bar_len == 0 && sc > 0 )) && bar_len=1
        (( bar_len > max_width )) && bar_len=max_width
    fi

    local empty_len=$(( max_width - bar_len ))
    local bar_str=""
    for ((b=0; b<bar_len; b++)); do bar_str+="█"; done
    local empty_str=""
    for ((b=0; b<empty_len; b++)); do empty_str+="░"; done

    printf "${color}%s${C_RESET}${C_GRAY}%s${C_RESET} %6s ${color}%s${C_RESET}\n" "$bar_str" "$empty_str" "$disp_score" "$badge"
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
            if [[ -n "$sc" && "$sc" != "null" && "$sc" != "" ]]; then
                local chk
                chk=$(normalize_score "$sc")
                if [[ "$chk" =~ ^[0-9]+$ ]]; then
                    db_has_score=true
                    break
                fi
            fi
        done
        [[ "$db_has_score" == "false" ]] && continue

        (( ++shown_db_count ))
        local db_unit="(满分 100)"
        [[ "$db" == "ipapi" ]] && db_unit="(百分比分值)"
        echo -e "${C_BOLD}  • 数据库: ${C_CYAN}$db${C_RESET} $db_unit"
        for f in "${files[@]}"; do
            local dt
            dt=$(fmt_short_time "$(basename "$f" .json)")
            local score
            score=$(jq -r ".Score.$db // \"null\"" "$f" 2>/dev/null)
            printf "    %-12s ▏ " "$dt"
            render_bar "$score" "$db"
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

    echo -e "${C_GRAY}说明: 评分越高风险越高。各数据库遵循官方独立判定标准:${C_RESET}"
    echo -e "${C_GRAY}  - Scamalytics: 0-19 低 | 20-59 中 | 60-89 高 | 90+ 极高${C_RESET}"
    echo -e "${C_GRAY}  - IP2Location: 0-32 低 | 33-65 中 | 66+ 高${C_RESET}"
    echo -e "${C_GRAY}  - AbuseIPDB:   0-24 低 | 25-74 高 | 75+ 建议封禁${C_RESET}"
    echo -e "${C_GRAY}  - IPQS:        0-74 低 | 75-84 可疑 | 85-89 存在风险 | 90+ 高风险${C_RESET}"
    echo -e "${C_GRAY}  - ipapi:       <0.85% 低风险 | 0.85%~3.00% 较高风险 | 3.00%+ 高风险${C_RESET}"
    echo -e "${C_GRAY}  - DB-IP:       0 低 | 50 中 | 100 高${C_RESET}\n"
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

    # 打印表头 (固定 10 字符宽度 + 1 空格 + 分隔符)
    printf "  风险因子   │ "
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

    # 打印表头 (第一列固定 12 字符宽度: "  风险因子  ")
    printf "  风险因子  "
    for d in "${dates[@]}"; do
        # 每列固定 8 字符宽度: "  09-12 "
        printf "│  %-5s " "$d"
    done
    printf "│  %-12s\n" "历史综合表现"

    local divider_len=$(( 12 + ${#dates[@]} * 9 + 16 ))
    echo -ne "  "
    draw_divider "$divider_len"

    local full_engines=("IP2LOCATION" "ipapi" "ipregistry" "IPQS" "SCAMALYTICS" "ipdata" "IPinfo" "IPWHOIS" "DBIP")
    local factors=("Proxy" "Tor" "VPN" "Server" "Abuser" "Robot")

    # S-11: 批量提取各文件风险因子统计，避免内层循环数百次调用 jq
    declare -A file_factor_det
    declare -A file_factor_tot

    for (( fi=0; fi<${#hist_files[@]}; fi++ )); do
        local hf="${hist_files[fi]}"
        local factor_summary
        factor_summary=$(jq -r '
            .Factor as $F |
            ["Proxy", "Tor", "VPN", "Server", "Abuser", "Robot"] | map(
                . as $fac |
                [ "IP2LOCATION", "ipapi", "ipregistry", "IPQS", "SCAMALYTICS", "ipdata", "IPinfo", "IPWHOIS", "DBIP", "WHOIS" ] |
                [
                    map(select(($F[$fac][.] // false) == true or ($F[$fac][.] // false) == "true")) | length,
                    map(select(($F[$fac][.] // null) != null)) | length
                ] | "\(.[0])/\(.[1])"
            ) | join("\u001f")
        ' "$hf" 2>/dev/null)

        local f_idx=0
        local f_stats=()
        IFS=$'\x1f' read -r -a f_stats <<< "$factor_summary"
        for st in "${f_stats[@]}"; do
            local det="${st%%/*}"
            local tot="${st##*/}"
            file_factor_det["${fi}_${f_idx}"]="${det:-0}"
            file_factor_tot["${fi}_${f_idx}"]="${tot:-0}"
            (( ++f_idx ))
        done
    done

    for (( fac_i=0; fac_i<${#factors[@]}; fac_i++ )); do
        local fac="${factors[fac_i]}"
        printf "  %-8s  " "$fac"
        local had_detection=false
        local had_any_tested=false

        for (( fi=0; fi<${#hist_files[@]}; fi++ )); do
            local detected_count="${file_factor_det["${fi}_${fac_i}"]:-0}"
            local total_tested="${file_factor_tot["${fi}_${fac_i}"]:-0}"

            if (( total_tested == 0 )); then
                # M-14: 无数据时不显示绿色的“安全”
                printf "│ ${C_GRAY}无数据${C_RESET}  "
            elif (( detected_count > 0 )); then
                printf "│ ${C_RED}⚠️ %d/%d${C_RESET}  " "$detected_count" "$total_tested"
                had_detection=true
                had_any_tested=true
            else
                printf "│ ${C_GREEN}✔ 安全${C_RESET} "
                had_any_tested=true
            fi
        done

        if [[ "$had_detection" == "true" ]]; then
            printf "│  ${C_YELLOW}⚠️  曾有检出${C_RESET}\n"
        elif [[ "$had_any_tested" == "true" ]]; then
            printf "│  ${C_GREEN}✅ 保持安全${C_RESET}\n"
        else
            # M-14: 全部无数据时显示暂无数据
            printf "│  ${C_GRAY}⚪ 暂无数据${C_RESET}\n"
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

    # 打印时间表头 (服务名称占 8 字符，补 6 空格对齐 14 字符宽度)
    printf "  服务名称      │ "
    for d in "${dates[@]}"; do
        printf "%-5s " "$d"
    done
    echo ""
    local div_len=$(( 18 + ${#dates[@]} * 6 ))
    echo -ne "  "
    draw_divider "$div_len"

    local services=("TikTok" "DisneyPlus" "Netflix" "Youtube" "AmazonPrimeVideo" "Reddit" "ChatGPT")
    local display_names=("TikTok" "Disney+" "Netflix" "YouTube" "AmazonPV" "Reddit" "ChatGPT")

    for idx in "${!services[@]}"; do
        local svc="${services[$idx]}"
        local sname="${display_names[$idx]}"
        printf "  %-14s │ " "$sname"

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
            elif [[ "$status" =~ (仅自制|Originals|NF\.Only|仅网页|仅APP|WebOnly|APPOnly|机房|IDC|待支持|Pending) ]]; then
                printf "  %b   " "$SYM_DOT_YELLOW"
            elif [[ "$status" =~ (失败|屏蔽|No|Blocked|Block|Failed|中国|China|禁会员|NoPrem) ]]; then
                printf "  %b   " "$SYM_DOT_RED"
            else
                printf "  %b   " "$SYM_DOT_GRAY"
            fi
        done
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

    local latest_file="${files[${#files[@]}-1]}"
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

    local bl_status
    if ! [[ "$total" =~ ^[0-9]+$ ]] || (( total == 0 )); then
        bl_status="${C_GRAY}暂无检测数据${C_RESET}"
        echo -e "  • 全局 DNS 黑名单概况 : $bl_status (共 0 个数据库)"
    else
        if (( blacklisted > 0 )); then
            bl_status="${C_RED}检出 $blacklisted 个黑名单拦截！${C_RESET}"
        elif (( marked > 0 )); then
            bl_status="${C_YELLOW}检出 $marked 个可疑标记${C_RESET}"
        else
            bl_status="${C_GREEN}全部干净通过 (0 拦截)${C_RESET}"
        fi
        echo -e "  • 全局 DNS 黑名单概况 : $bl_status (共 $total 个数据库, 干净 $clean)"
    fi
    echo ""

    # 12 邮局连通性历史表格
    local dates=()
    for f in "${files[@]}"; do
        dates+=("$(fmt_short_date "$(basename "$f" .json)")")
    done

    # 打印表头 (邮局名称占 8 字符，补 2 空格对齐 10 字符宽度)
    printf "  邮局名称   │ "
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
    print_module_header "🔧 设置后台定时自动检测与存档"

    local local_h
    local_h=$(get_beijing_4am_local_hour)
    local tz_name tz_offset server_time bj_time
    tz_name=$(date +%Z)
    tz_offset=$(date +%z)
    server_time=$(date '+%H:%M')
    bj_time=$(TZ="Asia/Shanghai" date '+%H:%M' 2>/dev/null || echo "--:--")

    echo -e "  ${C_GRAY}ℹ️  服务器时区: ${C_CYAN}${tz_name} (${tz_offset})${C_GRAY} │ 本机时间: ${C_BOLD}${server_time}${C_RESET}${C_GRAY} │ 北京时间: ${C_BOLD}${bj_time}${C_RESET}"
    echo -e "  ${C_YELLOW}💡 提示: 预设选项已按北京时间凌晨 04:00 自动换算 (对应本机服务器时间: ${C_BOLD}${local_h}:00${C_RESET}${C_YELLOW})${C_RESET}\n"

    # 检测当前 crontab 中是否有 ipqa 任务 (N-01: 健壮匹配带引号与不带引号规则)
    local current_cron
    current_cron=$(crontab -l 2>/dev/null | grep -E 'ipqa(\.sh)?["'\''[:space:]]+--cron' | head -n 1 || true)

    if [[ -n "$current_cron" ]]; then
        local friendly_name
        friendly_name=$(get_cron_friendly_name "$current_cron")
        echo -e "当前状态: ${C_GREEN}已启用自动检测${C_RESET} [${friendly_name}]"
        echo -e "当前规则: ${C_YELLOW}$current_cron${C_RESET}\n"
    else
        echo -e "当前状态: ${C_GRAY}未配置定时检测${C_RESET}\n"
    fi

    echo -e "${C_BOLD}请选择定时检测周期:${C_RESET}"
    echo -e "  [1] 每天检测一次     (北京时间 04:00，自适应夏令时 / 本机约 $local_h:00) [推荐/默认]"
    echo -e "  [2] 每 3 天检测一次  (北京时间 04:00，连续跨月计算)"
    echo -e "  [3] 每 7 天检测一次  (北京时间 04:00，每周日执行)"
    echo -e "  [4] 自定义 Cron 表达式"
    echo -e "  [5] 关闭/移除定时检测"
    echo -e "  [0] 返回主菜单"
    echo ""
    echo -ne "${C_CYAN}请输入选项 [默认 1]: ${C_RESET}"
    read -r opt
    opt="${opt:-1}"

    # 确定脚本执行绝对路径 (N-04: 优先使用 verified 属于本项目的命令链接，否则严格锁定当前脚本路径)
    local script_path="$IPQA_HOME/ipqa.sh"
    if [[ -x "/usr/local/bin/ipqa" && "/usr/local/bin/ipqa" -ef "$IPQA_HOME/ipqa.sh" ]]; then
        script_path="/usr/local/bin/ipqa"
    elif [[ -x "$HOME/.local/bin/ipqa" && "$HOME/.local/bin/ipqa" -ef "$IPQA_HOME/ipqa.sh" ]]; then
        script_path="$HOME/.local/bin/ipqa"
    fi

    # M-19, M-20: 计算半小时/45分钟时区的分钟偏差并对路径安全转义
    local local_min
    local_min=$(get_beijing_00_local_minute)
    local esc_script esc_log
    esc_script=$(printf '%s' "$script_path" | sed -e 's/[\\"]/\\&/g' -e 's/%/\\%/g')
    esc_log=$(printf '%s' "$LOG_FILE" | sed -e 's/[\\"]/\\&/g' -e 's/%/\\%/g')

    local cron_line=""
    case "$opt" in
        1)
            cron_line="$local_min * * * * [ \"\$(TZ='Asia/Shanghai' date +\\%H:\\%M)\" = \"04:00\" ] && \"$esc_script\" --cron >> \"$esc_log\" 2>&1"
            ;;
        2)
            cron_line="$local_min * * * * [ \"\$(TZ='Asia/Shanghai' date +\\%H:\\%M)\" = \"04:00\" ] && [ \$(( (\$(date +\\%s) / 86400) \\% 3 )) -eq 0 ] && \"$esc_script\" --cron >> \"$esc_log\" 2>&1"
            ;;
        3)
            cron_line="$local_min * * * * [ \"\$(TZ='Asia/Shanghai' date +\\%H:\\%M)\" = \"04:00\" ] && [ \"\$(TZ='Asia/Shanghai' date +\\%u)\" = \"7\" ] && \"$esc_script\" --cron >> \"$esc_log\" 2>&1"
            ;;
        4)
            echo -ne "\n请输入 5 位标准 Cron 表达式 (如: 0 $local_h */5 * *): "
            read -r new_cron_expr
            if [[ -z "$new_cron_expr" ]]; then
                echo -e "${C_RED}Cron 表达式不能为空${C_RESET}"
                sleep 1
                return
            fi
            local cron_fields=()
            read -r -a cron_fields <<< "$new_cron_expr"
            if [[ ${#cron_fields[@]} -ne 5 ]]; then
                echo -e "\n${C_RED}错误: Cron 表达式必须包含 5 个时间字段 (分 时 日 月 周)${C_RESET}"
                sleep 2
                return
            fi
            for fld in "${cron_fields[@]}"; do
                if [[ ! "$fld" =~ ^[0-9*\/,-]+$ ]]; then
                    echo -e "\n${C_RED}错误: Cron 表达式包含非法字符: '$fld'${C_RESET}"
                    sleep 2
                    return
                fi
            done
            cron_line="$new_cron_expr \"$esc_script\" --cron >> \"$esc_log\" 2>&1"
            ;;
        5)
            # 移除所有历史 IPQA cron (N-01: 健壮去重清理)
            local tmp_cron
            tmp_cron=$(mktemp 2>/dev/null || echo "/tmp/ipqa_cron.$$.$RANDOM")
            local remaining
            remaining=$(crontab -l 2>/dev/null | grep -vE 'ipqa(\.sh)?["'\''[:space:]]+--cron' | grep -v "# IPQA AUTO CHECK" || true)
            if [[ -n "$remaining" ]]; then
                echo "$remaining" > "$tmp_cron"
                if crontab "$tmp_cron" 2>/dev/null; then
                    echo -e "\n${C_GREEN}已成功移除定时检测任务！${C_RESET}"
                    log_msg "INFO" "用户手动关闭了定时检测 cron 任务"
                else
                    echo -e "\n${C_RED}移除定时任务失败，请检查 crontab 权限${C_RESET}"
                fi
                rm -f "$tmp_cron"
            else
                crontab -r 2>/dev/null || true
                echo -e "\n${C_GREEN}已成功移除定时检测任务！${C_RESET}"
                log_msg "INFO" "用户手动关闭了定时检测 cron 任务"
            fi
            read -r -p "按回车键返回..."
            return
            ;;
        0) return ;;
        *) echo -e "${C_RED}无效选项${C_RESET}"; sleep 1; return ;;
    esac

    # 清理旧的 IPQA cron 进行严格去重，再追加新配置 (N-01)
    local existing_cron
    existing_cron=$(crontab -l 2>/dev/null | grep -vE 'ipqa(\.sh)?["'\''[:space:]]+--cron' | grep -v "# IPQA AUTO CHECK" || true)

    local tmp_cron
    tmp_cron=$(mktemp 2>/dev/null || echo "/tmp/ipqa_cron.$$.$RANDOM")
    {
        [[ -n "$existing_cron" ]] && echo "$existing_cron"
        echo "# IPQA AUTO CHECK - DO NOT EDIT MANUALLY"
        echo "$cron_line"
    } > "$tmp_cron"

    if crontab "$tmp_cron" 2>/dev/null; then
        rm -f "$tmp_cron"
        local friendly_disp
        friendly_disp=$(get_cron_friendly_name "$cron_line")
        echo -e "\n${C_GREEN}✔ 定时检测配置成功！${C_RESET}"
        echo -e "设定规则: ${C_CYAN}$cron_line${C_RESET}"
        echo -e "执行周期: ${C_YELLOW}${friendly_disp}${C_RESET}\n"
        log_msg "INFO" "配置定时任务: $cron_line"
    else
        rm -f "$tmp_cron"
        echo -e "\n${C_RED}✗ 定时检测配置失败: 写入 crontab 时出错，请检查系统 crontab 权限${C_RESET}\n"
        log_msg "ERROR" "配置定时任务失败: $cron_line"
    fi
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
    IFS=$'\x1f' read -r ip asn org city country ip_type < <(
        jq -r '[
            (.Head.IP // "未知"),
            (.Info.ASN // "--"),
            (.Info.Organization // "--"),
            (.Info.City.Name // ""),
            (.Info.Region.Name // ""),
            (.Info.Type // "--")
        ] | join("\u001f")' "$f" 2>/dev/null
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
            ["IPinfo", ($t.Usage.IPinfo // ""), ($t.Company.IPinfo // "")],
            ["ipregistry", ($t.Usage.ipregistry // ""), ($t.Company.ipregistry // "")],
            ["ipapi", ($t.Usage.ipapi // ""), ($t.Company.ipapi // "")],
            ["IP2Location", ($t.Usage.IP2LOCATION // $t.Usage.IP2Location // ""), ($t.Company.IP2LOCATION // $t.Company.IP2Location // "")],
            ["AbuseIPDB", ($t.Usage.AbuseIPDB // ""), ($t.Company.AbuseIPDB // "")]
        ] | .[] | join("\u001f")
    ' "$f" 2>/dev/null)

    while IFS=$'\x1f' read -r tdb u c; do
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
            . as $k | [$k, ($s[$k] // "")] | join("\u001f")
        ) | .[]
    ' "$f" 2>/dev/null)
    while IFS=$'\x1f' read -r sdb sc; do
        [[ -z "$sc" || "$sc" == "null" ]] && continue
        local chk
        chk=$(normalize_score "$sc")
        if [[ "$chk" =~ ^[0-9]+$ ]]; then
            printf "    • %-13s ▏ " "$sdb"
            render_bar "$sc" "$sdb"
            (( ++score_count ))
        fi
    done <<< "$score_data"
    if (( score_count == 0 )); then
        echo -e "    ${C_GRAY}• 暂无各权威数据库有效风控评分数据${C_RESET}"
    fi

    # 风险因子 (一次性提取 6 大安全因子检出状态，支持无数据检测)
    echo -e "  ${C_GRAY}── 🔬 核心安全因子 ─────────────────────────────────────────────────${C_RESET}"
    local factor_line="   "
    local factor_data
    factor_data=$(jq -r '
        .Factor as $f |
        ["Proxy", "Tor", "VPN", "Server", "Abuser", "Robot"] | map(
            . as $fac |
            [ "IP2LOCATION", "ipapi", "ipregistry", "IPQS", "SCAMALYTICS", "ipdata", "IPinfo", "IPWHOIS", "DBIP", "WHOIS" ] as $engs |
            ($engs | map(select($f[$fac][.] != null and $f[$fac][.] != "--" and $f[$fac][.] != "")) | length) as $tested |
            ($engs | any(($f[$fac][.] // false) == true or ($f[$fac][.] // false) == "true")) as $is_det |
            [$fac, ($tested|tostring), ($is_det|tostring)] | join("\u001f")
        ) | .[]
    ' "$f" 2>/dev/null)
    while IFS=$'\x1f' read -r fac tested is_detected; do
        [[ -z "$fac" ]] && continue
        if [[ "$tested" -eq 0 ]]; then
            factor_line+=" ${fac}: ${C_GRAY}● 无数据${C_RESET}  "
        elif [[ "$is_detected" == "true" ]]; then
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
            ["Youtube", "YouTube", ($m.Youtube.Status // "未知"), ($m.Youtube.Region // ""), ($m.Youtube.Type // "")],
            ["Netflix", "Netflix", ($m.Netflix.Status // "未知"), ($m.Netflix.Region // ""), ($m.Netflix.Type // "")],
            ["DisneyPlus", "Disney+", ($m.DisneyPlus.Status // "未知"), ($m.DisneyPlus.Region // ""), ($m.DisneyPlus.Type // "")],
            ["TikTok", "TikTok", ($m.TikTok.Status // "未知"), ($m.TikTok.Region // ""), ($m.TikTok.Type // "")],
            ["AmazonPrimeVideo", "AmazonPV", ($m.AmazonPrimeVideo.Status // $m.AmazonPV.Status // "未知"), ($m.AmazonPrimeVideo.Region // $m.AmazonPV.Region // ""), ($m.AmazonPrimeVideo.Type // $m.AmazonPV.Type // "")],
            ["ChatGPT", "ChatGPT", ($m.ChatGPT.Status // "未知"), ($m.ChatGPT.Region // ""), ($m.ChatGPT.Type // "")],
            ["Reddit", "Reddit", ($m.Reddit.Status // "未知"), ($m.Reddit.Region // ""), ($m.Reddit.Type // "")]
        ] | .[] | join("\u001f")
    ' "$f" 2>/dev/null)

    while IFS=$'\x1f' read -r m_key m_name st reg m_type; do
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
    IFS=$'\x1f' read -r p25 bl_total bl_blk < <(
        jq -r '[
            (.Mail.Port25 // "null"),
            (.Mail.DNSBlacklist.Total // 0),
            (.Mail.DNSBlacklist.Blacklisted // 0)
        ] | join("\u001f")' "$f" 2>/dev/null
    )
    if [[ "$p25" == "true" ]]; then
        echo -e "    • 25 端口出站 (Port 25): ${C_GREEN}✓ 开放${C_RESET}"
    elif [[ "$p25" == "false" ]]; then
        echo -e "    • 25 端口出站 (Port 25): ${C_RED}✗ 拦截/封禁${C_RESET}"
    else
        echo -e "    • 25 端口出站 (Port 25): ${C_GRAY}未检出${C_RESET}"
    fi

    if ! [[ "$bl_total" =~ ^[0-9]+$ ]] || (( bl_total == 0 )); then
        echo -e "    • DNS 黑名单拦截       : ${C_GRAY}暂无检测数据 (0 数据库)${C_RESET}"
    elif (( bl_blk == 0 )); then
        echo -e "    • DNS 黑名单拦截       : ${C_GREEN}0 / $bl_total 数据库 (全部干净通过)${C_RESET}"
    else
        echo -e "    • DNS 黑名单拦截       : ${C_RED}$bl_blk / $bl_total 数据库检出拦截！${C_RESET}"
    fi
    echo -e "${proto_color}└──────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

# 将存档时间戳字符串解析为 epoch 秒 (S-06)
# 支持 YYYY-MM-DD_HHMMSS 以及 YYYY-MM-DD_HH-MM-SS 等不同格式
parse_archive_epoch() {
    local raw="$1"
    if [[ "$raw" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
        date -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}" +%s 2>/dev/null || echo 0
    elif [[ "$raw" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})$ ]]; then
        date -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}" +%s 2>/dev/null || echo 0
    elif [[ "$raw" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
        date -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}" +%s 2>/dev/null || echo 0
    else
        echo 0
    fi
}

find_matching_v6() {
    local target_ts="$1"
    local direct="$V6_DIR/${target_ts}.json"
    if [[ -f "$direct" ]]; then
        echo "$direct"
        return
    fi
    [[ ! -d "$V6_DIR" ]] && return

    # S-06: 精确解析 YYYY-MM-DD_HHMMSS 时间戳进行近邻匹配 (阈值 300 秒)
    local target_epoch=0
    target_epoch=$(parse_archive_epoch "$target_ts")

    local best_file=""
    local min_diff=999999

    for f6 in "$V6_DIR"/*.json; do
        [[ ! -f "$f6" ]] && continue
        local fn6
        fn6=$(basename "$f6" .json)
        if [[ "$fn6" == "$target_ts" ]]; then
            echo "$f6"
            return
        fi
        if (( target_epoch > 0 )); then
            local f6_epoch=0
            f6_epoch=$(parse_archive_epoch "$fn6")
            if (( f6_epoch > 0 )); then
                local diff=$(( f6_epoch - target_epoch ))
                (( diff < 0 )) && diff=$(( -diff ))
                if (( diff <= 300 && diff < min_diff )); then
                    min_diff=$diff
                    best_file="$f6"
                fi
            fi
        fi
    done

    if [[ -n "$best_file" ]]; then
        echo "$best_file"
    fi
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

# ==============================================================================
# 模块 6: 风险变化提醒历史 (show_alerts_history)
# ==============================================================================
show_alerts_history() {
    local total_archives=0
    total_archives=$(( $(count_json_files "$V4_DIR") + $(count_json_files "$V6_DIR") ))

    if [[ ! -f "$ALERT_LOG" || ! -s "$ALERT_LOG" ]]; then
        clear
        print_module_header "🔔 风险变化提醒历史一览"
        if (( total_archives == 0 )); then
            echo -e "  ${C_YELLOW}• 暂无任何检测存档与提醒记录，请先执行一次检测 (选项 9)${C_RESET}\n"
        else
            echo -e "  ${C_GREEN}• 暂无新的风险变化提醒记录${C_RESET}\n"
        fi
        read -r -p "按回车键返回主菜单..."
        return
    fi

    # 倒序读取全部告警记录 (最新变动在最前)
    local all_alerts=()
    mapfile -t all_alerts < <(sort -t'|' -k1 -r "$ALERT_LOG" 2>/dev/null)

    local total_count=${#all_alerts[@]}
    if (( total_count == 0 )); then
        clear
        print_module_header "🔔 风险变化提醒历史一览"
        if (( total_archives == 0 )); then
            echo -e "  ${C_YELLOW}• 暂无任何检测存档与提醒记录，请先执行一次检测 (选项 9)${C_RESET}\n"
        else
            echo -e "  ${C_GREEN}• 暂无新的风险变化提醒记录${C_RESET}\n"
        fi
        read -r -p "按回车键返回主菜单..."
        return
    fi

    local page=0
    local page_size=15
    local total_pages=$(( (total_count + page_size - 1) / page_size ))
    (( total_pages == 0 )) && total_pages=1

    while true; do
        clear
        print_module_header "🔔 风险变化提醒历史一览"

        local start_idx=$((page * page_size))
        local end_idx=$((start_idx + page_size))
        (( end_idx > total_count )) && end_idx=$total_count

        echo -e "最近风险变动事件记录 (共 ${total_count} 条，第 $((page + 1))/${total_pages} 页):\n"

        for ((i=start_idx; i<end_idx; i++)); do
            local alt="${all_alerts[$i]}"
            [[ -z "$alt" ]] && continue
            # 格式: 2026-09-11 12:00:00|WARNING|YouTube Region 发生变化|IPv4
            local a_time a_level a_msg a_ver
            IFS='|' read -r a_time a_level a_msg a_ver <<< "$alt"

            local badge=""
            case "$a_level" in
                CRITICAL) badge="${C_RED}${C_BOLD}[严重]${C_RESET}" ;;
                WARNING)  badge="${C_YELLOW}[警告]${C_RESET}" ;;
                INFO)     badge="${C_CYAN}[提示]${C_RESET}" ;;
                *)        badge="${C_GRAY}[记录]${C_RESET}" ;;
            esac

            local ver_badge=""
            if [[ "$a_ver" == "IPv6" ]]; then
                ver_badge="${C_CYAN}IPv6${C_RESET}"
            else
                ver_badge="${C_GREEN}IPv4${C_RESET}"
            fi

            local idx
            printf -v idx "%2d" "$((i + 1))"
            echo -e "  ${C_BOLD}[$idx]${C_RESET} ${a_time} │ ${ver_badge} │ ${badge} │ ${a_msg}"
        done

        echo ""
        local nav_hint=""
        (( page + 1 < total_pages )) && nav_hint+="[n] 下一页 | "
        (( page > 0 )) && nav_hint+="[p] 上一页 | "
        echo -e "${C_GRAY}──────────────────────────────────────────────────────────────────────${C_RESET}"
        echo -ne "${C_CYAN}操作: ${nav_hint}[c] 清空日志 | [0/回车] 返回主菜单: ${C_RESET}"
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
        elif [[ "$opt_act" == "c" || "$opt_act" == "C" ]]; then
            echo ""
            read -r -p "确认清空全部风险变动日志吗？(y/N): " confirm_clear
            if [[ "$confirm_clear" =~ ^[Yy]$ ]]; then
                : > "$ALERT_LOG"
                echo -e "${C_GREEN}✔ 告警日志已成功清空！${C_RESET}"
                sleep 0.8
                break
            fi
        fi
    done
}

# ==============================================================================
# 模块 7: 查看历史存档快照 (view_archives - 图形图表化美化版，双栈合并展示)
# ==============================================================================
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
        echo -e "${C_YELLOW}暂无任何历史存档数据，请先执行一次检测 (选项 9)${C_RESET}\n"
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
    print_module_header "🧹 清理与维护历史数据"

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
        1|2|3)
            local days=30
            [[ "$c_opt" == "2" ]] && days=90
            [[ "$c_opt" == "3" ]] && days=180
            local cutoff
            cutoff=$(date -d "$days days ago" +%Y-%m-%d 2>/dev/null || date -d "@$(( $(date +%s) - days*86400 ))" +%Y-%m-%d 2>/dev/null)
            local del_cnt=0
            for d in "$V4_DIR" "$V6_DIR"; do
                [[ ! -d "$d" ]] && continue
                for f in "$d"/*.json; do
                    [[ ! -f "$f" ]] && continue
                    local base
                    base=$(basename "$f" .json)
                    if [[ "${base:0:10}" < "$cutoff" ]]; then
                        rm -f "$f"
                        (( ++del_cnt ))
                    fi
                done
            done
            echo -e "\n${C_GREEN}已清理 $days 天前 (早于 $cutoff) 的旧存档数据 (共清理 $del_cnt 份)！${C_RESET}"
            ;;
        4)
            echo -ne "请输入保留的存档份数: "
            read -r keep_num
            if [[ "$keep_num" =~ ^[0-9]+$ ]] && (( keep_num > 0 )); then
                for d in "$V4_DIR" "$V6_DIR"; do
                    [[ ! -d "$d" ]] && continue
                    local all_f=()
                    for f in "$d"/*.json; do
                        [[ -f "$f" ]] && all_f+=("$f")
                    done
                    local total=${#all_f[@]}
                    if (( total > keep_num )); then
                        local sorted_f=()
                        mapfile -t sorted_f < <(printf "%s\n" "${all_f[@]}" | sort)
                        local diff=$((total - keep_num))
                        for (( k=0; k<diff; k++ )); do
                            rm -f "${sorted_f[$k]}"
                        done
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
            : > "$ALERT_LOG"
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
    local tmp_cron
    tmp_cron=$(mktemp 2>/dev/null || echo "/tmp/ipqa_cron.$$.$RANDOM")
    local remaining
    remaining=$(crontab -l 2>/dev/null | grep -vE 'ipqa(\.sh)?["'\''[:space:]]+--cron' | grep -v "# IPQA AUTO CHECK" || true)
    if [[ -n "$remaining" ]]; then
        echo "$remaining" > "$tmp_cron"
        crontab "$tmp_cron" 2>/dev/null || true
        rm -f "$tmp_cron"
    else
        crontab -r 2>/dev/null || true
    fi
    echo -e "${C_GREEN}✔ 定时检测任务已成功移除${C_RESET}"

    echo -e "\n${C_CYAN}▶ [2/3] 正在删除全局命令软链接...${C_RESET}"
    local links=("/usr/local/bin/ipqa" "$HOME/.local/bin/ipqa" "$HOME/bin/ipqa")
    for link in "${links[@]}"; do
        if [[ -L "$link" ]]; then
            local target
            target=$(readlink "$link" 2>/dev/null || true)
            # M-03, Q-05: 仅删除明确指向当前 IPQA 实例或本项目主程序的软链接
            if [[ "$link" -ef "$IPQA_HOME/ipqa.sh" || "$target" == "$IPQA_HOME"* || ( "$target" == *ipqa.sh && -f "$target" && $(grep -c "IP-Quality-Archive" "$target" 2>/dev/null || echo 0) -gt 0 ) ]]; then
                rm -f "$link" 2>/dev/null || sudo rm -f "$link" 2>/dev/null || true
                echo -e "${C_GREEN}✔ 已删除软链接 $link${C_RESET}"
            else
                echo -e "${C_GRAY}跳过软链接 $link (非本项目软链接: $target)${C_RESET}"
            fi
        elif [[ -f "$link" ]]; then
            if grep -qE "IP-Quality-Archive|IPQA" "$link" 2>/dev/null; then
                rm -f "$link" 2>/dev/null || sudo rm -f "$link" 2>/dev/null || true
                echo -e "${C_GREEN}✔ 已删除快捷脚本 $link${C_RESET}"
            fi
        fi
    done

    echo -e "\n${C_CYAN}▶ [3/3] 数据与配置目录清理${C_RESET}"
    echo -ne "${C_YELLOW}是否删除所有历史检测存档与配置 ($IPQA_HOME)? [y/N]: ${C_RESET}"
    read -r rm_data
    if [[ "$rm_data" == "y" || "$rm_data" == "Y" ]]; then
        if is_dangerous_path "$IPQA_HOME"; then
            echo -e "${C_RED}错误: IPQA_HOME 路径 ($IPQA_HOME) 属于危险系统路径，已拒绝删除！${C_RESET}"
        else
            rm -rf "$IPQA_HOME"
            echo -e "${C_GREEN}✔ 已彻底删除 $IPQA_HOME${C_RESET}"
        fi
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

    # M-08A: 使用统一 main 执行互斥锁
    if ! acquire_lock "main"; then
        echo -e "${C_YELLOW}⚠ 另有 IPQA 检测或更新任务正在运行中，已取消当前更新操作。${C_RESET}\n"
        exit 1
    fi
    trap cleanup_main_lock EXIT
    trap handle_interrupt INT
    trap handle_term TERM

    echo -e "${C_CYAN}正在检查并下载 IPQA 主程序最新版本...${C_RESET}"
    local tmp_file="$IPQA_HOME/ipqa.sh.tmp.$$.$RANDOM"
    local main_ok=false

    if curl -fsSL --connect-timeout 10 --max-time 60 -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/ipqa.sh?t=$(date +%s)" -o "$tmp_file" 2>/dev/null; then
        local sz
        sz=$(wc -c < "$tmp_file" 2>/dev/null || echo 0)
        if (( sz > 10000 )) && bash -n "$tmp_file" 2>/dev/null && grep -qE "IP-Quality-Archive|IPQA" "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$IPQA_HOME/ipqa.sh"
            sed -i 's/\r$//' "$IPQA_HOME/ipqa.sh" 2>/dev/null || true
            chmod 755 "$IPQA_HOME/ipqa.sh" 2>/dev/null || chmod +x "$IPQA_HOME/ipqa.sh"
            date +%s > "$IPQA_HOME/.last_script_update" 2>/dev/null || true
            echo -e "${C_GREEN}✔ IPQA 主程序已更新至最新版本${C_RESET}"
            main_ok=true
        else
            rm -f "$tmp_file"
            echo -e "${C_RED}错误: 下载的主程序脚本校验失败 (语法错误或内容不完整)${C_RESET}\n"
        fi
    else
        rm -f "$tmp_file"
        echo -e "${C_RED}错误: 无法连接 GitHub 下载主程序，请检查网络${C_RESET}\n"
    fi

    echo -e "\n${C_CYAN}正在同步 IPQuality 检测核心最新版本...${C_RESET}"
    local tmp_core="$IPQA_HOME/ip.sh.tmp.$$.$RANDOM"
    local core_ok=false

    if curl -fsSL --connect-timeout 10 --max-time 60 https://IP.Check.Place -o "$tmp_core" 2>/dev/null || \
       curl -fsSL --connect-timeout 10 --max-time 60 https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh -o "$tmp_core" 2>/dev/null; then
        local csz
        csz=$(wc -c < "$tmp_core" 2>/dev/null || echo 0)
        # S-01: 必须先通过 bash -n 语法校验与项目特征比对
        if (( csz > 3000 )) && bash -n "$tmp_core" 2>/dev/null && grep -q -E '(script_version|IP\.Check\.Place|IPQuality|Check_DNS)' "$tmp_core" 2>/dev/null; then
            sed -i 's/\r$//' "$tmp_core" 2>/dev/null || true
            if patch_ip_script "$tmp_core" && bash -n "$tmp_core" 2>/dev/null; then
                chmod 755 "$tmp_core" 2>/dev/null || chmod +x "$tmp_core" 2>/dev/null || true
                mv -f "$tmp_core" "$IP_SCRIPT"
                date +%s > "$IPQA_HOME/.last_core_update" 2>/dev/null || true
                rm -f "$IPQA_HOME/.last_auto_update" 2>/dev/null || true
                echo -e "${C_GREEN}✔ IPQuality 检测核心已成功同步至最新版本！${C_RESET}"
                core_ok=true
            else
                rm -f "$tmp_core"
                echo -e "${C_YELLOW}⚠ 检测核心 patch 规则应用或语法校验未通过，已保留本地版本${C_RESET}"
            fi
        else
            rm -f "$tmp_core"
            echo -e "${C_YELLOW}⚠ 检测核心内容不完整或语法校验未通过，已保留本地版本${C_RESET}"
        fi
    else
        rm -f "$tmp_core"
        echo -e "${C_YELLOW}⚠ 检测核心下载超时，已保留本地版本${C_RESET}"
    fi

    cleanup_main_lock
    trap - EXIT INT TERM

    if [[ "$main_ok" == "true" && "$core_ok" == "true" ]]; then
        echo -e "\n${C_GREEN}${C_BOLD}🎉 IPQA 系统及检测核心已全部更新完成！${C_RESET}\n"
        exit 0
    elif [[ "$main_ok" == "true" ]]; then
        echo -e "\n${C_YELLOW}${C_BOLD}✔ IPQA 主程序已更新完成，检测核心保持现有版本。${C_RESET}\n"
        exit 0
    else
        echo -e "\n${C_RED}${C_BOLD}✗ 更新失败，未更改本地脚本。${C_RESET}\n"
        exit 1
    fi
}

# ==============================================================================
# 命令行配置: 启用/禁用 IPQA 脚本本身自动更新 (set_auto_update)
# ==============================================================================
set_auto_update() {
    local action="$1"
    load_config
    case "$action" in
        enable|on|true|1)
            AUTO_UPDATE_SCRIPT="true"
            save_config
            echo -e "${C_GREEN}✔ IPQA 脚本自身自动更新已启用 (默认模式)${C_RESET}"
            echo -e "  已保存至配置: ${C_GRAY}$CONFIG_FILE${C_RESET}"
            echo -e "  IPQA 将在每日检测时自动从 GitHub 同步主脚本最新版本。"
            log_msg "INFO" "用户通过命令行启用了 IPQA 脚本自身自动更新"
            ;;
        disable|off|false|0)
            AUTO_UPDATE_SCRIPT="false"
            save_config
            echo -e "${C_YELLOW}✔ IPQA 脚本自身自动更新已禁用${C_RESET}"
            echo -e "  已保存至配置: ${C_GRAY}$CONFIG_FILE${C_RESET}"
            echo -e "  IPQA 主脚本将不会被每日自动覆盖更新（保留本地修改与当前版本）。"
            echo -e "  ${C_CYAN}提示: 上游 IPQuality 检测核心仍正常每日检测更新；您亦可随时通过 'ipqa --update' 手动全量更新。${C_RESET}"
            log_msg "INFO" "用户通过命令行禁用了 IPQA 脚本自身自动更新"
            ;;
        status|"")
            local status_text="${C_GREEN}开启 (默认)${C_RESET}"
            if [[ "$AUTO_UPDATE_SCRIPT" == "false" || "$AUTO_UPDATE_SCRIPT" == "off" || "$AUTO_UPDATE_SCRIPT" == "0" ]]; then
                status_text="${C_YELLOW}已禁用${C_RESET}"
            fi
            echo -e "当前脚本自动更新状态: $status_text"
            echo -e "配置文件路径: ${C_GRAY}$CONFIG_FILE${C_RESET}"
            echo ""
            echo "命令行控制指令:"
            echo "  ipqa --enable-auto-update   (启用脚本自身自动更新)"
            echo "  ipqa --disable-auto-update  (禁用脚本自身自动更新)"
            ;;
        *)
            echo -e "${C_RED}错误: 未知参数 '$action'${C_RESET}"
            echo "用法: ipqa --auto-update (查看状态) 或 ipqa --enable-auto-update / ipqa --disable-auto-update"
            return 1
            ;;
    esac
}

# ==============================================================================
# 状态概况输出 (CLI)
# ==============================================================================
show_status() {
    local use_color="false"
    if [[ "$*" =~ --color ]]; then
        use_color="true"
    fi

    local c_reset="" c_bold="" c_cyan="" c_green="" c_yellow="" c_red="" c_gray=""
    if [[ "$use_color" == "true" ]]; then
        c_reset="$C_RESET"
        c_bold="$C_BOLD"
        c_cyan="$C_CYAN"
        c_green="$C_GREEN"
        c_yellow="$C_YELLOW"
        c_red="$C_RED"
        c_gray="$C_GRAY"
    fi

    load_config

    local latest_v4 latest_v6
    latest_v4=$(get_latest_archive "$V4_DIR")
    latest_v6=$(get_latest_archive "$V6_DIR")

    local ip_v4="未检测"
    local ip_v6="无"
    local asn="--"
    local org="--"
    local loc="--"
    local last_check="从无检测记录"

    local ref_archive="${latest_v4:-$latest_v6}"
    if [[ -n "$ref_archive" ]]; then
        IFS=$'\x1f' read -r ref_ip asn org city country < <(
            jq -r '[
                (.Head.IP // "未知"),
                (.Info.ASN // "--"),
                (.Info.Organization // "--"),
                (.Info.City.Name // ""),
                (.Info.Region.Name // "")
            ] | join("\u001f")' "$ref_archive" 2>/dev/null
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
    fi

    if [[ -n "$latest_v4" ]]; then
        ip_v4=$(jq -r '.Head.IP // "未知"' "$latest_v4" 2>/dev/null)
    fi
    if [[ -n "$latest_v6" ]]; then
        ip_v6=$(jq -r '.Head.IP // "无"' "$latest_v6" 2>/dev/null)
    fi

    # 统计数量与时间跨度
    local count_v4 count_v6
    count_v4=$(count_json_files "$V4_DIR")
    count_v6=$(count_json_files "$V6_DIR")

    local latest_file
    latest_file=$(find "$V4_DIR" "$V6_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | sort -r | head -n 1)
    if [[ -n "$latest_file" ]]; then
        last_check=$(fmt_timestamp "$(basename "$latest_file" .json)")
    fi

    # 定时检测状态 (UI-01, N-01: 提取执行周期并显示友好名称)
    local cron_status="未开启"
    local cron_colored="未开启"
    local cron_line
    cron_line=$(crontab -l 2>/dev/null | grep -E 'ipqa(\.sh)?["'\''[:space:]]+--cron' | head -n 1 || true)
    if [[ -n "$cron_line" ]]; then
        cron_status=$(get_cron_friendly_name "$cron_line")
        if [[ "$use_color" == "true" ]]; then
            cron_colored="${c_green}开启 [${cron_status}]${c_reset}"
        else
            cron_colored="开启 [${cron_status}]"
        fi
    else
        if [[ "$use_color" == "true" ]]; then
            cron_colored="${c_gray}未开启${c_reset}"
        fi
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
        if [[ "$use_color" == "true" ]]; then
            ver_display="${c_gray}(Core: ${core_ver})${c_reset}"
        else
            ver_display="(Core: ${core_ver})"
        fi
    fi

    echo ""
    echo -e "${c_cyan}${c_bold}══════════════════════════════════════════════════════════════════════${c_reset}"
    echo -e "   ${c_bold}${c_green}🔍 IP 质量存档监测系统 (IPQA) 状态概况${c_reset}  ${ver_display}"
    echo -e "${c_cyan}${c_bold}══════════════════════════════════════════════════════════════════════${c_reset}"
    echo ""
    echo -e "  ${c_cyan}📡 节点网络:${c_reset} ${c_bold}${ip_v4}${c_reset} (IPv4)  ${c_gray}│${c_reset}  ${c_bold}${ip_v6}${c_reset} (IPv6)"
    echo -e "  ${c_cyan}🏢 归属信息:${c_reset} ${asn_display}  ${c_gray}│${c_reset}  📍 ${loc}"
    echo -e "  ${c_cyan}⏰ 上次检测:${c_reset} ${last_check}"
    echo -e "  ${c_cyan}📦 历史存档:${c_reset} IPv4: ${c_green}${count_v4}${c_reset} 份  ${c_gray}│${c_reset}  IPv6: ${c_green}${count_v6}${c_reset} 份"
    local script_update_display=""
    if [[ "$AUTO_UPDATE_SCRIPT" == "false" || "$AUTO_UPDATE_SCRIPT" == "off" || "$AUTO_UPDATE_SCRIPT" == "0" ]]; then
        if [[ "$use_color" == "true" ]]; then
            script_update_display="${c_yellow}已禁用${c_reset}"
        else
            script_update_display="已禁用"
        fi
    else
        if [[ "$use_color" == "true" ]]; then
            script_update_display="${c_green}开启 (默认)${c_reset}"
        else
            script_update_display="开启 (默认)"
        fi
    fi

    echo -e "  ${c_cyan}🔄 定时检测:${c_reset} ${cron_colored}  ${c_gray}│${c_reset}  ${c_cyan}🆙 脚本自更:${c_reset} ${script_update_display}"
    echo ""
    echo -e "${c_gray}── ${c_cyan}🔔 最近风险变化提醒 (近 3 日)${c_reset} ${c_gray}──────────────────────────────────────${c_reset}"

    # 获取近三日有效日期（优先考虑有检测记录或告警记录的最近 3 个日期，并结合当前系统日期）
    local target_dates=()
    mapfile -t target_dates < <(
        {
            date +%Y-%m-%d
            date -d '1 day ago' +%Y-%m-%d 2>/dev/null || true
            date -d '2 days ago' +%Y-%m-%d 2>/dev/null || true
            if [[ -f "$ALERT_LOG" ]]; then
                cut -d' ' -f1 "$ALERT_LOG" 2>/dev/null
            fi
            if [[ -d "$V4_DIR" ]]; then
                for f in "$V4_DIR"/*.json; do
                    [[ -f "$f" ]] && basename "$f" | cut -d'_' -f1
                done
            fi
            if [[ -d "$V6_DIR" ]]; then
                for f in "$V6_DIR"/*.json; do
                    [[ -f "$f" ]] && basename "$f" | cut -d'_' -f1
                done
            fi
        } | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort -u -r | head -n 3
    )

    local matched_alerts=()
    if [[ -f "$ALERT_LOG" && ${#target_dates[@]} -gt 0 ]]; then
        local pattern
        pattern="^($(IFS='|'; echo "${target_dates[*]}")) "
        mapfile -t matched_alerts < <(grep -E "$pattern" "$ALERT_LOG" 2>/dev/null | grep -v "首次完成数据存档监测" | sort -t'|' -k1 -r)
    fi

    if (( count_v4 + count_v6 == 0 )); then
        echo -e "  • 暂无任何历史检测存档数据"
    elif (( ${#matched_alerts[@]} == 0 )); then
        local recent_archives=0
        for d in "$V4_DIR" "$V6_DIR"; do
            [[ ! -d "$d" ]] && continue
            for f in "$d"/*.json; do
                [[ ! -f "$f" ]] && continue
                local b
                b=$(basename "$f" | cut -d'_' -f1)
                for td in "${target_dates[@]}"; do
                    if [[ "$b" == "$td" ]]; then
                        (( ++recent_archives ))
                        break
                    fi
                done
            done
        done
        if (( recent_archives == 0 )); then
            echo -e "  • 近三日无检测记录 (历史检测保持原有状态)"
        else
            echo -e "  • 近三日未检测到新的状态变化记录"
        fi
    else
        local i=1
        for alt in "${matched_alerts[@]}"; do
            [[ -z "$alt" ]] && continue
            local a_time a_level a_msg a_ver
            IFS='|' read -r a_time a_level a_msg a_ver <<< "$alt"

            local badge=""
            case "$a_level" in
                CRITICAL) badge="${c_red}${c_bold}[严重]${c_reset}" ;;
                WARNING)  badge="${c_yellow}[警告]${c_reset}" ;;
                INFO)     badge="${c_cyan}[提示]${c_reset}" ;;
                *)        badge="${c_gray}[记录]${c_reset}" ;;
            esac

            local ver_badge="${a_ver:-IPv4}"
            if [[ "$use_color" == "true" ]]; then
                if [[ "$a_ver" == "IPv6" ]]; then
                    ver_badge="${c_cyan}IPv6${c_reset}"
                else
                    ver_badge="${c_green}IPv4${c_reset}"
                fi
            fi

            local idx
            printf -v idx "%2d" "$i"
            echo -e "  [${idx}] ${a_time} │ ${ver_badge} │ ${badge} │ ${a_msg}"
            (( ++i ))
        done
    fi

    echo -e "${c_cyan}${c_bold}══════════════════════════════════════════════════════════════════════${c_reset}"
    echo ""
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
        IFS=$'\x1f' read -r ip_v4 asn org city country < <(
            jq -r '[
                (.Head.IP // "未知"),
                (.Info.ASN // "--"),
                (.Info.Organization // "--"),
                (.Info.City.Name // ""),
                (.Info.Region.Name // "")
            ] | join("\u001f")' "$latest_v4" 2>/dev/null
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

    # 统计数量
    local count_v4 count_v6
    count_v4=$(count_json_files "$V4_DIR")
    count_v6=$(count_json_files "$V6_DIR")

    # 定时检测状态 (UI-01, N-01: 提取执行周期并显示友好名称)
    local cron_status="未开启"
    local cron_colored="${C_GRAY}未开启${C_RESET}"
    local cron_line
    cron_line=$(crontab -l 2>/dev/null | grep -E 'ipqa(\.sh)?["'\''[:space:]]+--cron' | head -n 1 || true)
    if [[ -n "$cron_line" ]]; then
        cron_status=$(get_cron_friendly_name "$cron_line")
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
    local script_update_hint=""
    if [[ "$AUTO_UPDATE_SCRIPT" == "false" || "$AUTO_UPDATE_SCRIPT" == "off" || "$AUTO_UPDATE_SCRIPT" == "0" ]]; then
        script_update_hint="${C_YELLOW}(脚本自更: 已禁用)${C_RESET}"
    else
        script_update_hint="${C_GRAY}(每天静默更新核心与脚本)${C_RESET}"
    fi
    echo -e "  ${C_CYAN}🔄 定时检测:${C_RESET} ${cron_colored} ${script_update_hint}"
    echo ""
    echo -e "${C_GRAY}── ${C_CYAN}🔔 最近风险变化提醒${C_RESET} ${C_GRAY}───────────────────────────────────────────────${C_RESET}"

    # 按天聚合展示最近 3 天的风险变化统计与智能摘要
    render_daily_alerts_summary 3
    echo ""
    echo -e "${C_GRAY}── ${C_CYAN}📋 功能菜单导航${C_RESET} ${C_GRAY}───────────────────────────────────────────────────${C_RESET}"
    echo -e "  ${C_BOLD}[1]${C_RESET} 📊 IP 类型属性变动        ${C_BOLD}[7]${C_RESET}  📋 历史存档图表快照"
    echo -e "  ${C_BOLD}[2]${C_RESET} 📈 综合风险评分图         ${C_BOLD}[8]${C_RESET}  🔧 配置定时任务"
    echo -e "  ${C_BOLD}[3]${C_RESET} 🔬 风险因子综合矩阵       ${C_BOLD}[9]${C_RESET}  🔄 立即执行检测"
    echo -e "  ${C_BOLD}[4]${C_RESET} 🎬 流媒体与AI解锁         ${C_BOLD}[10]${C_RESET} 🧹 清理历史数据"
    echo -e "  ${C_BOLD}[5]${C_RESET} 📬 邮件与黑名单监测       ${C_BOLD}[0]${C_RESET}  🚪 退出系统"
    echo -e "  ${C_BOLD}[6]${C_RESET} 🔔 风险变化提醒历史       ${C_BOLD}[x]${C_RESET}  ❌ 卸载系统"
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
            6) show_alerts_history ;;
            7) view_archives ;;
            8) setup_cron ;;
            9)
                clear
                run_check false
                read -r -p "检测完毕，按回车键返回主菜单..."
                ;;
            10) cleanup_data ;;
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
        for arg in "$@"; do
            [[ "$arg" == "--no-auto-update" || "$arg" == "--disable-auto-update" ]] && OVERRIDE_AUTO_UPDATE_SCRIPT="false"
        done
        run_check true
        exit $?
        ;;
    --check)
        check_dependencies
        for arg in "$@"; do
            [[ "$arg" == "--no-auto-update" || "$arg" == "--disable-auto-update" ]] && OVERRIDE_AUTO_UPDATE_SCRIPT="false"
        done
        run_check false
        exit $?
        ;;
    --enable-auto-update|enable-auto-update)
        check_dependencies
        set_auto_update "enable" || exit $?
        exit 0
        ;;
    --disable-auto-update|disable-auto-update)
        check_dependencies
        set_auto_update "disable" || exit $?
        exit 0
        ;;
    --auto-update|auto-update)
        check_dependencies
        set_auto_update "${2:-status}" || exit $?
        exit 0
        ;;
    --no-auto-update)
        OVERRIDE_AUTO_UPDATE_SCRIPT="false"
        if [[ "$2" == "--cron" ]]; then
            check_dependencies
            run_check true
            exit $?
        elif [[ "$2" == "--check" ]]; then
            check_dependencies
            run_check false
            exit $?
        else
            check_dependencies
            set_auto_update "disable"
        fi
        exit 0
        ;;
    --status|status)
        check_dependencies
        show_status "$@"
        ;;
    --update|update)
        update_ipqa
        ;;
    --uninstall|uninstall)
        uninstall_ipqa
        ;;
    --help|-h|help)
        echo "IP Quality Archive (IPQA)"
        echo "用法: ipqa [选项]"
        echo ""
        echo "选项:"
        echo "  (无参数)                启动交互式终端图形界面 (TUI)"
        echo "  --check                 立即执行一次检测并生成存档与告警"
        echo "  --cron                  静默模式执行检测 (专用于 crontab 定时任务，自动同步最新核心)"
        echo "  --status                查看当前状态概况与近三日风险变化详情 (纯文本输出适配远程运维，支持 --color)"
        echo "  --update                一键从 GitHub 在线更新 IPQA 主程序与检测核心"
        echo "  --enable-auto-update    启用每日自动同步更新 IPQA 脚本本身 (默认开启)"
        echo "  --disable-auto-update   禁用每日自动同步更新 IPQA 脚本本身 (保留本地修改与版本)"
        echo "  --auto-update           查看当前脚本自身自动更新状态"
        echo "  --test                  运行系统环境、依赖与配置健康自检"
        echo "  --uninstall             干净卸载 IPQA 并清理任务与软链接"
        echo "  --help, -h              显示本帮助信息"
        ;;
    --test)
        echo "正在执行 IPQA 系统自检测试..."
        pass=true
        echo -ne "  [1/5] 核心依赖检查 (bash, jq, curl): "
        missing=()
        for cmd in bash jq curl; do
            command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
        done
        if [[ ${#missing[@]} -eq 0 ]]; then
            if command -v crontab >/dev/null 2>&1; then
                echo "通过 (含 crontab)"
            else
                echo "通过 (提示: 未检出 crontab，定时检测功能将受限)"
            fi
        else
            echo "缺失核心依赖 (${missing[*]})"
            pass=false
        fi

        echo -ne "  [2/5] 目录与配置检查: "
        if [[ -d "$V4_DIR" && -d "$V6_DIR" && -f "$CONFIG_FILE" ]]; then
            echo "通过"
        else
            echo "已就绪"
            mkdir -p "$V4_DIR" "$V6_DIR" "$IPQA_HOME/logs" 2>/dev/null || true
            [[ ! -f "$CONFIG_FILE" ]] && save_config
        fi

        echo -ne "  [3/5] 检测核心检查 ($IP_SCRIPT): "
        if [[ -f "$IP_SCRIPT" && -s "$IP_SCRIPT" ]]; then
            if bash -n "$IP_SCRIPT" 2>/dev/null; then
                echo "通过"
            else
                echo "语法校验异常"
                pass=false
            fi
        else
            echo "未下载 (首次检测时将自动同步)"
        fi

        echo -ne "  [4/5] 锁与日志机制检查: "
        if acquire_lock "test_lock"; then
            release_lock "test_lock"
            echo "通过"
        else
            echo "锁机制异常"
            pass=false
        fi

        echo -ne "  [5/5] 数据解析与 JSON 支持检查: "
        if echo '{"test":"ok"}' | jq -e '.test == "ok"' >/dev/null 2>&1; then
            echo "通过"
        else
            echo "jq JSON 解析异常"
            pass=false
        fi

        if [[ "$pass" == "true" ]]; then
            echo -e "\n自检结果: 全部通过，IPQA 运行环境健康。"
            exit 0
        else
            echo -e "\n自检结果: 存在异常，请根据上方提示排查。"
            exit 1
        fi
        ;;
    "")
        main_loop
        ;;
    *)
        echo -e "${C_RED}错误: 未知选项 '$1'${C_RESET}\n"
        echo "请运行 'ipqa --help' 查看可用选项。"
        exit 1
        ;;
esac
