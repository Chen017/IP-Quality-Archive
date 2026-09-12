#!/usr/bin/env bash
# ==============================================================================
# IP Quality Archive (IPQA) - 一键安装脚本
# Version: 1.0.0
# Description: 自动化安装 IPQA 监测系统及必要依赖 (jq, curl, cron)
# GitHub: https://github.com/xykt/IPQuality
# ==============================================================================

set -e

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_GRAY="\033[90m"

ACTION="install"
NON_INTERACTIVE=false
INSTALL_DIR="${IPQA_DIR:-$HOME/.ipqa}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
        remaining=$(crontab -l 2>/dev/null | grep -vE "ipqa(\.sh)? --cron" | grep -v "# IPQA AUTO CHECK" || true)
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
        if [[ -L "$link" || -f "$link" ]]; then
            rm -f "$link" 2>/dev/null || sudo rm -f "$link" 2>/dev/null || true
            echo -e "${C_GREEN}✔ 已删除 $link${C_RESET}"
        fi
    done

    echo -e "\n${C_CYAN}▶ [3/3] 数据与配置目录清理${C_RESET}"
    local rm_data="n"
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        rm_data="y"
    else
        echo -ne "${C_YELLOW}是否删除所有历史检测存档与配置 ($INSTALL_DIR)? [y/N]: ${C_RESET}"
        read -r rm_data
    fi

    if [[ "$rm_data" == "y" || "$rm_data" == "Y" ]]; then
        rm -rf "$INSTALL_DIR"
        echo -e "${C_GREEN}✔ 已彻底删除 $INSTALL_DIR${C_RESET}"
    else
        echo -e "${C_GRAY}ℹ️ 已保留历史存档与配置目录: $INSTALL_DIR${C_RESET}"
    fi

    echo -e "\n${C_GREEN}${C_BOLD}✔ IPQA 已完全卸载！感谢使用。${C_RESET}\n"
    exit 0
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            NON_INTERACTIVE=true
            shift
            ;;
        -d|--dir)
            INSTALL_DIR="$2"
            shift 2
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
            echo "  -y, --yes          非交互式操作，全部采用默认确认"
            echo "  -d, --dir <路径>   指定安装/数据目录 (默认: ~/.ipqa)"
            echo "  --uninstall        干净卸载 IPQA，清理定时任务、命令软链接与数据"
            echo "  -h, --help         显示本帮助信息"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

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

# 检查 bash 版本
BASH_VER=$(bash --version | head -n 1 | grep -oE '[0-9]+\.[0-9]+' | head -n 1 | cut -d '.' -f 1)
if (( BASH_VER < 4 )); then
    echo -e "${C_RED}错误: Bash 版本必须 >= 4.0 (当前版本: $BASH_VER)${C_RESET}"
    exit 1
fi

can_sudo() {
    has_cmd sudo && sudo -n true >/dev/null 2>&1
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
        run_as_root apt-get update -qq && run_as_root apt-get install -y -qq "${pkgs[@]}" || true
    elif has_cmd dnf; then
        run_as_root dnf install -y -q "${pkgs[@]}" || true
    elif has_cmd yum; then
        run_as_root yum install -y -q "${pkgs[@]}" || true
    elif has_cmd pacman; then
        run_as_root pacman -Sy --noconfirm "${pkgs[@]}" || true
    elif has_cmd apk; then
        run_as_root apk add --no-cache "${pkgs[@]}" || true
    elif has_cmd zypper; then
        run_as_root zypper install -y "${pkgs[@]}" || true
    else
        echo -e "${C_RED}未能识别系统包管理器，请手动安装: ${pkgs[*]}${C_RESET}"
        return 1
    fi
}

needed_pkgs=()
has_cmd jq || needed_pkgs+=("jq")
has_cmd curl || needed_pkgs+=("curl")
has_cmd crontab || needed_pkgs+=("cron")

