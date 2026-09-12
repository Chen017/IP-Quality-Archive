# 🔍 IP 质量存档监测系统 (IP Quality Archive - IPQA)

[![Bash](https://img.shields.io/badge/Language-Bash%204.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20WSL-lightgrey.svg)](https://www.kernel.org/)
[![Detection Engine](https://img.shields.io/badge/Detection%20Engine-IPQuality-orange.svg)](https://github.com/xykt/IPQuality)

**IP 质量存档监测系统 (IPQA)** 是一套轻量、高效、无侵入、开箱即用的 Linux 终端 IP 质量历史归档与全方位可视化监测系统。

基于 Bash 4.0+ 与 `jq` 构建，系统封装并深度增强了业界知名的 [IPQuality](https://github.com/xykt/IPQuality) 检测引擎。通过后台定时任务自动对服务器的 **IPv4 与 IPv6** 双栈网络质量、权威风控评分、5 大数据库 IP 类型属性、流媒体/AI 解锁状态及邮件黑名单进行周期化体检与 JSON 结构化版本存档。借助沉浸式终端界面（TUI），直观呈现历史趋势矩阵，并在第一时间捕捉 IP 属性漂移、解锁降级与风控异常。

---

## ✨ 核心特性

- ⚡ **双栈一体化直出**：告别繁琐的手动切换！所有分析模块、历史对比与存档卡片默认同时输出 **IPv4 与 IPv6**（若节点支持），一览无余。
- 🏷️ **全维度 5 大数据库 IP 类型矩阵**：
  - 深度整合 **IPinfo、ipregistry、ipapi、IP2Location、AbuseIPDB** 5 大权威数据库。
  - 同步追踪「**使用类型 (Usage)**」与「**公司类型 (Company)**」双重维度属性（如 ISP、Hosting、Business、Residential 等）。
  - 基于权威多库地理位置一致性，精准诊断「**原生 IP (Geo-consistent)**」与「**广播/机房 IP (Geo-discrepant)**」。
- 📈 **权威风控评分水平趋势图**：
  - 支持 **SCAMALYTICS、IP2LOCATION、AbuseIPDB、IPQS、ipapi、DBIP** 6 大主流风控平台。
  - 0-100 阶梯色彩水平进度条，分级提示低风险、中风险、高风险与极高风险。
- 🔬 **9 大引擎 6 维风险因子热力矩阵**：
  - 全面检出 **Proxy / Tor / VPN / Server / Abuser / Robot** 6 大核心风险标记。
  - 汇总 9 家风控引擎历史检出点阵，并以时间线形式展示长期安全性综合评级。
- 🎬 **流媒体与 AI 解锁历史 & 地区漂移监控**：
  - 覆盖 **YouTube、Netflix、Disney+、TikTok、ChatGPT、Reddit、Amazon Prime Video**。
  - 三态高亮标注：🟢 **原生解锁**、🟡 **DNS 分流解锁 / 仅自制剧 / 机房解锁 / 仅网页**、🔴 **屏蔽/失败/受限**。
  - 独家上游补丁修复：解决原版脚本在部分无 dig 环境或超时情况下将原生解锁误判为 DNS 解锁的缺陷。
  - 自动检测并预警地区漂移（如 Netflix 节点送中、YouTube 锁区变动）。
- 📬 **邮件 25 端口出站与全球 DNSBL 黑名单**：
  - 实时检测 IDC 是否封禁 TCP 25 端口出站能力。
  - 追踪国内外 12 家主流邮局服务连通性矩阵及全球 400+ DNS 反垃圾黑名单收录拦截趋势。
- 📋 **可视化历史快照卡片**：
  - 将冰冷的 JSON 数据一键转化为设计精致的终端快照卡片，包含 ASN、地理信息、5 库属性表格、风控条、因子徽标及流媒体状态。
  - 支持随时按 `j` 键调出 `jq` 交互查看原始底层数据。
- ⏰ **精准对齐北京时间的定时任务 (Cron)**：
  - 支持 **每天一次 / 每 3 天一次 / 每 7 天一次** 或自定义 Cron 表达式。
  - **智能时区换算**：无论服务器位于 UTC、美西、美东、欧洲还是日本，系统自动换算本机时区，确保在**北京时间凌晨 04:00 (UTC+8)** 准时静默体检。
- 🔄 **每日 24h 自动同步与核心热修复**：
  - 每天首次运行时自动从 GitHub 拉取最新主程序并同步最新检测引擎，热打补丁（IP2Location 公司类型补全、DNS 误判修复）。
- 🚨 **智能异常波动告警**：
  - 自动比对相邻存档，捕获评分骤增（≥10分）、流媒体掉解锁/送中、IP 属性漂移、黑名单新增。
  - 控制台顶部直观提示最近告警，并完整写入 `~/.ipqa/data/alerts.log`。
- 🎯 **变化感知自适应降采样 (Change-Aware Adaptive Downsampling)**：
  - 彻底攻克传统机械等间距抽样导致“突发波动落入缝隙被漏掉”的痛点！在查看 30 天或多月历史记录时，系统通过 7ms 极速多维指纹比对，**自动将所有状态突变点（IP类型变动、评分上升、解锁降级/送中、黑名单拦截等）作为关键帧（Keyframes）优先锁定上屏展示**。
  - 剩余列槽位自适应均匀插值，既保证终端表格紧凑不溢出折行，又确保任何一天的突发异动或恢复 100% 精准显现无遗。
- ⚡ **极致性能与交互升级**：
  - 单张存档卡片渲染重构为批量提取，减少 50+ 次 `jq` 子进程 fork，渲染速度提升数倍。
  - 历史归档列表新增交互式 `[n] 下一页 / [p] 上一页` 翻页导航，支持回看任意历史阶段存档。
  - 查看底层原始 JSON 优先调用 `less -R` 进行交互式滚动与 `/` 关键词搜索。
  - 单次体检结束提供精准秒级耗时反馈 `(耗时 XX 秒)`。
- 🧹 **无残留数据清理与一键彻底卸载**：
  - 支持按天数（30/90/180天）或保留最新 N 份存档清理历史数据。
  - 交互式 `[x]` 或命令行 `ipqa --uninstall` 干净移除定时任务、系统软链接与数据目录。

---

## 🖥️ 终端控制台预览

### 1. 主控制面板 (TUI Dashboard)

```text
══════════════════════════════════════════════════════════════════════
   🔍 IP 质量存档监测系统 (IPQA)  v1.0.0 (Core: v2026-09-04)
══════════════════════════════════════════════════════════════════════

  📡 节点网络: 38.244.12.34 (IPv4)  │  2602:f656:1::2 (IPv6)
  🏢 归属信息: AS1054  │  📍 Los Angeles, United States of America
  ⏰ 上次检测: 2026-09-12 04:00:00
  📦 历史存档: IPv4: 30 份  │  IPv6: 30 份
  📅 时间跨度: 2026-08-14 ~ 2026-09-12
  🔄 定时检测: 开启 [每天 (北京 04:00)] (每天自动同步主程序与核心)

── ⚠️  最近风险变化提醒 ───────────────────────────────────────────────
  • [09-11] YouTube 地区从 [US] 变为 [HK]
  • [09-08] Netflix 解锁状态发生降级: [解锁] 变为 [仅自制]
  • [09-02] AbuseIPDB 风险评分大幅上升 +15 (0 -> 15)

── 📋 功能菜单导航 ───────────────────────────────────────────────────
  [1] 📊 IP 类型属性变动       [6] 📋 历史存档图表快照
  [2] 📈 综合风险评分图        [7] ⚙️  配置定时任务
  [3] 🔬 风险因子综合矩阵      [8] 🔄 立即执行检测
  [4] 🎬 流媒体与AI解锁        [9] 🗑️  清理历史数据
  [5] 📬 邮件与黑名单监测      [0] 🚪 退出系统  [x] 🧹 卸载系统
──────────────────────────────────────────────────────────────────────
```

### 2. IP 类型属性变动表 (模块 1 预览)

```text
▶ IPv4 IP 类型属性变化分析:
  数据库 / 维度 │ 09-07    │ 09-08    │ 09-09    │ 09-10    │ 09-11    │ 09-12    │ 历史稳定性
  ──────────────────────────────────────────────────────────────────────────────────────────
  原生/广播     │ 原生IP   │ 原生IP   │ 原生IP   │ 原生IP   │ 原生IP   │ 原生IP   │ ✅ 保持稳定
  IPinfo (使用) │ isp      │ isp      │ isp      │ isp      │ isp      │ isp      │ ✅ 保持稳定
  ipreg  (使用) │ isp      │ isp      │ isp      │ isp      │ isp      │ isp      │ ✅ 保持稳定
  ipapi  (使用) │ hosting  │ hosting  │ hosting  │ hosting  │ hosting  │ hosting  │ ✅ 保持稳定
  IP2L   (使用) │ isp      │ isp      │ isp      │ isp      │ isp      │ isp      │ ✅ 保持稳定
  Abuse  (使用) │ isp      │ isp      │ isp      │ isp      │ isp      │ isp      │ ✅ 保持稳定
  IPinfo (公司) │ isp      │ isp      │ isp      │ isp      │ isp      │ isp      │ ✅ 保持稳定
  ipreg  (公司) │ hosting  │ hosting  │ hosting  │ hosting  │ hosting  │ hosting  │ ✅ 保持稳定
  ipapi  (公司) │ hosting  │ hosting  │ hosting  │ hosting  │ hosting  │ hosting  │ ✅ 保持稳定
  IP2L   (公司) │ isp      │ isp      │ isp      │ isp      │ isp      │ isp      │ ✅ 保持稳定
```

### 3. 历史存档图形化快照卡片 (模块 6 预览)

```text
┌── [IPv4 检测快照卡片] ──────────────────────────────────────────┐
  📡 节点 IP  : 38.244.12.34 (IPv4)
  🏢 组织/ASN : AS1054 (US-Hosting)
  📍 地理位置 : Los Angeles, 美国
  🌐 网络类型 : ● 原生IP
  ── 🏷️ IP 类型属性 ──────────────────────────────────────────────────
    数据库:   IPinfo      ipregistry  ipapi       IP2Location AbuseIPDB   
    使用类型: isp         isp         hosting     isp         isp         
    公司类型: isp         hosting     hosting     isp         
  ── 📊 权威风控评分 ─────────────────────────────────────────────────
    • SCAMALYTICS   ▏ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 低风险
    • IP2LOCATION   ▏ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 低风险
    • AbuseIPDB     ▏ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 低风险
    • IPQS          ▏ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 低风险
  ── 🔬 核心安全因子 ─────────────────────────────────────────────────
    Proxy: ● 正常   Tor: ● 正常   VPN: ● 正常   Server: ● 正常   Abuser: ● 正常   Robot: ● 正常
  ── 🎬 流媒体与 AI 解锁 ─────────────────────────────────────────────
    • YouTube   : ✓ 解锁 [US]
    • Netflix   : ⚡ DNS解锁 [US]
    • Disney+   : ✓ 解锁 [US]
    • TikTok    : ⚠️ 机房解锁 [US]
    • ChatGPT   : ✓ 解锁 [US]
    • Reddit    : ✗ 屏蔽/失败
  ── 📬 邮件连通与 DNS 黑名单 ─────────────────────────────────────────
    • 25 端口出站 (Port 25): ✓ 开放
    • DNS 黑名单拦截       : 0 / 400 数据库 (全部干净通过)
└──────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 快速安装与使用

### 方式一：一键自动安装 (推荐)

在终端执行以下命令（适用于 Debian / Ubuntu / CentOS / Rocky / Alma / Alpine / Arch / Fedora 等系统）：

```bash
bash <(curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/install.sh)
```

或如果已克隆本仓库到本地：

```bash
git clone https://github.com/Chen017/IP-Quality-Archive.git
cd IP-Quality-Archive
bash install.sh
```

### 方式二：非交互式无人值守安装 (自动化脚本专用)

在脚本部署场景下，加上 `-y` 参数可实现全自动无人值守安装（默认配置每天北京时间凌晨 04:00 定时检测并立即运行初始归档）：

```bash
bash install.sh -y
```

### 方式三：平滑在线升级

当有新版本发布时，直接运行以下命令即可无缝升级，**所有历史存档、配置文件与定时任务均会被 100% 完整保留**：

```bash
ipqa --update
# 或者再次执行在线安装脚本，将自动检测并转入平滑更新模式：
bash <(curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/install.sh)
```

### 方式四：一键彻底卸载

如果您不再需要 IPQA，可通过以下任一命令一键干净卸载，自动清除定时任务、全局命令软链接并可选择性删除历史数据：

```bash
ipqa --uninstall
# 或通过安装脚本卸载：
bash install.sh --uninstall
```

---

## 📖 命令行参数速查

安装完成后，全局注册了 `ipqa` 命令：

| 命令 / 参数 | 说明 | 适用场景 |
| :--- | :--- | :--- |
| `ipqa` | 启动交互式终端图形管理面板 (TUI) | 日常监控、查看图表、交互操作 |
| `ipqa --check` | 立即前台触发一次完整检测并写入历史存档 | 手动测试、排查网络质量 |
| `ipqa --cron` | 静默后台执行检测（自动同步最新核心，输出定向至日志） | `crontab` 专用自动调度 |
| `ipqa --status` | 快速打印当前存档统计、最新 IP 及最近检测时间 | 命令行状态速查、健康检查 |
| `ipqa --update` | 从 GitHub 在线拉取并更新 IPQA 主程序及检测核心 | 在线平滑升级 |
| `ipqa --uninstall` | 交互式卸载 IPQA 并清理 crontab 任务与系统链接 | 干净卸载 |
| `ipqa --help` / `-h` | 打印命令行帮助说明 | 查阅参数选项 |

---

## 🧭 功能模块深度解析

### 1. 📊 IP 类型属性变动 (`[1]`)
- 横向时间轴对比最近 8 次体检的 IP 属性变化。
- 整合 **原生/广播判定** 及 **IPinfo、ipregistry、ipapi、IP2Location、AbuseIPDB** 的「使用类型」与「公司类型」。
- 自动计算「历史稳定性」，若检测过程中发生 ISP 变更为 Hosting（例如机房重标）立即高亮提示。

### 2. 📈 综合风险评分趋势图 (`[2]`)
- 提取 **SCAMALYTICS、IP2LOCATION、AbuseIPDB、IPQS、ipapi、DBIP** 的历史评分。
- 水平柱状图直观呈现，并以 🟢 0-25 安全、🟡 26-50 中等、🔴 51-75 风险、🟣 76-100 极高风险四色阶渲染。

### 3. 🔬 风险因子综合矩阵 (`[3]`)
- 深度挖掘 **Proxy / Tor / VPN / Server / Abuser / Robot** 6 大因子的检出状态。
- 显示 9 家权威引擎对当前各因子的交叉检出比率（如 `0/9 正常` 或 `2/9 检出`）。
- 历史时间线追踪每一个风险因子的综合安全评级（`保持安全` vs `曾有检出`）。

### 4. 🎬 流媒体与 AI 解锁历史 (`[4]`)
- 全面监测 TikTok、Disney+、Netflix、YouTube、Amazon Prime Video、Reddit、ChatGPT 等平台。
- 动态区分 **原生解锁**（绿色 `●`）、**DNS 分流解锁**（黄色 `●` ⚡）、**仅自制剧**、**机房解锁**、**仅网页/仅APP** 及 **封锁屏蔽**（红色 `●`）。
- 追踪地区代码漂移（如 `[US]` -> `[HK]`），及时告警 IP 送中或跨区。

### 5. 📬 邮件连通与 DNS 黑名单 (`[5]`)
- 检查出站 25 端口能力（许多云厂商默认拦截 TCP 25 出站）。
- 矩阵化展示连接国内外主流邮件服务商（Gmail、Outlook、QQ 邮箱、163 等）的连通状态。
- 统计全球 400+ DNS 反垃圾黑名单（DNSBL）的拦截计数与历史增减。

### 6. 📋 历史存档图表快照 (`[6]`)
- 双栈合并时间轴索引，输入序号一键查看对应时间的完整卡片快照。
- **分页导航**：支持 `[n] 下一页 / [p] 上一页`，彻底摆脱单页 15 条限制，轻松翻阅任意早期的历史记录。
- **结构化排版**：节点网络、ASN 组织、地理归属、原生/广播、5 大检测商表格、风控条、安全因子、解锁明细、邮件黑名单。
- **交互式翻阅**：提供 `[j]` 快捷键，优先通过 `less -R` 交互翻阅底层完整 JSON，支持上下翻卷与 `/` 关键词搜索，无 `less` 环境优雅回退。

### 7. ⚙️ 配置定时任务 (`[7]`)
- 提供三种精心调优的黄金周期：
  - `[1]` 每天凌晨 4 点检测一次 (北京时间 04:00) **[推荐]**
  - `[2]` 每 3 天检测一次 (北京时间 04:00)
  - `[3]` 每 7 天检测一次 (北京时间 04:00)
  - `[4]` 自定义输入任意 Cron 表达式
  - `[5]` 关闭/移除定时任务
- **时区自适应算法**：自动识别服务器时区偏移量，无论 VPS 设在哪个时区，生成的 Cron 时间均精准对应**北京时间 04:00**。

### 8. 🔄 立即执行检测 (`[8]`)
- 立即唤起 IPQuality 核心分别执行 IPv4 与 IPv6 完整检测。
- **精准耗时反馈**：检测过程带有秒级耗时统计（完成时输出 `检测完成！(耗时 XX 秒)`），直观了解网络连通效率。
- 自动写入 JSON 存档，与上一次存档进行比对，若触发阈值立即追加告警日志并展示检测报告。

### 9. 🗑️ 清理历史数据 (`[9]`)
- 统计当前 IPv4 与 IPv6 存档所占空间及份数。
- 支持按保留天数（30天/90天/180天）清理、按保留最新 N 份清理，或一键重置告警日志与存档数据。

---

## 📁 目录结构与配置文件

IPQA 默认部署于用户目录下的 `~/.ipqa/`，结构极为清爽，无杂乱文件：

```text
~/.ipqa/
├── ipqa.sh               # IPQA 主程序 (终端 TUI 与 CLI 逻辑)
├── ip.sh                 # IPQuality 检测引擎 (自动缓存与热修复)
├── config.sh             # 用户自定义配置文件
├── .last_core_update     # 每日核心自动同步时间戳记
├── data/
│   ├── v4/               # IPv4 历史检测 JSON 存档 (YYYY-MM-DD_HHMMSS.json)
│   ├── v6/               # IPv6 历史检测 JSON 存档
│   └── alerts.log        # 异常风控与解锁告警日志
└── logs/
    └── ipqa.log          # 运行与 Cron 定时检测执行日志
```

### 配置文件 `config.sh`

可在 `~/.ipqa/config.sh` 中按需微调以下参数：

```bash
# 检测间隔基准 (小时)
CHECK_INTERVAL_HOURS=24

# 是否检测 IPv6 (auto: 自动探测 / true: 强制检测 / false: 仅 IPv4)
HAS_V6="auto"

# 风险评分突变告警阈值 (默认当评分较上次上升超过 10 分时触发告警)
SCORE_DIFF_THRESHOLD=10

# 期望的流媒体地区 (当实际地区不符合时触发告警，留空则仅监测地区漂移)
EXPECTED_YOUTUBE_REGION=""
EXPECTED_NETFLIX_REGION=""

# 最大保留存档份数 (0 为永久保存，超出则自动滚动淘汰最旧存档)
KEEP_MAX_ARCHIVES=0
```

---

## 🔧 系统依赖与环境支持

IPQA 安装脚本已内置主流 Linux 发行版的包管理器自动检测与依赖补齐机制：

| 依赖组件 | 作用说明 | 缺失时安装策略 |
| :--- | :--- | :--- |
| `bash 4.0+` | 脚本运行基础（支持关联数组与高级字符串操作） | 现代 Linux 系统标配 |
| `jq` | JSON 存档高效解析与数据抽取 | 通过 `apt` / `dnf` / `yum` / `pacman` / `apk` 自动安装 |
| `curl` | 上游脚本拉取与网络质量探测 | 自动安装 |
| `cron` / `crontab` | 定时检测任务调度 | 自动安装 |
| `dnsutils` / `bind-utils` | `dig` 与 `nslookup`，保障原生 vs DNS 解锁诊断精确性 | 自动检测并提示/安装 |

**经测试兼容的环境：**
- Debian 10 / 11 / 12
- Ubuntu 18.04 / 20.04 / 22.04 / 24.04
- CentOS 7 / 8 / 9 Stream
- Rocky Linux & AlmaLinux 8 / 9
- Alpine Linux 3.16+
- Arch Linux
- Fedora 36+
- Windows Subsystem for Linux (WSL / WSL2)

---

## 🤝 鸣谢与开源协议

- 本项目采用 **[GNU General Public License v3.0](LICENSE)** 开源。
- 核心检测引擎技术基于并致敬优秀的上游项目 **[IPQuality (xykt/IPQuality)](https://github.com/xykt/IPQuality)**。
- 感谢所有为 IP 质量与网络流媒体解锁检测做出开源贡献的开发者。
