#!/bin/bash
# ============================================
# 模块1：系统资源巡检
# 功能：CPU使用率、系统负载、内存占用、磁盘使用率、系统运行时间
# ============================================

set -euo pipefail

# ---------- 颜色定义 ----------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# ---------- 阈值定义 ----------
CPU_LOAD_THRESHOLD=2.0        # 单核负载告警阈值
MEM_USAGE_THRESHOLD=80        # 内存使用率告警阈值(%)
DISK_USAGE_THRESHOLD=80       # 磁盘使用率告警阈值(%)

# ---------- 异常标记 ----------
SYS_ANOMALY_FOUND=0

# ---------- CPU 使用率与系统负载 ----------
check_cpu() {
    echo "========== CPU 与系统负载 =========="

    # 检查 /proc 文件系统
    if [[ ! -f /proc/stat ]]; then
        echo -e "${YELLOW}[警告] /proc/stat 不可用，无法检测 CPU 使用率${NC}"
        echo ""; return
    fi

    # CPU 使用率（通过 /proc/stat 计算）
    local cpu_line
    cpu_line=$(grep '^cpu ' /proc/stat)
    local cpu_values=($cpu_line)
    # cpu_values[1]=user, [2]=nice, [3]=system, [4]=idle, [5]=iowait, [6]=irq, [7]=softirq, [8]=steal
    local total=0
    local idle=${cpu_values[4]}
    for ((i=1; i<${#cpu_values[@]}; i++)); do
        total=$((total + cpu_values[i]))
    done

    # 短暂等待后再次采样，计算实际使用率
    sleep 0.5
    cpu_line=$(grep '^cpu ' /proc/stat)
    cpu_values=($cpu_line)
    local total2=0
    local idle2=${cpu_values[4]}
    for ((i=1; i<${#cpu_values[@]}; i++)); do
        total2=$((total2 + cpu_values[i]))
    done

    local total_diff=$((total2 - total))
    local idle_diff=$((idle2 - idle))
    local cpu_usage=0
    if [[ $total_diff -gt 0 ]]; then
        cpu_usage=$((100 * (total_diff - idle_diff) / total_diff))
    fi

    echo "CPU 使用率: ${cpu_usage}%"

    # 系统负载
    if [[ ! -f /proc/loadavg ]]; then
        echo -e "${YELLOW}[警告] /proc/loadavg 不可用${NC}"
        echo ""; return
    fi
    local loadavg
    loadavg=$(cat /proc/loadavg)
    local load_1min=$(echo "$loadavg" | awk '{print $1}')
    local load_5min=$(echo "$loadavg" | awk '{print $2}')
    local load_15min=$(echo "$loadavg" | awk '{print $3}')
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)

    echo "CPU 核心数: ${cpu_cores}"
    echo "系统负载 (1/5/15分钟): ${load_1min} / ${load_5min} / ${load_15min}"

    # 负载告警判断（负载 / 核心数 超过阈值）
    local load_ratio
    load_ratio=$(awk "BEGIN {printf \"%.2f\", ${load_1min}/${cpu_cores}}")
    if awk "BEGIN {exit !(${load_1min} > ${CPU_LOAD_THRESHOLD} * ${cpu_cores})}"; then
        echo -e "${RED}[异常] 系统负载过高！1分钟负载 ${load_1min}，超过阈值${NC}"
        SYS_ANOMALY_FOUND=1
    else
        echo -e "${GREEN}[正常] 系统负载在合理范围内${NC}"
    fi

    # 运行队列信息
    local running_procs
    running_procs=$(echo "$loadavg" | awk '{print $4}' | cut -d'/' -f2)
    echo "当前运行/总进程数: ${running_procs}"

    echo ""
}

# ---------- 内存占用 ----------
check_memory() {
    echo "========== 内存使用情况 =========="

    local mem_info
    mem_info=$(free -h | grep -E '^Mem:|^Swap:')
    local mem_total mem_used mem_free mem_available mem_percent

    # 解析 free 输出
    mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    mem_free=$(free -h | awk '/^Mem:/ {print $4}')
    mem_available=$(free -h | awk '/^Mem:/ {print $7}')

    echo "内存总量: ${mem_total}"
    echo "已用内存: ${mem_used}"
    echo "空闲内存: ${mem_free}"
    echo "可用内存: ${mem_available}"

    # Swap 信息
    local swap_total swap_used
    swap_total=$(free -h | awk '/^Swap:/ {print $2}')
    swap_used=$(free -h | awk '/^Swap:/ {print $3}')
    echo "Swap 总量: ${swap_total}"
    echo "Swap 已用: ${swap_used}"

    # 使用率计算
    mem_percent=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100}')
    echo "内存使用率: ${mem_percent}%"

    if awk "BEGIN {exit !(${mem_percent} > ${MEM_USAGE_THRESHOLD})}"; then
        echo -e "${RED}[异常] 内存使用率过高！当前 ${mem_percent}%${NC}"
        SYS_ANOMALY_FOUND=1
    else
        echo -e "${GREEN}[正常] 内存使用率正常${NC}"
    fi

    echo ""
}

# ---------- 磁盘分区使用率 ----------
check_disk() {
    echo "========== 磁盘使用情况 =========="

    local typed_df
    typed_df=$(df -h --type ext4 --type xfs --type btrfs --type vfat --type ntfs 2>/dev/null | grep -v '^Filesystem' || true)

    if [[ -n "$typed_df" ]]; then
        while read -r line; do
            local use_percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
            echo "挂载点: $(echo "$line" | awk '{print $6}')"
            echo "  文件系统: $(echo "$line" | awk '{print $1}')"
            echo "  总量: $(echo "$line" | awk '{print $2}')  已用: $(echo "$line" | awk '{print $3}')  可用: $(echo "$line" | awk '{print $4}')  使用率: ${use_percent}%"
            if [[ $use_percent -gt $DISK_USAGE_THRESHOLD ]]; then
                echo -e "  ${RED}[异常] 磁盘使用率过高！当前 ${use_percent}%，超过阈值 ${DISK_USAGE_THRESHOLD}%${NC}"
                SYS_ANOMALY_FOUND=1
            fi
        done <<< "$typed_df"
    else
        echo "(注意：未检测到常见物理文件系统类型，显示所有挂载点)"
        local fallback_df
        fallback_df=$(df -h | grep -vE '^Filesystem|tmpfs|devtmpfs|overlay|squashfs' || true)
        while read -r line; do
            [[ -z "$line" ]] && continue
            local use_percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
            echo "挂载点: $(echo "$line" | awk '{print $6}')"
            echo "  文件系统: $(echo "$line" | awk '{print $1}')"
            echo "  总量: $(echo "$line" | awk '{print $2}')  已用: $(echo "$line" | awk '{print $3}')  可用: $(echo "$line" | awk '{print $4}')  使用率: ${use_percent}%"
            if [[ $use_percent -gt $DISK_USAGE_THRESHOLD ]]; then
                echo -e "  ${RED}[异常] 磁盘使用率过高！当前 ${use_percent}%${NC}"
                SYS_ANOMALY_FOUND=1
            fi
        done <<< "$fallback_df"
    fi

    echo ""
}

# ---------- 系统运行时间 ----------
check_uptime() {
    echo "========== 系统运行时间 =========="

    local uptime_str
    uptime_str=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
    echo "运行时间: ${uptime_str}"

    local current_time
    current_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "当前时间: ${current_time}"

    echo ""
}

# ---------- 执行全部巡检 ----------
run_system_info() {
    SYS_ANOMALY_FOUND=0
    echo ""
    echo "########################################################"
    echo "#              系统资源巡检报告                          #"
    echo "#              巡检时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "########################################################"
    echo ""

    check_cpu
    check_memory
    check_disk
    check_uptime

    if [[ $SYS_ANOMALY_FOUND -eq 1 ]]; then
        echo -e "${RED}=============================================${NC}"
        echo -e "${RED}  警告：系统资源巡检发现异常，请及时处理！${NC}"
        echo -e "${RED}=============================================${NC}"
    else
        echo -e "${GREEN}=============================================${NC}"
        echo -e "${GREEN}  系统资源巡检全部正常${NC}"
        echo -e "${GREEN}=============================================${NC}"
    fi

    echo ""
}

# 如果直接执行脚本（非 source），则运行巡检
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_system_info
fi
