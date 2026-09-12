# 🔍 IP 质量存档监测系统 (IP Quality Archive - IPQA)

[![Bash](https://img.shields.io/badge/Language-Bash%204.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)
[![IPQuality](https://img.shields.io/badge/Detection%20Engine-IPQuality-orange.svg)](https://github.com/xykt/IPQuality)

**IP 质量存档监测系统 (IPQA)** 是一个轻量、高效、基于 Bash 的 IP 质量历史归档与终端可视化监测工具。它以后台守护或定时任务的形式自动调用 [IPQuality](https://github.com/xykt/IPQuality) 检测引擎，对服务器的 IPv4 与 IPv6 网络质量、风险评分、流媒体解锁状态及邮局连通性进行定期采集与版本化存档，并通过丰富的终端图表（TUI）呈现历史趋势与波动，第一时间捕获 IP 属性漂移与风控降级。

---

## ✨ 核心特性

- 📦 **纯净 JSON 存档**：利用 `-o` 参数直接生成结构化 JSON 存档，双栈隔离分别采集 `-4` 与 `-6`，避免交互输出污染。
- 📊 **六大终端可视化模块**：
  1. **IP 类型属性变化**：追踪原生/广播 IP 及各权威数据库（IPinfo, ipregistry, AbuseIPDB, IP2LOCATION）的使用类型变化（家宽/商业/机房）。
  2. **风险评分趋势图**：水平彩色柱状图直观展示 6 大风控引擎（SCAMALYTICS, IP2LOCATION, IPQS, AbuseIPDB 等）评分走势。
  3. **风险因子综合矩阵**：Proxy / Tor / VPN / Server / Abuser / Robot 9 大引擎检出 Boolean 热力图与因子历史追踪。
  4. **流媒体与 AI 解锁历史**：TikTok, Disney+, Netflix, YouTube, Amazon PV, Reddit, ChatGPT 解锁历史点阵、地区漂移追踪与解锁成功率。
  5. **邮局连通性状态**：实时与历史监测 25 端口出站可用性及国内外 12 家主流邮箱服务器连接状态。
  6. **DNS 黑名单趋势**：跟踪全局 400+ DNSBL 数据库中 Marked 与 Blacklisted 拦截数量变化。
- 🚨 **智能告警引擎**：检测流媒体送中/地区变更、解锁降级、风险评分突增（默认 ≥ 10 分）、IP 类型突变或黑名单新增，并自动记录。
- ⚙️ **开箱即用 定时任务**：内置交互式 Cron 配置，支持 1h / 3h / 6h / 12h / 每天 或 自定义周期自动检测。
- 🧹 **无痛数据维护**：支持按 30/90/180 天或保留最新 N 份存档一键清理，轻量省心。

---

## 🖥️ 终端控制台预览

```text
╔══════════════════════════════════════════════════════════════════╗
║         🔍 IP 质量存档监测系统 (IPQA)  v1.0.0                    ║
╠══════════════════════════════════════════════════════════════════╣
║  📡 IP: 38.244.12.34           │ v6: 2602:f656:1::2             ║
║  🏢 ASN: AS1054 Zont LLC       │ 📍 归属: Los Angeles, United St ║
╠══════════════════════════════════════════════════════════════════╣
║  ⏰ 上次检测: 2026-09-12 08:30:00                                ║
║  📦 存档数量: v4: 48   份      │  v6: 48   份                   ║
║  📅 时间跨度: 08-01 ~ 09-12                                      ║
║  🔄 定时检测: 已启用 (Cron: 每 6 小时)                           ║
╠══════════════════════════════════════════════════════════════════╣
║  ⚠️  最近风险变化提醒:                                           ║
║  • [09-11] YouTube 地区从 [US] 变为 [CN]                        ║
║  • [09-10] Netflix 解锁状态发生降级: [解锁] 变为 [仅自制]       ║
║  • [09-08] AbuseIPDB 风险评分大幅上升 +15 (0 -> 15)             ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  [1] 📊 IP 类型属性变化          [6] 🚫 黑名单历史趋势           ║
║  [2] 📈 风险评分趋势图          [7] ⚙️  配置定时任务             ║
║  [3] 🔬 风险因子综合矩阵        [8] 🔄 立即执行检测             ║
║  [4] 🎬 流媒体与AI解锁          [9] 📋 查看原始存档             ║
║  [5] 📬 邮局连通性状态          [u] 🔃 更新检测核心             ║
║                                  [c] 🗑️  清理历史数据             ║
║                                  [0] 🚪 退出程序                 ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## 🚀 快速安装

### 方式一：一键自动安装 (推荐)

在终端中执行以下命令（适用于 Debian / Ubuntu / CentOS / RHEL / Alpine / Arch / Fedora 等）：

```bash
bash <(curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/install.sh)
```

或如果已克隆本仓库：

```bash
bash install.sh
```

### 方式二：非交互式无人值守安装

```bash
bash install.sh -y
```

安装完成后，可直接在终端中输入 `ipqa` 调出控制台。

---

## 📖 使用指南

### 1. 启动交互式终端界面

```bash
ipqa
```

在菜单中直接输入数字 `1-9`、`u`、`c` 或 `0` 即可快速查看对应图表与执行操作。

### 2. 命令行快捷操作

| 命令 | 描述 |
| --- | --- |
| `ipqa` | 启动交互式 TUI 监控面板 |
| `ipqa --check` | 立即手动触发一次完整体检并存入历史记录 |
| `ipqa --cron` | 静默后台执行体检（写入 log，不阻塞终端，供 crontab 专用） |
| `ipqa --status` | 查看当前存档总数与最新检测 IP 简报 |
| `ipqa --help` | 显示命令行帮助参数 |

---

## 📊 图表模块解析

### 1. 📊 IP 类型属性变化
按时间列对齐，对比 IPinfo、ipregistry、AbuseIPDB、IP2LOCATION 等数据库中的使用类型（家宽 / 商业 / 机房），快速定位何时被机房标记或判定广播 IP：
```text
数据库      │ 09-06    │ 09-08    │ 09-10    │ 09-12    │ 历史稳定性
────────────┼──────────┼──────────┼──────────┼──────────┼──────────
IPinfo      │ ISP      │ ISP      │ ISP      │ ISP      │ ✅ 保持稳定
ipregistry  │ ISP      │ ISP      │ Hosting  │ ISP      │ ⚠️ 存在变动
AbuseIPDB   │ ISP      │ ISP      │ ISP      │ ISP      │ ✅ 保持稳定
原生/广播   │ 原生IP   │ 原生IP   │ 原生IP   │ 原生IP   │ ✅ 保持稳定
```

### 2. 📈 风险评分趋势
对 SCAMALYTICS、IP2LOCATION、IPQS、AbuseIPDB 进行 0-100 水平柱状图可视化，按绿、黄、红、紫四色阶标记风险等级：
```text
▶ 数据库: SCAMALYTICS (满分 100)
  09-06 12:00  ▏ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 低风险
  09-08 12:00  ▏ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 低风险
  09-10 12:00  ▏ ████████░░░░░░░░░░░░░░░░░░░░░░  12 低风险
  09-12 12:00  ▏ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 低风险
```

### 3. 🔬 风险因子综合矩阵
9 个引擎针对 Proxy、Tor、VPN、Server、Abuser、Robot 的检出点阵，并可进一步下钻查看某个因子在全部检测时间线中的检出率。

### 4. 🎬 流媒体与 AI 解锁历史
清晰显示主流流媒体的原生解锁（绿点）、DNS 解锁（橙点）、自制剧（黄点）与封锁（红点），并自动追踪地区漂移（如 Netflix/YouTube 地区从 US 漂移到其他地区）。

### 5. 📬 邮局连通性
检测服务器 IDC 是否开放出站 25 端口，以及连接 Gmail、Outlook、QQ、163 等 12 家主流邮箱服务器的状态矩阵。

### 6. 🚫 黑名单趋势
直观展示全局黑名单数据库中，该 IP 被判定拦截的数量变化。

---

## ⚙️ 目录结构与配置

系统安装于 `~/.ipqa/` 目录下：

```text
~/.ipqa/
├── ipqa.sh               # 主程序
├── ip.sh                 # 本地缓存的 IPQuality 检测引擎
├── config.sh             # 用户配置文件
├── data/
│   ├── v4/               # IPv4 历史 JSON 存档 (YYYY-MM-DD_HHMMSS.json)
│   ├── v6/               # IPv6 历史 JSON 存档
│   └── alerts.log        # 异常告警日志 (YYYY-MM-DD HH:MM:SS|LEVEL|MSG|PROTO)
└── logs/
    └── ipqa.log          # 运行与 Cron 执行日志
```

### 配置文件 `config.sh`

```bash
# 检测间隔小时数
CHECK_INTERVAL_HOURS=6

# 是否检测 IPv6 (auto / true / false)
HAS_V6="auto"

# 风险评分突变告警阈值 (默认上升超过 10 分告警)
SCORE_DIFF_THRESHOLD=10

# 期望的流媒体地区 (非期望地区时告警，留空则仅记录变化)
EXPECTED_YOUTUBE_REGION="US"
EXPECTED_NETFLIX_REGION="US"

# 最大保留存档数 (0 为永久保存)
KEEP_MAX_ARCHIVES=0
```

---

## 🛠️ 依赖说明

- `bash 4.0+`
- `jq` (自动通过系统包管理器安装)
- `curl`
- `cron` / `crontab`

---

## 📄 开源许可

本项目遵循 [GNU General Public License v3.0](LICENSE)。
检测引擎逻辑基于 [IPQuality (xykt/IPQuality)](https://github.com/xykt/IPQuality)。
