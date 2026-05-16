#!/bin/bash
# ============================================
# Linux 服务器日常巡检自动化工具 — 主入口脚本
# 版本：v0.1
# 功能：一键调用所有巡检模块，生成巡检报告
# ============================================

set -euo pipefail

# ---------- 路径配置 ----------
# 获取脚本所在目录的绝对路径（兼容 crontab 环境）
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

# ---------- 加载模块 ----------
log "========== 开始巡检 =========="
log "加载巡检模块..."

# 模块1：系统资源巡检
if [[ -f "${SCRIPT_DIR}/system_info.sh" ]]; then
    source "${SCRIPT_DIR}/system_info.sh"
    log "已加载: 系统资源巡检模块"
else
    log "警告: 未找到 system_info.sh"
fi

# TODO: 后续模块在此加载
# source "${SCRIPT_DIR}/process_check.sh"   # v0.2
# source "${SCRIPT_DIR}/log_analysis.sh"    # v0.3
# source "${SCRIPT_DIR}/network_check.sh"   # v0.3

log "模块加载完成，开始执行巡检..."

# ---------- 执行巡检 ----------
{
    echo "============================================================"
    echo "       Linux 服务器日常巡检报告"
    echo "       生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "       主机名称: $(hostname)"
    echo "       内核版本: $(uname -r)"
    echo "       工具版本: v0.1"
    echo "============================================================"
    echo ""

    # 模块1：系统资源巡检
    if declare -f run_system_info &>/dev/null; then
        run_system_info
    else
        echo "[错误] 系统资源巡检模块未加载，跳过"
    fi

    # TODO: 后续模块在此调用
    # run_process_check   # v0.2
    # run_log_analysis    # v0.3
    # run_network_check   # v0.3

    echo "============================================================"
    echo "       巡检完成 — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================"

} | tee "$REPORT_FILE"

log "巡检报告已保存至: $REPORT_FILE"
log "========== 巡检结束 =========="

# 输出报告路径，方便 crontab 邮件通知
echo ""
echo "报告文件: $REPORT_FILE"
