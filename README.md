# IP Quality Archive (IPQA)

<p align="center">
  <strong>面向 Linux VPS 的 IP 质量定时归档、历史追踪与异常变动监测工具</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="AGPL-3.0"></a>
  <a href="https://github.com/xykt/IPQuality"><img src="https://img.shields.io/badge/Core-IPQuality-10b981" alt="IPQuality"></a>
  <a href="https://github.com/Chen017/komari-plugin-ipqa-alert-report"><img src="https://img.shields.io/badge/Komari-IPQA%20Integration-7c3aed" alt="Komari Integration"></a>
  <a href="https://github.com/Chen017/komari-emerald-suite"><img src="https://img.shields.io/badge/Komari%20Emerald-Ecosystem-10b981" alt="Komari Emerald Ecosystem"></a>
</p>

基于 [IPQuality](https://github.com/xykt/IPQuality) 的 Linux IP 质量定时归档与历史监测工具。  
在保留原始 IP 质量检测能力的基础上，提供 **IPv4 / IPv6 独立归档、历史趋势、风险变化摘要与异常告警记录**。

IPQA 可以完全独立使用；如果同时部署 Komari，还可通过配套插件将本地归档同步到服务器，并在 **Komari Emerald Insights** 中获得完整的图形化历史档案与集群质量视图。

---

## 一键安装
脚本支持 Debian/Ubuntu

```bash
bash <(curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/install.sh)
```

安装完成后运行：

```bash
ipqa
```

即可打开终端交互菜单。

---

## 核心特性

- **双栈独立归档**  
  IPv4 / IPv6 分别定时检测并以 JSON 形式独立保存，便于长期回溯与比较。

- **历史趋势分析**  
  在终端中查看 IP 类型判定、风控评分（Scamalytics / AbuseIPDB 等）、欺诈标记，以及 Netflix、YouTube、Amazon Prime Video、AI 服务等解锁状态的历史演变。

- **每日风险摘要**  
  自动归纳近期风险变化，例如：
  - 风控评分明显上升
  - 流媒体掉解锁
  - 解锁地区漂移
  - DNSBL / 黑名单状态变化
  - IP 类型与关键属性变化

- **异常告警记录**  
  重要变化会写入：

  ```text
  ~/.ipqa/data/alerts.log
  ```

  可供人工查看，也可被 Komari IPQA 插件进一步汇总。

- **定时巡检**  
  根据服务器本地时区执行周期检测，支持 Crontab 静默运行。

- **检测核心更新**  
  可通过 `ipqa --update` 更新程序及上游检测核心。

---

## 常用命令

| 命令 | 说明 |
| :--- | :--- |
| `ipqa` | 打开终端交互菜单 |
| `ipqa --check` | 立即执行一次完整检测并归档 |
| `ipqa --status` | 查看当前状态概况与近三日风险变化详情；纯文本适配远程运维，支持 `--color` |
| `ipqa --cron` | 静默执行检测，适合 Crontab 定时调用 |
| `ipqa --update` | 手动更新主程序与检测引擎 |
| `ipqa --enable-auto-update` | 启用每日自动同步更新 IPQA 脚本本身（默认开启） |
| `ipqa --disable-auto-update` | 禁用每日自动同步更新 IPQA 脚本本身（保留本地修改） |
| `ipqa --auto-update` | 查看当前 IPQA 脚本自身自动更新状态 |
| `ipqa --uninstall` | 卸载程序并清理定时任务 |

---

## 界面预览

### 主控制面板

<p align="center">
  <a href="pics/dashboard.png"><img src="pics/dashboard.png" alt="主控制面板" width="720" /></a>
  <br>
  <em>主控制面板：双栈信息、变动提醒与功能导航</em>
</p>

### 历史趋势图表

> 回看历史时自动采用变动感知采样，优先提取发生过属性变化的节点。点击图片可放大查看原图。

| IP 类型演变分析 | 流媒体与 AI 解锁历史 |
| :---: | :---: |
| <a href="pics/type_analysis.png"><img src="pics/type_analysis.png" width="380" alt="IP 类型属性变动分析" /></a> | <a href="pics/media_unlock.png"><img src="pics/media_unlock.png" width="380" alt="流媒体与 AI 解锁历史" /></a> |
| **核心安全因子矩阵与追踪** | **邮件连通与 DNS 黑名单监测** |
| <a href="pics/risk_factors.png"><img src="pics/risk_factors.png" width="380" alt="风险因子综合矩阵" /></a> | <a href="pics/email_dnsbl.png"><img src="pics/email_dnsbl.png" width="380" alt="邮件连通性与 DNS 黑名单" /></a> |

### 历史存档与全量快照

<p align="center">
  <a href="pics/archive_list.png"><img src="pics/archive_list.png" width="620" alt="历史存档列表分页" /></a>
  <br>
  <em>历史存档列表：支持 [n]/[p] 交互分页与单条快照检索</em>
</p>

| 综合风险评分历史走势（长图） | 历史双栈检测快照卡片（长图） |
| :---: | :---: |
| <a href="pics/risk_score.png"><img src="pics/risk_score.png" width="280" alt="综合风险评分历史走势" /></a> | <a href="pics/snapshot_card.png"><img src="pics/snapshot_card.png" width="460" alt="双栈历史存档快照卡片" /></a> |

---

## Komari Emerald Ecosystem 集成

IPQA 本身不依赖 Komari，可以单独部署和使用。

如果已经使用 Komari，可以按以下方式扩展：

```text
                         Komari
                            │
                            ▼
                Komari Emerald Insights
                            │
              ┌─────────────┴─────────────┐
              │                           │
              ▼                           ▼
   Availability History          IPQA Alert Report
                                          │
                                          ▼
                                IP Quality Archive
                                  （本项目 / VPS）
```

- [Komari Emerald Suite](https://github.com/Chen017/komari-emerald-suite)：生态聚合展示主页
- [Komari Emerald Insights](https://github.com/Chen017/komari-theme-emerald-insights)：现代化 Komari 前端主题
- [IPQA Alert Report](https://github.com/Chen017/komari-plugin-ipqa-alert-report)：IPQA 数据同步、历史 API 与告警插件
- [Availability History](https://github.com/Chen017/komari-plugin-availability-history)：基于事件账本的精确在线率插件

Availability History 与 IPQA 功能互相独立，不是 IPQA 的必需依赖。

---

## Related Projects

- [IPQuality](https://github.com/xykt/IPQuality) — IP 质量检测核心
- [Komari](https://github.com/komari-monitor/komari) — 轻量服务器监控平台

---

## 许可证与致谢

- 本项目采用 [AGPL-3.0](LICENSE) 协议。
- 检测核心基于 [IPQuality (xykt/IPQuality)](https://github.com/xykt/IPQuality)。
- 感谢 Komari 及相关开源项目提供的扩展与集成基础。
