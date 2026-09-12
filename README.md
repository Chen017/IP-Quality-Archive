# 🔍 IP 质量存档监测系统 (IP Quality Archive - IPQA)

[![Bash](https://img.shields.io/badge/Language-Bash%204.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)
[![IPQuality](https://img.shields.io/badge/Detection%20Engine-IPQuality-orange.svg)](https://github.com/xykt/IPQuality)

**IP 质量存档监测系统 (IPQA)** 是一个轻量、高效、基于 Bash 的 IP 质量历史归档与终端可视化监测工具。它以后台守护或定时任务的形式自动调用 [IPQuality](https://github.com/xykt/IPQuality) 检测引擎，对服务器的 IPv4 与 IPv6 网络质量、风险评分、流媒体解锁状态及邮局连通性进行定期采集与版本化存档，并通过丰富的终端图表（TUI）呈现历史趋势与波动，第一时间捕获 IP 属性漂移与风控降级。

---

## ✨ 核心特性

- ⚡ **双栈一体化直出**：无需繁琐选择 v4 还是 v6，所有分析模块与历史存档一键同时输出 IPv4 与 IPv6（若有）的全部检测与图表，省时省力。
- 📊 **五大数据分析模块**：
  1. **IP 类型属性变动**：追踪原生/广播属性及权威数据库（IPinfo, ipregistry, AbuseIPDB, IP2LOCATION）的使用类型变迁（家宽/商业/机房）。
  2. **综合风险评分图**：水平彩色柱状图直观展示各大风控引擎（SCAMALYTICS, IP2LOCATION, IPQS, AbuseIPDB 等）评分走势与等级划分。
  3. **风险因子综合矩阵**：Proxy / Tor / VPN / Server / Abuser / Robot 检出热力图与历史深钻。
  4. **流媒体与 AI 解锁**：TikTok, Disney+, Netflix, YouTube, Amazon PV, Reddit, ChatGPT 解锁历史点阵、地区漂移追踪与解锁稳定性分析。
  5. **邮件与黑名单监测**：深度合并 25 端口出站能力、国内外 12 家主流邮箱服务器连通性矩阵及 DNSBL 全局 400+ 数据库拦截深度趋势。
- 📋 **图形化存档快照**：告别枯燥难读的纯 JSON！查看历史存档时直接输出结构化、图形化卡片，展示 IP 详情、风险评分条、因子徽标及解锁状态，并提供按键查看原始 JSON 功能。
- 🔄 **每日自动同步核心**：免去繁琐的手动维护，系统每天自动检测并静默拉取上游最新检测引擎核心，保证风控检测规则时刻最新。
- 🚨 **智能告警引擎**：实时捕捉流媒体送中/地区漂移、解锁降级、风险评分突增（默认 ≥ 10 分）、IP 类型变更及黑名单收录，并记录告警日志。
- 🧹 **一键干净卸载**：支持交互菜单 `[x]` 或命令 `ipqa --uninstall` / `bash install.sh --uninstall`，干净清理 crontab 任务、系统软链接与数据，不留系统垃圾。

---

## 🖥️ 终端控制台预览

```text
```text
══════════════════════════════════════════════════════════════════════
   🔍 IP 质量存档监测系统 (IPQA)  v1.0.0
══════════════════════════════════════════════════════════════════════

  📡 节点网络: 38.244.12.34 (IPv4)  │  2602:f656:1::2 (IPv6)
  🏢 归属信息: AS1054  │  📍 Los Angeles, United States of America
  ⏰ 上次检测: 2026-09-12 08:30:00
  📦 历史存档: IPv4: 48 份  │  IPv6: 48 份  (08-01 ~ 09-12)
  🔄 定时检测: 每 6 小时 (每天自动同步核心)

── ⚠️  最近风险变化提醒 ───────────────────────────────────────────────
  • [09-11] YouTube 地区从 [US] 变为 [CN]
  • [09-10] Netflix 解锁状态发生降级: [解锁] 变为 [仅自制]
  • [09-08] AbuseIPDB 风险评分大幅上升 +15 (0 -> 15)

── 📋 功能菜单导航 ───────────────────────────────────────────────────
  [1] 📊 IP 类型属性变动       [6] 📋 历史存档图表快照
  [2] 📈 综合风险评分图        [7] ⚙️  配置定时任务
  [3] 🔬 风险因子综合矩阵      [8] 🔄 立即执行检测
  [4] 🎬 流媒体与AI解锁        [9] 🗑️  清理历史数据
  [5] 📬 邮件与黑名单监测      [0] 🚪 退出系统  [x] 🧹 卸载系统
──────────────────────────────────────────────────────────────────────
```

---

## 🚀 快速安装与更新

### 方式一：一键自动安装 (推荐)

在终端中执行以下命令（适用于 Debian / Ubuntu / CentOS / RHEL / Alpine / Arch / Fedora 等）：

```bash
bash <(curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/install.sh)
```

或如果已克隆本仓库：

```bash
bash install.sh
```

### 方式二：一键无损在线更新 (已安装用户)

如果系统已安装过 IPQA，随时可通过以下任一命令进行一键平滑升级，系统将**自动无损保留历史存档、配置文件及现有的定时检测任务**：

```bash
ipqa --update
# 或再次执行在线安装脚本，脚本将自动识别并转入平滑更新流程：
bash <(curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/install.sh)
```

### 方式三：非交互式无人值守安装

```bash
bash install.sh -y
```

### 方式四：一键干净卸载

如果需要卸载 IPQA，只需执行：

```bash
ipqa --uninstall
# 或通过安装脚本一键卸载：
bash install.sh --uninstall
```

安装完成后，可直接在终端中输入 `ipqa` 调出控制台。

---

## 📖 使用指南

### 1. 启动交互式终端界面

```bash
ipqa
```

在菜单中直接输入数字 `1-9`、`x` 或 `0` 即可快速查看对应图表与执行操作。

### 2. 命令行快捷操作

| 命令 | 描述 |
| --- | --- |
| `ipqa` | 启动交互式 TUI 监控面板 |
| `ipqa --check` | 立即手动触发一次完整体检并存入历史记录（超 24h 自动同步核心） |
| `ipqa --cron` | 静默后台执行体检（写入 log，供 crontab 专用，自动同步最新核心） |
| `ipqa --status` | 查看当前存档总数与最新检测 IP 简报 |
| `ipqa --update` | 一键从 GitHub 在线升级 IPQA 主程序并保留全部数据 |
| `ipqa --uninstall` | 干净卸载 IPQA 并清理 crontab 任务与软链接 |
| `ipqa --help` | 显示命令行帮助参数 |

---

## 📊 图表与快照特性解析

### 1. 📋 历史存档图表化快照
在主菜单选择 `[6]` 后，系统双栈合并展示最近的检测历史记录，选中任一历史记录即可一次性呈现 IPv4 与 IPv6（若有）的图形化快照卡片：
```text
┌── [IPv4 检测快照卡片] ──────────────────────────────────────────┐
  📡 节点 IP  : 38.244.12.34 (IPv4)
  🏢 组织/ASN : AS1054 (US-Hosting)
  📍 地理位置 : Los Angeles, 美国
  🏷️ 属性类型 : 原生IP │ IPinfo: ISP │ IP2Location: ISP
  ── 📊 权威风控评分 ─────────────────────────────────────────────────
    • SCAMALYTICS   ▏ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 低风险
    • IP2LOCATION   ▏ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 低风险
    • AbuseIPDB     ▏ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 低风险
  ── 🔬 核心安全因子 ─────────────────────────────────────────────────
    Proxy: ● 正常   Tor: ● 正常   VPN: ● 正常   Server: ● 正常   Abuser: ● 正常
  ── 🎬 流媒体与 AI 解锁 ─────────────────────────────────────────────
    • YouTube   : ✓ 解锁 [US]
    • Netflix   : ✓ 解锁 [US]
    • Disney+   : ✓ 解锁
    • ChatGPT   : ✓ 解锁
  ── 📬 邮件连通与 DNS 黑名单 ─────────────────────────────────────────
    • 25 端口出站 (Port 25): ✓ 开放
    • DNS 黑名单拦截       : 0 / 400 数据库 (全部干净通过)
└──────────────────────────────────────────────────────────────────────┘
```
若该次检测包含 IPv6，紧随其后自动绘制对应的 IPv6 快照卡片。同时提供按键 `[j]` 随时调用 `jq` 交互查看原始底层 JSON。

### 2. 📊 IP 类型属性变动
按时间列对齐，对比 IPinfo、ipregistry、AbuseIPDB、IP2LOCATION 等数据库中的使用类型（家宽 / 商业 / 机房），快速定位何时被机房标记或判定广播 IP。IPv4 与 IPv6 自动分段展示。

### 3. 📈 综合风险评分趋势图
对 SCAMALYTICS、IP2LOCATION、IPQS、AbuseIPDB 进行 0-100 水平柱状图可视化，按绿、黄、红、紫四色阶标记风险等级。

### 4. 🔬 风险因子综合矩阵与全量历史追踪
自动展示 9 大风控引擎针对 Proxy、Tor、VPN、Server、Abuser、Robot 的点阵检出，并直接一次性展开各因子在时间线上的历史变化与综合表现评级，无需手动选择单项因子，IPv4 与 IPv6 均完整呈现：
```text
▶ IPv4 各风险因子历史检出趋势 (时间线):
  风险因子 │  09-07  │  09-08  │  09-09  │  09-10  │  09-11  │  09-12  │ 历史综合表现
  ─────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────────
  Proxy    │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✅ 保持安全
  Tor      │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✅ 保持安全
  VPN      │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✅ 保持安全
  Server   │  ✔ 安全 │ ⚠️ 1/9  │ ⚠️ 1/9  │ ⚠️ 1/9  │ ⚠️ 1/9  │ ⚠️ 1/9  │  ⚠️ 曾有检出
  Abuser   │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✅ 保持安全
  Robot    │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✔ 安全 │  ✅ 保持安全
```

### 5. 🎬 流媒体与 AI 解锁历史
清晰显示主流流媒体的原生解锁（绿点）、DNS 解锁（橙点）、自制剧（黄点）与封锁（红点），并自动追踪地区漂移（如 Netflix/YouTube 地区变动）。

### 6. 📬 邮件与黑名单深度监测
合并展示 IDC 是否开放出站 25 端口、连接 12 家主流邮箱服务器状态矩阵，以及全局 400+ DNSBL 数据库的拦截数量与波动趋势。

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
