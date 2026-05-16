# Linux Server Daily Inspection Tool

> Lightweight one-click Linux server health check & automated inspection tool. Built for Raspberry Pi enthusiasts, homelab owners, and Linux beginners.

[![Version](https://img.shields.io/badge/version-v1.0-blue)](#)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnu-bash&logoColor=white)](#)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Raspberry%20Pi-orange)](#)
[![License](https://img.shields.io/badge/license-MIT-green)](#)

---

## Table of Contents

- [Why This Tool](#why-this-tool)
- [Features](#features)
- [Quick Start](#quick-start)
- [Module Overview](#module-overview)
- [Project Structure](#project-structure)
- [Usage](#usage)
- [Automated Inspection (crontab)](#automated-inspection-crontab)
- [Tech Stack](#tech-stack)
- [Development Roadmap](#development-roadmap)
- [Test Plan](#test-plan)

---

## Why This Tool

Managing a personal Linux server or Raspberry Pi usually means running the same commands every day:

```bash
top    free    df    ps    ss    grep /var/log/syslog
```

This is tedious, error-prone, and leaves no historical record. This tool replaces all that with a **single command** that checks everything, flags anomalies, and saves a structured report — so you don't miss anything.

---

## Features

- **One-click full inspection** — CPU, memory, disk, load, processes, logs, network
- **Automatic anomaly detection** — high load, disk full, service down, log errors
- **Structured report output** — color-coded terminal output + saved text report
- **Scheduled unattended runs** — crontab integration for daily automated checks
- **Zero extra dependencies** — pure Bash, works out of the box on any Linux distro
- **Raspberry Pi friendly** — lightweight, no heavy runtime needed

---

## Quick Start

```bash
# 1. Clone the repository
git clone git@github.com:Jun-shisheng/Linux_server_inspection.git
cd Linux_server_inspection

# 2. Make scripts executable
chmod +x scripts/*.sh

# 3. Run inspection
./scripts/main.sh

# 4. View the report
ls -la reports/
cat reports/inspection_*.txt
```

---

## Module Overview

| # | Module | Description | Status |
|---|--------|-------------|--------|
| 1 | **System Resources** | CPU usage, load average, memory, disk partitions, uptime | Done |
| 2 | **Process & Service** | TOP5 CPU/memory processes, sshd/cron health check | Done |
| 3 | **Log Analysis** | syslog `error`/`fail`/`warn` keyword filter & stats | Done |
| 4 | **Network Check** | Public internet ping, local port listening check | Done |
| 5 | **Report Generator** | Consolidated structured text report with anomaly markers | Planned |
| 6 | **Scheduled Task** | crontab daily auto-run + report archival | Done |

---

## Project Structure

```
Linux_server_inspection/
├── scripts/
│   ├── main.sh                # Main entry script
│   ├── system_info.sh         # Module 1: System resource inspection
│   ├── process_check.sh       # Module 2: Process & service monitor
│   ├── log_analysis.sh        # Module 3: Log anomaly analysis
│   ├── network_check.sh       # Module 4: Network connectivity
│   └── cron_setup.sh           # Module 6: Crontab task manager
├── reports/                   # Generated inspection reports
├── logs/                      # Runtime logs
├── README.md
└── 项目规划书.md                # Project plan (Chinese)
```

---

## Usage

### Run a single module

Each module can run independently:

```bash
./scripts/system_info.sh
```

### Run full inspection

```bash
./scripts/main.sh
```

Output is both printed to terminal and saved under `reports/` with timestamp:

```
reports/inspection_20260516_143000.txt
```

### Sample output

```
============================================================
       Linux Server Daily Inspection Report
       Time: 2026-05-16 14:30:00
       Host: raspberrypi
       Kernel: 6.1.0-rpi7-rpi-v8
       Version: v1.0
============================================================

========== CPU & System Load ==========
CPU Usage: 12%
CPU Cores: 4
Load (1/5/15min): 0.35 / 0.42 / 0.38
[OK] Load within normal range

========== Memory Usage ==========
Total: 7.6G   Used: 1.2G   Free: 5.8G   Available: 6.1G
Memory Usage: 15.8%
[OK] Memory usage normal

========== Disk Usage ==========
Mount: /   Filesystem: /dev/mmcblk0p2
  Total: 58G   Used: 22G   Available: 34G   Usage: 40%
[OK] All partitions normal

========== System Uptime ==========
Uptime: up 3 weeks, 2 days, 5 hours
Current: 2026-05-16 14:30:00

============================================================
        Inspection Complete
============================================================
```

---

## Automated Inspection (crontab)

Set up automated daily inspection with one command:

```bash
# Install daily inspection at 8:00 AM (default)
./scripts/cron_setup.sh install

# Or customize the schedule
./scripts/cron_setup.sh install "0 20 * * *"   # 8:00 PM daily
./scripts/cron_setup.sh install "*/30 * * * *"  # Every 30 minutes

# Check status
./scripts/cron_setup.sh status

# Remove scheduled task
./scripts/cron_setup.sh uninstall
```

Reports are automatically saved with timestamps. Check them anytime:

```bash
ls -l reports/
cat reports/latest_report.txt
```

---

## Tech Stack

| Category | Technology |
|----------|------------|
| Main Language | Bash Shell |
| System Commands | `free`, `df`, `ps`, `ss`, `ping`, `uptime` |
| Text Processing | `grep`, `awk`, `sed`, `sort`, `uniq` |
| Scheduling | crontab |
| Version Control | Git |
| Supported OS | Ubuntu, Debian, Raspberry Pi OS |

---

## Development Roadmap

| Version | Content | Week |
|---------|---------|------|
| v0.1 | Project setup, Git init, System resource inspection | Week 1 |
| v0.2 | Process monitor, basic log reading, first integration test | Week 1 |
| v0.3 | Log anomaly stats, network check, structured report | Week 2 |
| v0.4 | Error handling, anomaly markers, report auto-save | Done |
| v0.5 | Crontab config, daily auto-report | Done |
| v1.0 | Full integration, bug fixes, documentation, demo | Week 3 |

---

## Test Plan

- [ ] Functional — CPU/memory/disk data accuracy, service status, log filtering, network
- [ ] Anomaly — high disk alert, SSH down detection, network failure feedback
- [ ] Edge cases — empty logs, extreme CPU load, no listening ports
