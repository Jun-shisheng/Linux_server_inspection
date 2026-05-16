# 🖥️ Linux Server Daily Inspection Tool

[![Version](https://img.shields.io/badge/version-v2.0-blue)](#)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnu-bash&logoColor=white)](#)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Raspberry%20Pi-orange)](#)
[![License](https://img.shields.io/badge/license-MIT-green)](#)
[![ShellCheck](https://github.com/Jun-shisheng/Linux_server_inspection/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Jun-shisheng/Linux_server_inspection/actions/workflows/shellcheck.yml)

> 一行命令，全面掌握服务器状态。纯 Bash 实现，零依赖。

---

## 项目简介

管理 Linux 服务器时，每天都要手动敲 `top`、`free`、`df`、`ps`、`ss`、`grep`……繁琐且容易遗漏。

这个工具把这些命令整合成**一条命令**——自动检查 CPU、内存、磁盘、进程、日志、网络、安全，发现异常会标红警告，并保存结构化的巡检报告。适合树莓派、VPS、homelab 玩家和 Linux 初学者。

---

## 快速开始

```bash
# 下载
git clone https://github.com/Jun-shisheng/Linux_server_inspection.git
cd Linux_server_inspection

# 全量巡检（推荐 root 执行）
sudo bash scripts/main.sh
```

不需要安装任何依赖，任何 Linux 发行版开箱即用。

---

## 功能模块一览

| # | 模块 | 脚本 | 功能 |
|---|------|------|------|
| 1 | **系统资源** | `system_info.sh` | CPU 使用率、负载均值、内存占用、磁盘分区、运行时间 |
| 2 | **进程与服务** | `process_check.sh` | CPU/内存 TOP5 进程、sshd/cron 状态、异常进程检测 |
| 3 | **日志分析** | `log_analysis.sh` | syslog 异常关键词扫描（error/fail/warn/oom/segfault）、高频错误 TOP5、最近异常 |
| 4 | **网络检测** | `network_check.sh` | 公网 ping、DNS 解析、TCP 监听端口、默认网关、网卡状态 |
| 5 | **安全检测** | `security_check.sh` | 失败登录统计、SUID/SGID 文件、空密码用户、世界可写文件、sudo 记录 |
| 6 | **定时任务** | `cron_setup.sh` | 配置每日自动巡检并归档报告 |

每个模块可独立运行，也可通过 `main.sh` 一键全量执行。

---

## 运行效果

```
============================================================
       Linux Server Daily Inspection Report
       Time: 2026-05-16 14:30:00
       Host: raspberrypi
       Version: v2.0
============================================================

========== CPU & System Load ==========
CPU Usage: 12%  |  Cores: 4
Load (1/5/15min): 0.35 / 0.42 / 0.38
[OK] Load within normal range

========== Memory Usage ==========
Total: 7.6G   Used: 1.2G   Free: 5.8G   Available: 6.1G
Memory Usage: 15.8%
[OK] Memory usage normal

========== Disk Usage ==========
/dev/mmcblk0p2  Total: 58G  Used: 22G  Avail: 34G  (40%)
[OK] All partitions below 80%

========== TOP5 CPU Processes ==========
PID   %CPU   COMMAND
 892   8.2   kworker/u8:2
 1054  3.1   python3
[OK] No suspicious processes

========== 日志异常分析 ==========
error:      3 条
fail:       1 条
oom:        2 条
segfault:   1 条
[注意] 存在 7 条异常日志，请关注

========== 安全检测 ==========
失败登录次数: 3 次
[OK] 登录次数在正常范围内
SUID 文件: 42 个（标准系统文件）
[OK] 安全检测全部正常

============================================================
        ✓ Inspection Complete — Report saved to reports/
============================================================
```

---

## 常用操作

```bash
# 全量巡检
sudo bash scripts/main.sh

# 单独跑某个模块
bash scripts/system_info.sh       # 系统资源
bash scripts/process_check.sh     # 进程
bash scripts/log_analysis.sh      # 日志
bash scripts/network_check.sh     # 网络
bash scripts/security_check.sh    # 安全

# 设置每天 8:00 自动巡检
bash scripts/cron_setup.sh

# 自定义时间
bash scripts/cron_setup.sh install "0 20 * * *"    # 每晚 8 点
bash scripts/cron_setup.sh install "*/30 * * * *"  # 每 30 分钟

# 查看报告
ls -lh reports/
cat reports/inspection_*.txt

# 运行测试
bash scripts/tests/test_main.sh

# 更新到最新
git pull origin master
```

---

## 适用环境

- Ubuntu / Debian / Raspberry Pi OS / CentOS
- 树莓派、VPS、云服务器、homelab
- 无需安装额外软件包

---

## License

MIT
