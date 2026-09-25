#!/usr/bin/env bash
# ==============================================================================
# IP Quality Archive (IPQA) - 一键安装脚本
# Description: 自动化安装 IPQA 监测系统及必要依赖 (jq, curl, cron)
# GitHub: https://github.com/Chen017/IP-Quality-Archive
# ==============================================================================

set -e

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_CYAN="\033[36m"
C_GRAY="\033[90m"

ACTION="install"
NON_INTERACTIVE=false
PURGE_DATA=false
INSTALL_DIR="${IPQA_DIR:-$HOME/.ipqa}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查是否为危险或系统根路径 (M-04A, M-04B)
is_dangerous_path() {
    local target="$1"
    [[ -z "$target" ]] && return 0
    local canon
    canon=$(cd "$target" 2>/dev/null && pwd -P || true)
    [[ -z "$canon" ]] && canon="$target"
    canon="${canon%/}"
    [[ -z "$canon" ]] && return 0

    # 1. 拦截根路径及任意单层根路径 (如 /usr, /var, /etc, /opt)
    if [[ "$canon" == "" || "$canon" == "/" || "$canon" =~ ^/[^/]+$ ]]; then
        return 0
    fi

    # 2. 拦截用户主目录
    if [[ -n "$HOME" && "$canon" == "${HOME%/}" ]]; then
        return 0
    fi

    # 3. 拦截常见系统与软件核心目录
    case "$canon" in
        /usr/*|/var/*|/etc/*|/opt/*|/boot/*|/dev/*|/sys/*|/proc/*|/run/*|/tmp/*)
            case "$canon" in
                /usr/local|/usr/local/bin|/usr/local/sbin|/usr/local/lib*|/usr/local/share|/usr/local/etc|/usr/bin|/usr/sbin|/usr/lib*|/usr/share*)
                    return 0 ;;
                /var/log|/var/lib*|/var/run|/var/spool|/var/cache|/var/backups)
                    return 0 ;;
                /etc|/etc/*)
                    return 0 ;;
                /tmp|/var/tmp)
                    return 0 ;;
            esac
            ;;
    esac

    # 4. 拦截 $HOME 下的关键系统/桌面目录
    if [[ -n "$HOME" ]]; then
        local h="${HOME%/}"
        case "$canon" in
            "$h/.local"|"$h/.local/bin"|"$h/.config"|"$h/bin"|"$h/Desktop"|"$h/Documents"|"$h/Downloads")
                return 0 ;;
        esac
    fi

    return 1
}

# 卸载处理函数
do_uninstall() {
    echo -e "${C_CYAN}${C_BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║             🧹 IP 质量存档监测系统 (IPQA) 卸载程序               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}⚠️  警告: 即将执行 IPQA 监测系统卸载流程！${C_RESET}\n"

    if [[ "$NON_INTERACTIVE" == "false" ]]; then
        echo -ne "${C_RED}确认要卸载 IPQA 吗? [y/N]: ${C_RESET}"
        read -r confirm_un
        if [[ "$confirm_un" != "y" && "$confirm_un" != "Y" ]]; then
            echo -e "\n${C_GRAY}已取消卸载。${C_RESET}"
            exit 0
        fi
    fi

    echo -e "\n${C_CYAN}▶ [1/3] 正在清理定时任务...${C_RESET}"
    if command -v crontab >/dev/null 2>&1; then
        local remaining
        remaining=$(crontab -l 2>/dev/null | grep -vE 'ipqa(\.sh)?["'\''[:space:]]+--cron' | grep -v "# IPQA AUTO CHECK" || true)
        if [[ -n "$remaining" ]]; then
            echo "$remaining" | crontab -
        else
            crontab -r 2>/dev/null || true
        fi
        echo -e "${C_GREEN}✔ 定时检测任务已成功移除${C_RESET}"
    else
        echo -e "${C_GRAY}未安装 crontab，跳过${C_RESET}"
    fi

    echo -e "\n${C_CYAN}▶ [2/3] 正在删除全局命令软链接...${C_RESET}"
    local links=("/usr/local/bin/ipqa" "$HOME/.local/bin/ipqa" "$HOME/bin/ipqa")
    for link in "${links[@]}"; do
        if [[ -L "$link" ]]; then
            local target
            target=$(readlink "$link" 2>/dev/null || true)
            if [[ "$target" == "$INSTALL_DIR"* || "$target" == *ipqa* ]]; then
                rm -f "$link" 2>/dev/null || sudo rm -f "$link" 2>/dev/null || true
                echo -e "${C_GREEN}✔ 已删除软链接 $link -> $target${C_RESET}"
            else
                echo -e "${C_GRAY}跳过软链接 $link (非 IPQA 目标: $target)${C_RESET}"
            fi
        elif [[ -f "$link" ]]; then
            if grep -qE "IP-Quality-Archive|IPQA" "$link" 2>/dev/null; then
                rm -f "$link" 2>/dev/null || sudo rm -f "$link" 2>/dev/null || true
                echo -e "${C_GREEN}✔ 已删除命令文件 $link${C_RESET}"
            else
                echo -e "${C_GRAY}跳过文件 $link (非 IPQA 程序)${C_RESET}"
            fi
        fi
    done

    echo -e "\n${C_CYAN}▶ [3/3] 数据与配置目录清理${C_RESET}"
    local rm_data="n"
    if [[ "$PURGE_DATA" == "true" ]]; then
        rm_data="y"
    elif [[ "$NON_INTERACTIVE" == "true" ]]; then
        rm_data="n"
    else
        echo -ne "${C_YELLOW}是否删除所有历史检测存档与配置 ($INSTALL_DIR)? [y/N]: ${C_RESET}"
        read -r rm_data
    fi

    if [[ "$rm_data" == "y" || "$rm_data" == "Y" ]]; then
        if is_dangerous_path "$INSTALL_DIR"; then
            echo -e "${C_RED}错误: 检测到系统级或危险路径 ($INSTALL_DIR)，拒绝删除！${C_RESET}"
        else
            rm -rf "$INSTALL_DIR"
            echo -e "${C_GREEN}✔ 已彻底删除 $INSTALL_DIR${C_RESET}"
        fi
    else
        echo -e "${C_GRAY}ℹ️ 已保留历史存档与配置目录: $INSTALL_DIR${C_RESET}"
    fi

    echo -e "\n${C_GREEN}${C_BOLD}✔ IPQA 已完全卸载！感谢使用。${C_RESET}\n"
    exit 0
}

# 解析参数
AUTO_UPDATE_SCRIPT=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            NON_INTERACTIVE=true
            shift
            ;;
        -d|--dir)
            if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
                echo -e "${C_RED}错误: -d/--dir 需要指定有效的路径参数${C_RESET}"
                exit 1
            fi
            INSTALL_DIR="$2"
            shift 2
            ;;
        --purge|--remove-data)
            PURGE_DATA=true
            shift
            ;;
        --disable-auto-update|--no-auto-update)
            AUTO_UPDATE_SCRIPT=false
            shift
            ;;
        --enable-auto-update)
            AUTO_UPDATE_SCRIPT=true
            shift
            ;;
        --uninstall|uninstall)
            ACTION="uninstall"
            shift
            ;;
        -h|--help)
            echo "IPQA 安装与管理脚本使用说明:"
            echo "  bash install.sh [选项]"
            echo ""
            echo "选项:"
            echo "  -y, --yes              非交互式操作，全部采用默认确认 (卸载时默认保留数据)"
            echo "  -d, --dir <路径>       指定安装/数据目录 (默认: ~/.ipqa)"
            echo "  --purge, --remove-data 卸载时彻底删除数据与存档目录 (与 --uninstall 配合使用)"
            echo "  --disable-auto-update  安装时禁用每日自动同步更新 IPQA 脚本本身"
            echo "  --enable-auto-update   安装时启用每日自动同步更新 IPQA 脚本本身 (默认开启)"
            echo "  --uninstall            干净卸载 IPQA，清理定时任务、命令软链接与环境"
            echo "  -h, --help             显示本帮助信息"
            exit 0
            ;;
        *)
            echo -e "${C_RED}错误: 未知参数 '$1'，使用 -h/--help 查看使用说明${C_RESET}"
            exit 1
            ;;
    esac
done

# 解析参数后的路径预校验与绝对路径转换 (M-04B, N-08)
INSTALL_DIR="$(mkdir -p "$INSTALL_DIR" 2>/dev/null && cd "$INSTALL_DIR" 2>/dev/null && pwd -P || echo "$INSTALL_DIR")"
if is_dangerous_path "$INSTALL_DIR"; then
    echo -e "${C_RED}错误: 指定的安装目录为危险系统路径 ($INSTALL_DIR)，终止安装${C_RESET}"
    exit 1
fi

if [[ "$ACTION" == "uninstall" ]]; then
    do_uninstall
fi

IS_UPDATE=false
if [[ -f "$INSTALL_DIR/ipqa.sh" ]]; then
    IS_UPDATE=true
fi

if [[ "$IS_UPDATE" == "true" ]]; then
    echo -e "${C_CYAN}${C_BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║             🔄 IP 质量存档监测系统 (IPQA) 在线更新               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}"
    echo -e "${C_GREEN}检测到已安装 IPQA，正在更新主程序与检测引擎 (历史数据与配置将完整保留)...${C_RESET}\n"
else
    echo -e "${C_CYAN}${C_BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║             🔍 IP 质量存档监测系统 (IPQA) 一键安装               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}"
fi

# 1. 检测系统与包管理器
echo -e "${C_BOLD}[1/5] 检查系统环境与必要依赖...${C_RESET}"

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# 检查操作系统支持 (仅支持 Debian / Ubuntu 系 GNU/Linux 环境)
check_os_support() {
    local os_file="${IPQA_OS_RELEASE_FILE:-/etc/os-release}"
    local is_supported=false
    if [[ -f "$os_file" ]]; then
        local os_id="" os_like=""
        os_id=$(grep -E '^ID=' "$os_file" 2>/dev/null | cut -d= -f2 | tr -d '"'\''')
        os_like=$(grep -E '^ID_LIKE=' "$os_file" 2>/dev/null | cut -d= -f2 | tr -d '"'\''')
        if [[ "$os_id" == "debian" || "$os_id" == "ubuntu" ]] || [[ "$os_like" =~ debian|ubuntu ]]; then
            is_supported=true
        fi
    fi

    if [[ "$is_supported" != "true" ]]; then
        echo -e "${C_RED}Unsupported distribution.${C_RESET}"
        echo -e "${C_RED}IPQA currently supports Debian and Ubuntu based systems.${C_RESET}"
        return 1
    fi
    return 0
}

if ! check_os_support; then
    exit 1
fi

# 检查 bash 版本 (需 >= 4.2 以支持负下标及 mapfile 等特性)
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2) )); then
    echo -e "${C_RED}错误: Bash 版本必须 >= 4.2 (当前版本: ${BASH_VERSION:-未知})${C_RESET}"
    exit 1
fi

can_sudo() {
    if ! has_cmd sudo; then
        return 1
    fi
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        sudo -n true >/dev/null 2>&1
    else
        sudo -v >/dev/null 2>&1 || sudo -n true >/dev/null 2>&1
    fi
}

run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif can_sudo; then
        sudo "$@"
    else
        return 1
    fi
}

pkg_install() {
    local pkgs=("$@")
    if [[ ${#pkgs[@]} -eq 0 ]]; then return 0; fi

    echo -e "${C_YELLOW}正在安装依赖包: ${pkgs[*]}...${C_RESET}"
    if has_cmd apt-get; then
        run_as_root apt-get update -qq && run_as_root apt-get install -y -qq "${pkgs[@]}"
    else
        echo -e "${C_RED}未能识别系统包管理器 (仅支持 Debian/Ubuntu apt-get)，请手动安装: ${pkgs[*]}${C_RESET}"
        return 1
    fi
}

needed_pkgs=()
has_cmd jq || needed_pkgs+=("jq")
has_cmd curl || needed_pkgs+=("curl")

# 匹配 Debian/Ubuntu 下 cron 软件包
if ! has_cmd crontab; then
    if has_cmd apt-get; then
        needed_pkgs+=("cron")
    fi
fi

# 检查 dig 与 nslookup (Debian/Ubuntu 为 dnsutils)，保证流媒体/AI 解锁原生与 DNS 判定的准确性
if ! has_cmd dig || ! has_cmd nslookup; then
    if has_cmd apt-get; then
        needed_pkgs+=("dnsutils")
    fi
fi

if [[ ${#needed_pkgs[@]} -gt 0 ]]; then
    pkg_install "${needed_pkgs[@]}" || true
fi

# 重新核验必要与推荐依赖
if ! has_cmd jq; then
    echo -e "${C_RED}错误: jq 未安装成功，请手动执行 apt-get install -y jq${C_RESET}"
    exit 1
fi
if ! has_cmd curl; then
    echo -e "${C_RED}错误: curl 未安装成功，请手动执行 apt-get install -y curl${C_RESET}"
    exit 1
fi
if ! has_cmd crontab; then
    echo -e "${C_YELLOW}⚠ 警告: 未检测到 crontab，定时自动检测功能将受限 (可安装 cron)${C_RESET}"
fi
if ! has_cmd dig && ! has_cmd nslookup; then
    echo -e "${C_YELLOW}⚠ 提示: 未检测到 dig/nslookup (dnsutils)，DNS 解锁精确判定可能受限${C_RESET}"
fi
echo -e "${C_GREEN}✔ 必要依赖检查通过 (jq, curl, bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]})${C_RESET}"

# 2. 创建目录结构
echo -e "\n${C_BOLD}[2/5] 创建系统运行目录: ${C_CYAN}$INSTALL_DIR${C_RESET}"
if ! mkdir -p "$INSTALL_DIR/data/v4" "$INSTALL_DIR/data/v6" "$INSTALL_DIR/logs" 2>/dev/null; then
    echo -e "${C_RED}错误: 无法创建运行目录 $INSTALL_DIR，权限不足${C_RESET}"
    exit 1
fi
chmod 700 "$INSTALL_DIR" "$INSTALL_DIR/data" "$INSTALL_DIR/data/v4" "$INSTALL_DIR/data/v6" "$INSTALL_DIR/logs" 2>/dev/null || true
echo -e "${C_GREEN}✔ 运行目录创建完成 (权限已设为 700)${C_RESET}"

# 安全下载函数 (校验 HTTP 状态、文件大小、特定项目指纹与 Bash 语法) (S-01)
# 上游 ip.sh 修补函数 (针对临时文件或指定目标执行 patch)
patch_ip_script() {
    local target="$1"
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
        sed -i 's@currentTerritory//'\''|cut -f3 -d'\''"'\''@currentTerritory":\\s*"[A-Za-z]{2}"'\''|head -n 1|cut -d"\\"" -f4@g' "$target" 2>/dev/null || true
    fi

    return 0
}

# 安全下载函数 (校验 HTTP 状态、文件大小、特定项目指纹与 Bash 语法) (S-01)
safe_download() {
    local url="$1"
    local dest="$2"
    local ptype="${3:-}"
    local tmp="${dest}.tmp.$$.$RANDOM"

    if ! curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi

    local min_size=3000
    [[ "$ptype" == "ipqa" ]] && min_size=10000

    if [[ ! -s "$tmp" ]] || [[ $(wc -c < "$tmp" 2>/dev/null || echo 0) -lt $min_size ]]; then
        rm -f "$tmp"
        return 1
    fi

    if ! bash -n "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi

    if [[ "$ptype" == "ipqa" ]]; then
        if ! grep -qE "IP-Quality-Archive|IPQA" "$tmp" 2>/dev/null || ! grep -q "run_check" "$tmp" 2>/dev/null; then
            rm -f "$tmp"
            return 1
        fi
    elif [[ "$ptype" == "core" ]]; then
        if ! grep -qE "IPQuality|Check_DNS|IP\.Check\.Place|script_version" "$tmp" 2>/dev/null; then
            rm -f "$tmp"
            return 1
        fi
        sed -i 's/\r$//' "$tmp" 2>/dev/null || true
        # 对临时文件执行 patch
        patch_ip_script "$tmp" || { rm -f "$tmp"; return 1; }
        # patch 后必须重新通过 bash -n 验证
        if ! bash -n "$tmp" 2>/dev/null; then
            rm -f "$tmp"
            return 1
        fi
        # 必要的 feature sanity check
        if ! grep -qE "IPQuality|Check_DNS|IP\.Check\.Place|script_version" "$tmp" 2>/dev/null; then
            rm -f "$tmp"
            return 1
        fi
    fi

    sed -i 's/\r$//' "$tmp" 2>/dev/null || true
    chmod +x "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$dest"
    return 0
}

# 3. 安装主程序文件
echo -e "\n${C_BOLD}[3/5] 安装 IPQA 主程序...${C_RESET}"
if [[ -f "$SCRIPT_DIR/ipqa.sh" ]]; then
    cp "$SCRIPT_DIR/ipqa.sh" "$INSTALL_DIR/ipqa.sh"
    chmod 755 "$INSTALL_DIR/ipqa.sh"
else
    echo -e "${C_CYAN}从远程获取 ipqa.sh...${C_RESET}"
    if ! safe_download "https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/ipqa.sh" "$INSTALL_DIR/ipqa.sh" "ipqa"; then
        echo -e "${C_RED}错误: 无法获取有效的 ipqa.sh 脚本${C_RESET}"
        exit 1
    fi
fi
sed -i 's/\r$//' "$INSTALL_DIR/ipqa.sh" 2>/dev/null || true
chmod 755 "$INSTALL_DIR/ipqa.sh"

# 4. 下载/缓存 IPQuality 检测脚本核心
echo -e "\n${C_BOLD}[4/5] 初始化 IPQuality 检测引擎缓存...${C_RESET}"
local_core_src=""
if [[ -f "$SCRIPT_DIR/ip.sh" ]]; then
    local_core_src="$SCRIPT_DIR/ip.sh"
elif [[ -f "$SCRIPT_DIR/IP-Quality-Detection-Project/ip.sh" ]]; then
    local_core_src="$SCRIPT_DIR/IP-Quality-Detection-Project/ip.sh"
fi

core_installed=false
if [[ -n "$local_core_src" ]]; then
    tmp_local="$INSTALL_DIR/ip.sh.tmp.$$.$RANDOM"
    cp "$local_core_src" "$tmp_local"
    sed -i 's/\r$//' "$tmp_local" 2>/dev/null || true
    if bash -n "$tmp_local" 2>/dev/null && patch_ip_script "$tmp_local" && bash -n "$tmp_local" 2>/dev/null && grep -qE "IPQuality|Check_DNS|IP\.Check\.Place|script_version" "$tmp_local" 2>/dev/null; then
        chmod +x "$tmp_local" 2>/dev/null || true
        mv -f "$tmp_local" "$INSTALL_DIR/ip.sh"
        echo -e "${C_GREEN}✔ 已自本地同步并修补 IPQuality 引擎缓存${C_RESET}"
        core_installed=true
    else
        rm -f "$tmp_local"
        echo -e "${C_YELLOW}⚠ 本地 IPQuality 引擎语法或修补校验失败，尝试在线下载...${C_RESET}"
    fi
fi

if [[ "$core_installed" != "true" ]]; then
    echo -e "${C_CYAN}正在下载 IPQuality 上游脚本...${C_RESET}"
    if safe_download "https://IP.Check.Place" "$INSTALL_DIR/ip.sh" "core" || safe_download "https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh" "$INSTALL_DIR/ip.sh" "core"; then
        echo -e "${C_GREEN}✔ IPQuality 引擎下载与修补验证成功${C_RESET}"
        core_installed=true
    else
        if [[ -f "$INSTALL_DIR/ip.sh" && -s "$INSTALL_DIR/ip.sh" ]] && bash -n "$INSTALL_DIR/ip.sh" 2>/dev/null; then
            echo -e "${C_YELLOW}⚠ 引擎在线下载受阻，保留已有本地版本${C_RESET}"
            core_installed=true
        else
            echo -e "${C_YELLOW}⚠ 引擎在线下载受阻，运行首次检测时将自动重试${C_RESET}"
        fi
    fi
fi

# 自动计算服务器当前时区下对应“北京时间凌晨 04:00”的小时与分钟 (0-23, 0-59) (M-19)
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
    z=$(date +%z 2>/dev/null || echo "+0800")
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

# 初始化配置文件
if [[ ! -f "$INSTALL_DIR/config.sh" ]]; then
    cat <<EOF > "$INSTALL_DIR/config.sh"
# IPQA Configuration
CHECK_INTERVAL_HOURS=24
HAS_V6="auto"
V6_CHECK_COUNT=0
V6_PROBE_INTERVAL=10
SCORE_DIFF_THRESHOLD=10
EXPECTED_YOUTUBE_REGION=""
EXPECTED_NETFLIX_REGION=""
KEEP_MAX_ARCHIVES=0
AUTO_UPDATE_SCRIPT=${AUTO_UPDATE_SCRIPT:-true}
EOF
    chmod 600 "$INSTALL_DIR/config.sh" 2>/dev/null || true
fi

# 5. 配置全局命令软链接 (M-03: 安全检查，杜绝无条件覆写非 IPQA 文件或软链接)
echo -e "\n${C_BOLD}[5/5] 配置全局软链接 (ipqa)...${C_RESET}"
BIN_DIR="/usr/local/bin"
LINKED=false

if [[ -L "$BIN_DIR/ipqa" ]]; then
    cur_target=$(readlink "$BIN_DIR/ipqa" 2>/dev/null || true)
    if [[ "$cur_target" == "$INSTALL_DIR/ipqa.sh" || "$cur_target" == *ipqa* ]]; then
        ln -sf "$INSTALL_DIR/ipqa.sh" "$BIN_DIR/ipqa" 2>/dev/null || sudo ln -sf "$INSTALL_DIR/ipqa.sh" "$BIN_DIR/ipqa" 2>/dev/null && LINKED=true || true
    else
        echo -e "${C_YELLOW}提示: $BIN_DIR/ipqa 为其他程序的软链接 ($cur_target)，避免覆盖${C_RESET}"
    fi
elif [[ -e "$BIN_DIR/ipqa" ]]; then
    if grep -qE "IP-Quality-Archive|IPQA" "$BIN_DIR/ipqa" 2>/dev/null; then
        ln -sf "$INSTALL_DIR/ipqa.sh" "$BIN_DIR/ipqa" 2>/dev/null || sudo ln -sf "$INSTALL_DIR/ipqa.sh" "$BIN_DIR/ipqa" 2>/dev/null && LINKED=true || true
    else
        echo -e "${C_YELLOW}提示: $BIN_DIR/ipqa 已存在且非 IPQA 程序，避免覆盖${C_RESET}"
    fi
elif [[ -w "$BIN_DIR" ]]; then
    ln -sf "$INSTALL_DIR/ipqa.sh" "$BIN_DIR/ipqa" 2>/dev/null && LINKED=true || true
elif can_sudo; then
    sudo ln -sf "$INSTALL_DIR/ipqa.sh" "$BIN_DIR/ipqa" 2>/dev/null && LINKED=true || true
fi

if [[ "$LINKED" == "false" ]]; then
    USER_BIN="$HOME/.local/bin"
    mkdir -p "$USER_BIN"
    if [[ -L "$USER_BIN/ipqa" ]]; then
        cur_u_target=$(readlink "$USER_BIN/ipqa" 2>/dev/null || true)
        if [[ "$cur_u_target" == "$INSTALL_DIR/ipqa.sh" || "$cur_u_target" == *ipqa* ]]; then
            ln -sf "$INSTALL_DIR/ipqa.sh" "$USER_BIN/ipqa"
            LINKED=true
        else
            echo -e "${C_YELLOW}提示: $USER_BIN/ipqa 为其他程序软链接 ($cur_u_target)，保留原状${C_RESET}"
        fi
    elif [[ -e "$USER_BIN/ipqa" ]] && ! grep -qE "IP-Quality-Archive|IPQA" "$USER_BIN/ipqa" 2>/dev/null; then
        echo -e "${C_YELLOW}提示: $USER_BIN/ipqa 已存在且非 IPQA 程序，避免覆盖${C_RESET}"
    else
        ln -sf "$INSTALL_DIR/ipqa.sh" "$USER_BIN/ipqa"
        LINKED=true
        echo -e "${C_YELLOW}提示: 已创建软链接至 $USER_BIN/ipqa${C_RESET}"
        if [[ ":$PATH:" != *":$USER_BIN:"* ]]; then
            echo -e "${C_GRAY}请确保 $USER_BIN 在您的环境变量 PATH 中，或通过 $INSTALL_DIR/ipqa.sh 运行${C_RESET}"
        fi
    fi
else
    echo -e "${C_GREEN}✔ 全局指令已注册: $BIN_DIR/ipqa${C_RESET}"
fi

if [[ "$IS_UPDATE" == "true" ]]; then
    echo -e "\n${C_GREEN}${C_BOLD}🎉 IPQA 已成功更新至最新版本！${C_RESET}"
    echo -e "${C_GREEN}✔ 历史存档与用户配置已完整保留${C_RESET}"
else
    echo -e "\n${C_GREEN}${C_BOLD}🎉 IPQA 安装成功！${C_RESET}"

    # 定时任务配置询问 (交互式，仅初次安装)
    if [[ "$NON_INTERACTIVE" == "false" ]]; then
        local_h=$(get_beijing_4am_local_hour)
        echo -ne "\n${C_CYAN}是否开启每天定时自动检测与归档 (北京时间凌晨 04:00 / 本机约 $local_h:00)? (Y/n): ${C_RESET}"
        read -r setup_cron_ans
        setup_cron_ans="${setup_cron_ans:-y}"
        if [[ "$setup_cron_ans" =~ ^[yY] ]]; then
            # N-04: 优先且严格使用确认属于当前安装的 IPQA 脚本绝对路径
            CRON_BIN="$INSTALL_DIR/ipqa.sh"
            if [[ -x "$BIN_DIR/ipqa" && "$LINKED" == "true" ]] && [[ "$BIN_DIR/ipqa" -ef "$INSTALL_DIR/ipqa.sh" ]]; then
                CRON_BIN="$BIN_DIR/ipqa"
            elif [[ -x "$HOME/.local/bin/ipqa" ]] && [[ "$HOME/.local/bin/ipqa" -ef "$INSTALL_DIR/ipqa.sh" ]]; then
                CRON_BIN="$HOME/.local/bin/ipqa"
            fi

            # N-01: 健壮去重已有的 IPQA 定时任务 (匹配带引号及不带引号形式)
            existing=$(crontab -l 2>/dev/null | grep -vE 'ipqa(\.sh)?["'\''[:space:]]+--cron' | grep -v "# IPQA AUTO CHECK" || true)

            # M-19, M-20: 结合半小时/45分钟时区的分钟换算与北京时间校验，路径进行 shell 安全转义
            local_min=$(get_beijing_00_local_minute)
            cron_entry="$local_min * * * * [ \"\$(TZ='Asia/Shanghai' date +\\%H:\\%M)\" = \"04:00\" ] && \"$CRON_BIN\" --cron >> \"$INSTALL_DIR/logs/ipqa.log\" 2>&1"
            if {
                [[ -n "$existing" ]] && echo "$existing"
                echo "# IPQA AUTO CHECK - DO NOT EDIT MANUALLY"
                echo "$cron_entry"
            } | crontab -; then
                echo -e "${C_GREEN}✔ 已为您激活每天定时检测 (北京时间 04:00, 自动适配夏令时/时区)${C_RESET}"
            else
                echo -e "${C_YELLOW}⚠ 定时任务自动写入失败，请检查 crontab 权限${C_RESET}"
            fi
        fi

        echo -ne "\n${C_CYAN}是否立即执行首次 IP 质量检测并建立初始存档? (Y/n): ${C_RESET}"
        read -r first_run_ans
        first_run_ans="${first_run_ans:-y}"
        if [[ "$first_run_ans" =~ ^[yY] ]]; then
            echo -e "\n${C_CYAN}正在启动首次检测...${C_RESET}\n"
            # N-07: 首次检测若因临时网络受阻退出码非 0，不应打断整体安装流程导致安装器在 set -e 下报错退出
            bash "$INSTALL_DIR/ipqa.sh" --check || echo -e "${C_YELLOW}⚠ 首次检测未能完全生成存档，可在网络正常后通过 'ipqa' 或 'ipqa --check' 执行${C_RESET}"
        fi
    fi
fi

echo -e "\n${C_BOLD}使用小贴士:${C_RESET}"
echo -e "  • 启动终端图形界面:  ${C_CYAN}ipqa${C_RESET}"
echo -e "  • 立即执行一次检测:  ${C_CYAN}ipqa --check${C_RESET}"
echo -e "  • 查看当前运行状态:  ${C_CYAN}ipqa --status${C_RESET}"
echo -e "  • 在线升级主程序:    ${C_CYAN}ipqa --update${C_RESET}"
echo -e "  • 帮助信息:          ${C_CYAN}ipqa --help${C_RESET}\n"
