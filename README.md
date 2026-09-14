# IP Quality Archive (IPQA)

基于 [IPQuality](https://github.com/xykt/IPQuality) 的 Linux IP 质量定时归档与历史监测工具。支持双栈独立归档、趋势图表与异常变动告警。

## 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/install.sh)
```

安装完成后在终端运行 `ipqa` 即可。

## 功能特性

- **双栈归档**：IPv4 / IPv6 分别定时检测与归档（JSON 存储）。
- **历史走势**：终端查看 IP 类型判定、风控评分（Scamalytics / AbuseIPDB 等）、欺诈标记、主流流媒体与 AI 解锁（Netflix / YouTube / Amazon Prime Video 等）的历史演变。
- **变动感知采样**：查看长期历史时，自动优先保留发生过属性变动的节点，避免固定抽样错过变动。
- **每日聚合提醒**：面板直观展示最近多日的风险变化智能摘要，风控分上升、流媒体掉解锁/地区漂移、被列入黑名单时智能归纳并记录至 `alerts.log`。
- **定时巡检**：自动换算服务器本地时区，定时静默执行检测并自动同步更新核心。

## 常用命令

| 命令 | 说明 |
| :--- | :--- |
| `ipqa` | 打开终端交互菜单 |
| `ipqa --check` | 立即执行一次完整检测并归档 |
| `ipqa --status` | 查看当前最新 IP 与存档统计 |
| `ipqa --cron` | 静默执行检测（Crontab 定时调用） |
| `ipqa --update` | 更新主程序与检测引擎 |
| `ipqa --uninstall` | 卸载程序并清理定时任务 |

## 界面预览

### 主控制面板
<p align="center">
  <a href="pics/dashboard.png"><img src="pics/dashboard.png" alt="主控制面板" width="720" /></a>
  <br>
  <em>主控制面板：双栈信息、变动提醒与功能导航</em>
</p>

### 历史趋势图表
> 回看历史时自动采用变动感知采样，优先提取发生过属性变动的节点。点击图片可放大查看原图。

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

## 目录结构

所有配置与数据默认保存在 `~/.ipqa/`：

```text
~/.ipqa/
├── config.sh       # 配置文件（检测周期、保留天数、告警阈值等）
├── data/
│   ├── v4/         # IPv4 历史存档 (YYYY-MM-DD_HHMMSS.json)
│   ├── v6/         # IPv6 历史存档
│   └── alerts.log  # 变动告警记录
└── logs/           # 运行日志
```

## 许可证与致谢

- 协议：[GPL-3.0](LICENSE)
- 检测核心基于 [IPQuality (xykt/IPQuality)](https://github.com/xykt/IPQuality)。
