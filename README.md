# Linux Server Daily Inspection Tool

> 一行命令巡检 Linux 服务器 —— CPU、内存、磁盘、进程、日志、网络、安全，一键出报告。

[![Version](https://img.shields.io/badge/version-v2.0-blue)](#)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnu-bash&logoColor=white)](#)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Raspberry%20Pi-orange)](#)
[![License](https://img.shields.io/badge/license-MIT-green)](#)

---

## 快速开始

```bash
# 1. 下载项目
git clone https://github.com/Jun-shisheng/Linux_server_inspection.git
cd Linux_server_inspection

# 2. 运行全量巡检（推荐 root 执行以获得完整信息）
sudo bash scripts/main.sh

# 报告自动保存到 reports/ 目录
```

**就是这么简单。** 不需要装任何依赖，纯 bash 脚本，任何 Linux 发行版开箱即用。

---

## 功能模块

| 模块 | 脚本 | 功能 |
|------|------|------|
| 系统资源 | `system_info.sh` | CPU 使用率、负载、内存、磁盘、运行时间 |
| 进程与服务 | `process_check.sh` | TOP5 进程、sshd/cron 状态、异常进程检测 |
| 日志分析 | `log_analysis.sh` | syslog 异常关键词统计、高频错误 TOP5、最近异常 |
| 网络检测 | `network_check.sh` | 公网连通性、DNS 解析、监听端口、网关、网卡状态 |
| 安全检测 | `security_check.sh` | 失败登录、SUID 文件、空密码用户、sudo 记录 |
| 定时任务 | `cron_setup.sh` | 配置每日自动巡检 |

---

## 常用命令

```bash
# 全量巡检（推荐）
sudo bash scripts/main.sh

# 单独运行某个模块
bash scripts/system_info.sh      # 只看系统资源
bash scripts/process_check.sh    # 只看进程
bash scripts/log_analysis.sh     # 只看日志
bash scripts/network_check.sh    # 只看网络
bash scripts/security_check.sh   # 只看安全

# 设置每天 8:00 自动巡检
bash scripts/cron_setup.sh

# 查看历史报告
ls -lh reports/
cat reports/inspection_*.txt

# 运行测试
bash scripts/tests/test_main.sh

# 更新到最新版本
git pull origin master
```

---

## 输出示例

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
[OK] Memory usage normal

========== 安全检测 ==========
失败登录: 3 次
[OK] 失败登录次数正常
SUID 文件: 42 个（标准系统文件，无异常）
[OK] 安全检测全部正常

============================================================
        Inspection Complete — Report saved to reports/
============================================================
```

---

## 定时自动巡检

```bash
# 安装定时任务（默认每天 8:00）
bash scripts/cron_setup.sh install

# 自定义时间
bash scripts/cron_setup.sh install "0 20 * * *"    # 每天 20:00
bash scripts/cron_setup.sh install "*/30 * * * *"   # 每 30 分钟

# 查看状态
bash scripts/cron_setup.sh status

# 卸载定时任务
bash scripts/cron_setup.sh uninstall
```

---

## 适用环境

- Ubuntu / Debian / Raspberry Pi OS / CentOS
- 树莓派、VPS、homelab 服务器
- 不需要安装任何额外软件包

---

## License

MIT
