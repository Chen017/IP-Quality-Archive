# IP Quality Archive (IPQA)

基于 [IPQuality](https://github.com/xykt/IPQuality) 的 Linux IP 质量定时归档与历史监测工具。支持双栈独立归档、趋势图表与异常变动告警。

## 一键安装

```bash
# 交互式安装
bash <(curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/install.sh)

# 无人值守安装（默认每日北京时间 04:00 检测）
bash <(curl -sL https://raw.githubusercontent.com/Chen017/IP-Quality-Archive/main/install.sh) -y
```

安装完成后在终端运行 `ipqa` 即可。

## 功能特性

- **双栈归档**：IPv4 / IPv6 分别定时检测与归档（JSON 存储）。
- **历史走势**：终端查看 IP 类型判定、风控评分（Scamalytics / AbuseIPDB 等）、欺诈标记、流媒体解锁（Netflix / YouTube 等）的历史演变。
- **变动感知采样**：查看长期历史时，自动优先保留发生过属性变动的节点，避免固定抽样错过变动。
- **变动告警**：风控分上升、流媒体掉解锁/地区漂移、被列入黑名单时记录至 `alerts.log`。
- **定时巡检**：自动换算服务器本地时区，定时静默执行检测。

## 常用命令

| 命令 | 说明 |
| :--- | :--- |
| `ipqa` | 打开终端交互菜单 |
| `ipqa --check` | 立即执行一次完整检测并归档 |
| `ipqa --status` | 查看当前最新 IP 与存档统计 |
| `ipqa --cron` | 静默执行检测（Crontab 定时调用） |
| `ipqa --update` | 更新主程序与检测引擎 |
| `ipqa --uninstall` | 卸载程序并清理定时任务 |

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
