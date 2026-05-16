#!/bin/bash
# ============================================
# 模块2：进程与服务监控
# 功能：TOP5 CPU/内存进程、关键服务检测、异常进程识别
# ============================================

# 被 source 时不重新设置 pipefail（由主脚本统一管理）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

# ---------- 颜色定义 ----------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# ---------- 阈值定义 ----------
CPU_PROCESS_THRESHOLD=80       # 单进程 CPU 告警阈值(%)
MEM_PROCESS_THRESHOLD=50       # 单进程内存告警阈值(%)
KEY_SERVICES=("sshd" "cron")   # 关键服务列表

# ---------- 异常标记 ----------
PROC_ANOMALY_FOUND=0

# ---------- TOP5 CPU 进程 ----------
check_top_cpu_processes() {
    echo "========== TOP5 CPU 进程 =========="

    if ! command -v ps &>/dev/null; then
        echo -e "${YELLOW}[警告] ps 命令不可用${NC}"
        echo ""; return
    fi
    echo ""
    printf "%-8s %-6s %-6s %-25s\n" "PID" "CPU%" "MEM%" "COMMAND"
    echo "-----------------------------------------------"

    local top_cpu_data
    top_cpu_data=$(ps aux --sort=-%cpu | head -6 | tail -5)

    while read -r line; do
        [[ -z "$line" ]] && continue
        local pid=$(echo "$line" | awk '{print $2}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local mem=$(echo "$line" | awk '{print $4}')
        local cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | cut -c1-25)
        printf "%-8s %-6s %-6s %-25s\n" "$pid" "$cpu" "$mem" "$cmd"
        if awk "BEGIN {exit !(${cpu} > ${CPU_PROCESS_THRESHOLD})}" 2>/dev/null; then
            echo -e "  ${RED}[异常] 进程 PID=${pid} CPU 使用率 ${cpu}%，超过阈值${NC}"
            PROC_ANOMALY_FOUND=1
        fi
    done <<< "$top_cpu_data"
    echo ""
}

# ---------- TOP5 内存进程 ----------
check_top_mem_processes() {
    echo "========== TOP5 内存进程 =========="
    echo ""
    printf "%-8s %-6s %-6s %-25s\n" "PID" "CPU%" "MEM%" "COMMAND"
    echo "-----------------------------------------------"

    local top_mem_data
    top_mem_data=$(ps aux --sort=-%mem | head -6 | tail -5)

    while read -r line; do
        [[ -z "$line" ]] && continue
        local pid=$(echo "$line" | awk '{print $2}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local mem=$(echo "$line" | awk '{print $4}')
        local cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | cut -c1-25)
        printf "%-8s %-6s %-6s %-25s\n" "$pid" "$cpu" "$mem" "$cmd"
        if awk "BEGIN {exit !(${mem} > ${MEM_PROCESS_THRESHOLD})}" 2>/dev/null; then
            echo -e "  ${RED}[异常] 进程 PID=${pid} 内存使用率 ${mem}%，超过阈值${NC}"
            PROC_ANOMALY_FOUND=1
        fi
    done <<< "$top_mem_data"
    echo ""
}

# ---------- 进程总数与状态 ----------
check_process_summary() {
    echo "========== 进程状态汇总 =========="

    local total_procs
    total_procs=$(ps aux | wc -l)
    total_procs=$((total_procs - 1))  # 减去表头
    echo "进程总数: ${total_procs}"

    # 僵尸进程检测
    local zombie_count
    zombie_count=$(ps aux | awk '$8 ~ /Z/ {print $2}' | wc -l)
    if [[ $zombie_count -gt 0 ]]; then
        echo -e "${RED}[异常] 发现 ${zombie_count} 个僵尸进程${NC}"
        ps aux | awk '$8 ~ /Z/ {printf "  PID: %-8s CMD: %s\n", $2, $11}'
        PROC_ANOMALY_FOUND=1
    else
        echo -e "${GREEN}[正常] 无僵尸进程${NC}"
    fi

    # CPU / 内存 使用率最高的进程
    local top_cpu_proc
    top_cpu_proc=$(ps aux --sort=-%cpu | head -2 | tail -1 | awk '{printf "PID=%s (%s) CPU=%s%%", $2, $11, $3}')
    echo "CPU 最高进程: ${top_cpu_proc}"

    local top_mem_proc
    top_mem_proc=$(ps aux --sort=-%mem | head -2 | tail -1 | awk '{printf "PID=%s (%s) MEM=%s%%", $2, $11, $4}')
    echo "内存最高进程: ${top_mem_proc}"

    echo ""
}

# ---------- 关键服务检测 ----------
check_key_services() {
    echo "========== 关键服务状态 =========="

    for service in "${KEY_SERVICES[@]}"; do
        local status="未知"

        # 优先使用 systemctl
        if command -v systemctl &>/dev/null; then
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                status="运行中"
                echo -e "  ${GREEN}[正常]${NC} ${service}: ${status}"
            else
                status="已停止"
                echo -e "  ${RED}[异常]${NC} ${service}: ${status}"
                PROC_ANOMALY_FOUND=1
            fi
        # 回退到 service 命令
        elif command -v service &>/dev/null; then
            if service "$service" status &>/dev/null; then
                status="运行中"
                echo -e "  ${GREEN}[正常]${NC} ${service}: ${status}"
            else
                status="已停止或未安装"
                echo -e "  ${YELLOW}[警告]${NC} ${service}: ${status}"
            fi
        # 最后尝试 pgrep
        else
            if pgrep -x "$service" &>/dev/null; then
                status="运行中"
                echo -e "  ${GREEN}[正常]${NC} ${service}: ${status} (pgrep)"
            else
                status="未运行"
                echo -e "  ${YELLOW}[警告]${NC} ${service}: ${status} (pgrep)"
            fi
        fi
    done

    echo ""
}

# ---------- 执行全部巡检 ----------
run_process_check() {
    PROC_ANOMALY_FOUND=0
    echo ""
    echo "########################################################"
    echo "#              进程与服务巡检报告                        #"
    echo "#              巡检时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "########################################################"
    echo ""

    check_top_cpu_processes
    check_top_mem_processes
    check_process_summary
    check_key_services

    if [[ $PROC_ANOMALY_FOUND -eq 1 ]]; then
        echo -e "${RED}=============================================${NC}"
        echo -e "${RED}  警告：进程与服务巡检发现异常！${NC}"
        echo -e "${RED}=============================================${NC}"
    else
        echo -e "${GREEN}=============================================${NC}"
        echo -e "${GREEN}  进程与服务巡检全部正常${NC}"
        echo -e "${GREEN}=============================================${NC}"
    fi

    echo ""
}

# 如果直接执行脚本，则运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_process_check
fi
