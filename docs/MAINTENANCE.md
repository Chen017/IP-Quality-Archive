# IPQA 工程维护指南

## 目录与运行边界

| 位置 | 职责 |
| --- | --- |
| `install.sh` | 独立安装入口。检查 Debian/Ubuntu 与依赖，优先安装同目录的 `ipqa.sh`，否则从 `main` 获取；创建配置、命令链接并可选配置 Cron。 |
| `ipqa.sh` | CLI 和终端菜单。管理本地配置、更新锁、检测核心缓存、双栈归档、告警和历史展示。 |
| `tests/` | Shell 静态检查、离线回归和安装包验证。`fixtures/` 保存带来源注释的上游函数片段。 |
| `scripts/package.sh` | 生成包含 `install.sh`、`ipqa.sh` 和许可证的安装包。 |
| `.github/workflows/ci.yml` | 运行静态检查、两种 awk 的离线回归及安装包测试。 |

运行目录默认是 `~/.ipqa`。运行时优先使用显式 `IPQA_DIR`，否则解析实际启动脚本及其软链接，在脚本同目录有 `config.sh` 时使用该目录。安装器可通过 `--dir` 指定路径。脚本支持 Bash 4.2 及以上，依赖 `curl`、`jq` 和 GNU 用户空间工具。Cron 和 DNS 查询分别使用 `cron`、`dnsutils`。

- `config.sh` 由白名单解析器读取，应填写普通键值。旧 `AUTO_UPDATE` 仅在新字段缺失时生效，保存后写入规范化的 `AUTO_UPDATE_SCRIPT`。保留现有用户配置和数据目录是升级流程的要求。
- `data/v4/`、`data/v6/` 保存独立的报告，`data/alerts.log` 保存 `时间|等级|消息|协议` 记录，`logs/ipqa.log` 保存运行诊断。Komari 插件可消费这些文件，修改命名、JSON 或日志格式前先核对消费者。
- `ip.sh` 是动态获取的检测核心。安装器与运行时都需要独立工作，因此各自包含校验和补丁逻辑。修改共同规则时检查两个入口，运行时另外应用 DNS 启发式保护。

## 本地开发与测试

在 Debian、Ubuntu 或相应的 WSL 环境中，从仓库根目录执行以下命令。

```bash
sudo apt-get install jq curl shellcheck mawk gawk util-linux
bash tests/check.sh
bash tests/test_suite.sh mawk
bash tests/test_suite.sh gawk

bundle_dir="$(mktemp -d)"
bash scripts/package.sh "$bundle_dir/ipqa.tar.gz"
bash tests/test_install_bundle.sh "$bundle_dir/ipqa.tar.gz"
```

静态检查解析全部 Shell 文件并用 ShellCheck 检查项目维护的脚本。上游函数夹具单独做 Bash 语法检查。默认运行 `bash tests/test_suite.sh` 时使用环境里的 `awk`；传入名称时缺少该工具会直接报错。

运行时回归通过临时 HOME、固定报告及下载替身覆盖 CLI、归档、告警和菜单。安装包测试替换网络、系统链接、包管理器和 Cron 操作，覆盖解包安装、升级保留数据、卸载及删除保护。单独调试可运行 `bash tests/test_runtime.sh`、`bash tests/test_dbip.sh` 等对应脚本。生产排障先用 `ipqa --test`、`ipqa --status` 和运行日志定位，实际网络采集可在测试 VPS 执行 `ipqa --check --no-auto-update`。该参数只跳过本次 IPQA 自更新，上游核心仍可检查更新。

## CI、打包与动态更新

- CI 接收面向 `main` 的 PR、包含工程改动的 `main` 推送和手动触发。仅改 README、`docs/` 或 `pics/` 的 `main` 推送会跳过，PR 保留检查。相同事件及引用的新运行会取消仍在执行的旧运行。
- 同一个 Ubuntu 24.04 runner 复用检出和工具，只在缺少工具时通过 apt 补齐。静态检查一次，随后分别跑 mawk、gawk 完整回归。两种回归通过后构建并验证安装包。失败时先在对应步骤确认工具、awk 实现和测试组，再本地复跑同一条命令。
- Shell 项目的源文件即可执行。打包脚本通过固定文件清单、权限和归档时间构建 `tar.gz`，产物写到指定路径。解包后可运行 `bash install.sh`，同目录的主脚本会被优先选用，检测核心仍按安装器的本地或在线来源获取。
- 线上入口直接读取 `main`，因此合入就是分发。CI 使用只读仓库权限，工作流内的安装包供验证使用。手动 `ipqa --update` 立即尝试同步两份脚本。检测和打开主菜单时，自动更新按各自的时间戳每天检查一次，旧 `.last_auto_update` 会迁移为两份独立时间戳。遇到回归可通过修复或回退 `main` 恢复分发，再按需手动更新客户端。