if [[ ${#needed_pkgs[@]} -gt 0 ]]; then
    pkg_install "${needed_pkgs[@]}" || true
fi

# 重新核验依赖
if ! has_cmd jq; then
    echo -e "${C_RED}错误: jq 未安装成功，请手动执行 apt/yum install -y jq${C_RESET}"
    exit 1
fi
if ! has_cmd curl; then
    echo -e "${C_RED}错误: curl 未安装成功，请手动执行 apt/yum install -y curl${C_RESET}"
    exit 1
fi
echo -e "${C_GREEN}✔ 依赖检查通过 (jq, curl, bash $BASH_VER)${C_RESET}"

# 2. 创建目录结构
echo -e "\n${C_BOLD}[2/5] 创建系统运行目录: ${C_CYAN}$INSTALL_DIR${C_RESET}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/data/v4"
mkdir -p "$INSTALL_DIR/data/v6"
mkdir -p "$INSTALL_DIR/logs"
echo -e "${C_GREEN}✔ 运行目录创建完成${C_RESET}"

# 3. 安装主程序文件
echo -e "\n${C_BOLD}[3/5] 安装 IPQA 主程序...${C_RESET}"
if [[ -f "$SCRIPT_DIR/ipqa.sh" ]]; then
    cp "$SCRIPT_DIR/ipqa.sh" "$INSTALL_DIR/ipqa.sh"
else
    echo -e "${C_CYAN}从远程获取 ipqa.sh...${C_RESET}"
    curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/ipqa.sh -o "$INSTALL_DIR/ipqa.sh" || {
        echo -e "${C_RED}错误: 无法获取 ipqa.sh${C_RESET}"
        exit 1
    }
fi
chmod +x "$INSTALL_DIR/ipqa.sh"

# 4. 下载/缓存 IPQuality 检测脚本核心
echo -e "\n${C_BOLD}[4/5] 初始化 IPQuality 检测引擎缓存...${C_RESET}"
if [[ -f "$SCRIPT_DIR/ip.sh" ]]; then
    cp "$SCRIPT_DIR/ip.sh" "$INSTALL_DIR/ip.sh"
    chmod +x "$INSTALL_DIR/ip.sh"
    echo -e "${C_GREEN}✔ 已自本地同步 IPQuality 引擎缓存${C_RESET}"
elif [[ -f "$SCRIPT_DIR/IP-Quality-Detection-Project/ip.sh" ]]; then
    cp "$SCRIPT_DIR/IP-Quality-Detection-Project/ip.sh" "$INSTALL_DIR/ip.sh"
    chmod +x "$INSTALL_DIR/ip.sh"
    echo -e "${C_GREEN}✔ 已自本地同步 IPQuality 引擎缓存${C_RESET}"
else
    echo -e "${C_CYAN}正在下载 IPQuality 上游脚本...${C_RESET}"
    if curl -sL https://IP.Check.Place -o "$INSTALL_DIR/ip.sh" || curl -sL https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh -o "$INSTALL_DIR/ip.sh"; then
        chmod +x "$INSTALL_DIR/ip.sh"
        echo -e "${C_GREEN}✔ IPQuality 引擎下载成功${C_RESET}"
    else
        echo -e "${C_YELLOW}⚠ 引擎在线下载受阻，运行首次检测时将自动重试${C_RESET}"
    fi
fi
sed -i 's/\r$//' "$INSTALL_DIR/ip.sh" 2>/dev/null || true
sed -i 's/\r$//' "$INSTALL_DIR/ipqa.sh" 2>/dev/null || true
chmod +x "$INSTALL_DIR/ip.sh" "$INSTALL_DIR/ipqa.sh"
if [[ -f "$INSTALL_DIR/ip.sh" ]] && ! grep -q 'Company: { IP2LOCATION' "$INSTALL_DIR/ip.sh" 2>/dev/null; then
    sed -i '/Company: { ipapi:/a \type_updates+=".Type |= . * { Company: { IP2LOCATION: \\"$(clean_ansi "${ip2location[scomtype]:-null}")\\" } } | "' "$INSTALL_DIR/ip.sh" 2>/dev/null || true
fi

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
EOF
fi

# 5. 配置全局命令软链接
echo -e "\n${C_BOLD}[5/5] 配置全局软链接 (ipqa)...${C_RESET}"
BIN_DIR="/usr/local/bin"
LINKED=false

if [[ -w "$BIN_DIR" ]]; then
    ln -sf "$INSTALL_DIR/ipqa.sh" "$BIN_DIR/ipqa"
    LINKED=true
elif can_sudo; then
    sudo ln -sf "$INSTALL_DIR/ipqa.sh" "$BIN_DIR/ipqa" 2>/dev/null && LINKED=true || true
fi

if [[ "$LINKED" == "false" ]]; then
    USER_BIN="$HOME/.local/bin"
    mkdir -p "$USER_BIN"
    ln -sf "$INSTALL_DIR/ipqa.sh" "$USER_BIN/ipqa"
    echo -e "${C_YELLOW}提示: 已创建软链接至 $USER_BIN/ipqa${C_RESET}"
    if [[ ":$PATH:" != *":$USER_BIN:"* ]]; then
        echo -e "${C_GRAY}请确保 $USER_BIN 在您的环境变量 PATH 中，或通过 $INSTALL_DIR/ipqa.sh 运行${C_RESET}"
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
        echo -ne "\n${C_CYAN}是否开启每天定时自动检测与归档 (北京时间凌晨 04:00 / 本机 $local_h:00)? (Y/n): ${C_RESET}"
        read -r setup_cron_ans
        setup_cron_ans="${setup_cron_ans:-y}"
        if [[ "$setup_cron_ans" =~ ^[yY] ]]; then
            CRON_BIN="$(command -v ipqa 2>/dev/null || echo "$INSTALL_DIR/ipqa.sh")"
            existing=$(crontab -l 2>/dev/null | grep -vE "ipqa(\.sh)? --cron" | grep -v "# IPQA AUTO CHECK" || true)
            {
                [[ -n "$existing" ]] && echo "$existing"
                echo "# IPQA AUTO CHECK - DO NOT EDIT MANUALLY"
                echo "0 $local_h * * * $CRON_BIN --cron >> $INSTALL_DIR/logs/ipqa.log 2>&1"
            } | crontab -
            echo -e "${C_GREEN}✔ 已为您激活每天定时检测 (北京时间 04:00, 本机 Cron: 0 $local_h * * *)${C_RESET}"
        fi

        echo -ne "\n${C_CYAN}是否立即执行首次 IP 质量检测并建立初始存档? (Y/n): ${C_RESET}"
        read -r first_run_ans
        first_run_ans="${first_run_ans:-y}"
        if [[ "$first_run_ans" =~ ^[yY] ]]; then
            echo -e "\n${C_CYAN}正在启动首次检测...${C_RESET}\n"
            bash "$INSTALL_DIR/ipqa.sh" --check
        fi
    fi
fi

echo -e "\n${C_BOLD}使用小贴士:${C_RESET}"
echo -e "  • 启动终端图形界面:  ${C_CYAN}ipqa${C_RESET}"
echo -e "  • 立即执行一次检测:  ${C_CYAN}ipqa --check${C_RESET}"
echo -e "  • 查看当前运行状态:  ${C_CYAN}ipqa --status${C_RESET}"
echo -e "  • 在线升级主程序:    ${C_CYAN}ipqa --update${C_RESET}"
echo -e "  • 帮助信息:          ${C_CYAN}ipqa --help${C_RESET}\n"
