#!/bin/bash
# ============================================
# Linux 服务器日常巡检自动化工具 — 主入口脚本
# 版本：v0.3
# 功能：一键调用所有巡检模块，生成结构化巡检报告
# ============================================

set -euo pipefail

# ---------- 路径配置 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REPORT_DIR="${PROJECT_DIR}/reports"
LOG_DIR="${PROJECT_DIR}/logs"

# ---------- 初始化 ----------
mkdir -p "$REPORT_DIR" "$LOG_DIR"

REPORT_FILE="${REPORT_DIR}/inspection_$(date '+%Y%m%d_%H%M%S').txt"
LOG_FILE="${LOG_DIR}/main_$(date '+%Y%m%d').log"

# ---------- 日志函数 ----------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# ---------- 颜色定义 ----------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# ---------- 加载模块 ----------
log "========== 开始巡检 =========="
log "加载巡检模块..."

# 模块1
if [[ -f "${SCRIPT_DIR}/system_info.sh" ]]; then
    source "${SCRIPT_DIR}/system_info.sh"
    log "已加载: 系统资源巡检模块"
else
    log "警告: 未找到 system_info.sh"
fi

# 模块2
if [[ -f "${SCRIPT_DIR}/process_check.sh" ]]; then
    source "${SCRIPT_DIR}/process_check.sh"
    log "已加载: 进程与服务监控模块"
else
    log "警告: 未找到 process_check.sh"
fi

# 模块3
if [[ -f "${SCRIPT_DIR}/log_analysis.sh" ]]; then
    source "${SCRIPT_DIR}/log_analysis.sh"
    log "已加载: 日志异常分析模块"
else
    log "警告: 未找到 log_analysis.sh"
fi

# 模块4
if [[ -f "${SCRIPT_DIR}/network_check.sh" ]]; then
    source "${SCRIPT_DIR}/network_check.sh"
    log "已加载: 网络连通性检测模块"
else
    log "警告: 未找到 network_check.sh"
fi

log "模块加载完成，开始执行巡检..."

# ---------- 报告头部 ----------
generate_header() {
    echo "============================================================"
    echo "       Linux 服务器日常巡检报告"
    echo "       ========================"
    echo "       生成时间 : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "       主机名称 : $(hostname)"
    echo "       内核版本 : $(uname -r)"
    echo "       运行用户 : $(whoami)"
    echo "       工具版本 : v0.3"
    echo "============================================================"
    echo ""
}

# ---------- 异常汇总 ----------
generate_summary() {
    local report_data="$1"

    echo ""
    echo "############################################################"
    echo "#                    巡检异常汇总                            #"
    echo "############################################################"
    echo ""

    # 提取所有 [异常] 标记行
    local anomaly_lines
    anomaly_lines=$(echo "$report_data" | grep '\[异常\]' || true)

    if [[ -z "$anomaly_lines" ]]; then
        echo "  所有模块巡检结果均正常，未发现异常项。"
    else
        # 统计异常数量
        local anomaly_count
        anomaly_count=$(echo "$anomaly_lines" | wc -l)
        echo "  共发现 ${anomaly_count} 个异常项："
        echo ""
        echo "$anomaly_lines" | while read -r line; do
            echo "  - ${line##*$'\033'[0;31m}"  # 去除 ANSI 前缀，简洁展示
        done
    fi

    echo ""
    echo "------------------------------------------------------------"
    echo "  巡检完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "------------------------------------------------------------"
}

# ---------- 执行巡检 ----------
log "执行巡检模块..."

REPORT_CONTENT=$(
    generate_header

    # 模块1：系统资源巡检
    if declare -f run_system_info &>/dev/null; then
        run_system_info
    else
        echo "[错误] 系统资源巡检模块未加载，跳过"
    fi

    # 模块2：进程与服务监控
    if declare -f run_process_check &>/dev/null; then
        run_process_check
    else
        echo "[错误] 进程与服务监控模块未加载，跳过"
    fi

    # 模块3：日志异常分析
    if declare -f run_log_analysis &>/dev/null; then
        run_log_analysis
    else
        echo "[错误] 日志异常分析模块未加载，跳过"
    fi

    # 模块4：网络连通性检测
    if declare -f run_network_check &>/dev/null; then
        run_network_check
    else
        echo "[错误] 网络连通性检测模块未加载，跳过"
    fi
)

# 生成异常汇总
SUMMARY=$(generate_summary "$REPORT_CONTENT")

# 输出到终端并保存到文件
{
    echo "$REPORT_CONTENT"
    echo "$SUMMARY"
} | tee "$REPORT_FILE"

log "巡检报告已保存至: $REPORT_FILE"
log "========== 巡检结束 =========="

echo ""
echo "报告文件: $REPORT_FILE"
