#!/bin/bash
# ============================================
# Linux 服务器日常巡检自动化工具 — 主入口脚本
# 版本：v0.5
# 功能：一键调用所有巡检模块，生成结构化巡检报告，异常分类汇总
# 用法：./main.sh [--quiet]     # --quiet 适用于 crontab 静默模式
# ============================================

set -euo pipefail

# ---------- 路径配置 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REPORT_DIR="${PROJECT_DIR}/reports"
LOG_DIR="${PROJECT_DIR}/logs"
LATEST_REPORT="${REPORT_DIR}/latest_report.txt"

# ---------- 初始化 ----------
mkdir -p "$REPORT_DIR" "$LOG_DIR"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DATE_STAMP=$(date '+%Y%m%d')
REPORT_FILE="${REPORT_DIR}/inspection_${TIMESTAMP}.txt"
LOG_FILE="${LOG_DIR}/main_${DATE_STAMP}.log"

# ---------- 日志函数 ----------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

# ---------- 运行模式 ----------
QUIET_MODE=0
if [[ "${1:-}" == "--quiet" ]]; then
    QUIET_MODE=1
fi

# ---------- 颜色定义 ----------
if [[ $QUIET_MODE -eq 1 ]]; then
    RED='' YELLOW='' GREEN='' NC=''
else
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    NC='\033[0m'
fi

# ---------- 加载模块 ----------
log "========== 开始巡检 =========="
log "加载巡检模块..."

MODULES_LOADED=0
MODULES_FAILED=0

load_module() {
    local name="$1"
    local file="$2"
    if [[ -f "$file" ]]; then
        source "$file"
        log "已加载: ${name}"
        MODULES_LOADED=$((MODULES_LOADED + 1))
    else
        log "警告: 未找到 ${file##*/}，${name}将跳过"
        MODULES_FAILED=$((MODULES_FAILED + 1))
    fi
}

load_module "系统资源巡检"     "${SCRIPT_DIR}/system_info.sh"
load_module "进程与服务监控"   "${SCRIPT_DIR}/process_check.sh"
load_module "日志异常分析"     "${SCRIPT_DIR}/log_analysis.sh"
load_module "网络连通性检测"   "${SCRIPT_DIR}/network_check.sh"

log "模块加载: 成功 ${MODULES_LOADED} / 失败 ${MODULES_FAILED}"
log "开始执行巡检..."

# ---------- 报告头部 ----------
generate_header() {
    echo "============================================================"
    echo "       Linux 服务器日常巡检报告"
    echo "       ========================"
    echo "       生成时间 : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "       主机名称 : ${HOSTNAME:-$(hostname 2>/dev/null || echo 'unknown')}"
    echo "       内核版本 : $(uname -r 2>/dev/null || echo 'N/A')"
    echo "       运行用户 : ${USER:-$(whoami 2>/dev/null || echo 'unknown')}"
    echo "       工具版本 : v0.5"
    echo "============================================================"
    echo ""
}

# ---------- 按模块分类汇总异常 ----------
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
    local warn_lines
    warn_lines=$(echo "$report_data" | grep '\[警告\]' || true)
    local note_lines
    note_lines=$(echo "$report_data" | grep '\[注意\]' || true)

    local anom_count=0
    [[ -n "$anomaly_lines" ]] && anom_count=$(echo "$anomaly_lines" | wc -l)
    local warn_count=0
    [[ -n "$warn_lines" ]] && warn_count=$(echo "$warn_lines" | wc -l)
    local note_count=0
    [[ -n "$note_lines" ]] && note_count=$(echo "$note_lines" | wc -l)

    echo "  +-----------+-------+"
    echo "  | 级别      | 数量  |"
    echo "  +-----------+-------+"
    printf "  | %-9s | %-5s |\n" "异常" "${anom_count}"
    printf "  | %-9s | %-5s |\n" "警告" "${warn_count}"
    printf "  | %-9s | %-5s |\n" "注意" "${note_count}"
    echo "  +-----------+-------+"

    if [[ $anom_count -eq 0 ]] && [[ $warn_count -eq 0 ]]; then
        echo ""
        echo "  所有模块巡检结果均正常，未发现异常项。"
    else
        echo ""
        echo "  --- 异常明细 ---"
        if [[ -n "$anomaly_lines" ]]; then
            echo ""
            echo "  [异常]"
            echo "$anomaly_lines" | while read -r line; do
                local clean_line
                clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g')
                echo "    - ${clean_line}"
            done
        fi
        if [[ -n "$warn_lines" ]]; then
            echo ""
            echo "  [警告]"
            echo "$warn_lines" | while read -r line; do
                local clean_line
                clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g')
                echo "    - ${clean_line}"
            done
        fi
    fi

    echo ""
    echo "------------------------------------------------------------"
    echo "  巡检完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  报告保存路径: ${REPORT_FILE}"
    echo "  最新报告链接: ${LATEST_REPORT}"
    echo "------------------------------------------------------------"
}

# ---------- 报告清理（保留最近 30 份） ----------
cleanup_old_reports() {
    local max_reports=30
    local report_list
    report_list=$(ls -1t "${REPORT_DIR}"/inspection_*.txt 2>/dev/null || true)

    if [[ -z "$report_list" ]]; then
        return
    fi

    local count
    count=$(echo "$report_list" | wc -l)
    if [[ $count -gt $max_reports ]]; then
        echo "$report_list" | tail -n +$((max_reports + 1)) | while read -r old_report; do
            rm -f "$old_report"
            log "清理旧报告: $(basename "$old_report")"
        done
    fi
}

# ---------- 执行巡检 ----------
log "执行巡检模块..."

REPORT_CONTENT=$(
    generate_header

    # 模块1
    if declare -f run_system_info &>/dev/null; then
        run_system_info
    else
        echo "[错误] 系统资源巡检模块未加载，跳过"
    fi

    # 模块2
    if declare -f run_process_check &>/dev/null; then
        run_process_check
    else
        echo "[错误] 进程与服务监控模块未加载，跳过"
    fi

    # 模块3
    if declare -f run_log_analysis &>/dev/null; then
        run_log_analysis
    else
        echo "[错误] 日志异常分析模块未加载，跳过"
    fi

    # 模块4
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

# 更新最新报告链接
if [[ -L "$LATEST_REPORT" ]] || [[ -f "$LATEST_REPORT" ]]; then
    rm -f "$LATEST_REPORT"
fi
ln -sf "$(basename "$REPORT_FILE")" "$LATEST_REPORT" 2>/dev/null \
    || cp "$REPORT_FILE" "$LATEST_REPORT" 2>/dev/null \
    || true

# 清理旧报告
cleanup_old_reports

log "巡检报告已保存至: $REPORT_FILE"
log "========== 巡检结束 =========="

if [[ $QUIET_MODE -eq 0 ]]; then
    echo ""
    echo "报告文件: $REPORT_FILE"
    echo "最新报告: $LATEST_REPORT"
fi