## 关键兼容约定与回归定位

| 约定 | 原因与回归入口 |
| --- | --- |
| 校验候选并比较补丁后的内容 | 上游可能在 `script_version` 相同的情况下合入修复（`bcc28d5`）。成功替换才更新成功状态与时间戳，失败继续使用缓存。`test_runtime.sh` 用真实 `--cron` 和 `--update` 验证同版本修复、坏候选、写入失败及部分成功。 |
| 双栈、隐私格式和归档原子写入 | `-p` 输出的脱敏地址是合法数据（`2951a22`）。先验证对应协议，再替换目标；无效报告不能覆盖同时间戳的有效报告。`test_suite.sh`、`test_runtime.sh` 覆盖。 |
| 检测和更新共用锁 | 运行时以目录和 PID 跟踪持有者及嵌套深度。恢复死亡进程的锁时用系统 `flock` 串行重新检查 PID，避免并发恢复者移动刚重建的锁目录。`test_suite.sh` 验证恢复互斥和跨进程竞争。 |
| DB-IP 访客查询限制 | `/self` 的 IPv4 与 IPv6 不可互用（`850b555`）。IPv6 保持空值；IPv4 响应允许缺少 `ipAddress`，仍需验证有效结果。失败日志用 `[IPQA DB-IP]` 标识并记录阶段、HTTP 状态或原因，省略临时 key。参见 `test_dbip.sh`。 |
| Lite 评分、DNS 和 awk | MaxMind 不可用时，Lite 仍独立执行五个评分来源，各尝试一次，有效值正常入库（`7dd2840`）。DNS 查询对照用于排除 wildcard 假阳性（`ea750f8`）；补丁须兼容 mawk 与 gawk（`339031e`）。参见 `test_lite.sh`、`test_awk_compat.sh` 及主套件中的 DNS 用例。 |
| 旧 WHOIS 字段、三态结果和解锁变化 | `WHOIS` 仅是 `IPWHOIS` 的旧字段名（`3c85557`）。明确的 `false` 属于已检测结果，缺失或未知数据应单独显示。包含「未解锁」的状态应记录为降级。参见 `test_runtime.sh`。 |
| 归档历史与配对 | 同名 IPv6 优先，随后选 300 秒内最近候选，保留旧文件名格式和跨日配对。列表按页准备时间索引与批量 JSON 元数据，缓存只在当前菜单会话有效（`937b2f4`、`7031824`）。参见 `test_archive_performance.sh` 的进程调用上限、损坏文件隔离和跨页编号用例。 |
| 路径和 Cron | 安装与卸载保护系统和用户敏感目录。彻底清除数据要求目标可识别为 IPQA 安装。默认保留数据。Cron 的北京时间 04:00 判断和本地分钟分别处理，避免整小时假设。路径先处理 shell 双引号内的特殊字符，再转义 Cron 的百分号，含换行的路径不能写入定时任务。参见 `test_install_bundle.sh`、`test_review_fixes.sh` 及主套件中的路径和时区用例。 |

## 常见故障

| 现象 | 排查 |
| --- | --- |
| 定时任务未执行 | 用安装用户执行 `crontab -l`，核对脚本与日志的绝对路径、权限及服务器时区。再用 `ipqa --status` 检查任务识别。 |
| 执行检测失败或某协议缺数据 | 检查 `logs/ipqa.log`、`HAS_V6` 和上游接口状态。报告格式失败、无 IPv6 和接口临时故障需分别判断。 |
| 更新未生效 | 检查 `ipqa --auto-update`、`main` 中实际脚本、运行目录权限及两个更新戳。查看日志中的网络、校验和写入信息。 |
| 核心夹具或补丁测试失败 | 对照上游函数及测试夹具来源，确认是上游结构变化还是补丁回归，再分别验证独立安装器和已安装的运行时。 |

变更 CLI、配置、存档格式、安装更新流程或兼容逻辑时，同步更新本页、受影响的 README 用法和对应回归用例。
