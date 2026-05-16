#!/bin/bash
# ============================================
# 模块6：定时自动巡检（crontab 配置管理）
# 功能：安装/卸载/查看定时巡检任务，支持自定义执行频率
# ============================================

set -euo pipefail

# ---------- 路径配置 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/main.sh"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ---------- 颜色定义 ----------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# 默认配置
DEFAULT_SCHEDULE="0 8 * * *"        # 每天早上 8:00
CRON_MARKER="# rtk-inspection-cron"  # 用于识别本工具添加的任务

# ---------- 环境检查 ----------
check_prerequisites() {
    local errors=0

    if ! command -v crontab &>/dev/null; then
        echo -e "${RED}[错误] crontab 命令不可用，请安装 cron 服务${NC}"
        errors=1
    fi

    if [[ ! -f "$MAIN_SCRIPT" ]]; then
        echo -e "${RED}[错误] 未找到主脚本: ${MAIN_SCRIPT}${NC}"
        errors=1
    fi

    # 检查 cron 服务状态
    if command -v systemctl &>/dev/null; then
        if ! systemctl is-active --quiet cron 2>/dev/null && \
           ! systemctl is-active --quiet crond 2>/dev/null; then
            echo -e "${YELLOW}[警告] cron 服务未运行，定时任务可能不会执行${NC}"
        fi
    fi

    return $errors
}

# ---------- 显示当前状态 ----------
show_status() {
    echo "========== 定时巡检状态 =========="
    echo ""

    check_prerequisites || true

    echo "主脚本路径: ${MAIN_SCRIPT}"
    echo ""

    # 检查是否已配置
    local existing
    existing=$(crontab -l 2>/dev/null | grep "$CRON_MARKER" || true)

    if [[ -n "$existing" ]]; then
        echo -e "${GREEN}定时巡检已配置${NC}"
        echo ""
        echo "当前配置:"
        echo "$existing" | while read -r line; do
            # 提取 cron 表达式和执行命令
            local schedule=$(echo "$line" | awk '{print $1" "$2" "$3" "$4" "$5}')
            echo "  执行计划: ${schedule}"
        done
    else
        echo -e "${YELLOW}定时巡检未配置${NC}"
        echo ""
        echo "运行以下命令安装定时任务:"
        echo "  $0 install"
    fi

    echo ""
}

# ---------- 安装定时任务 ----------
install_cron() {
    echo "========== 安装定时巡检任务 =========="
    echo ""

    check_prerequisites

    local schedule="${1:-$DEFAULT_SCHEDULE}"

    # 检查是否已安装
    if crontab -l 2>/dev/null | grep -q "$CRON_MARKER"; then
        echo -e "${YELLOW}定时巡检任务已存在，将先移除旧配置${NC}"
        uninstall_cron_quiet
    fi

    # 构建 cron 条目
    # crontab 环境变量 PATH 可能不包含用户的路径，使用绝对路径
    local cron_entry="${schedule} /bin/bash ${MAIN_SCRIPT} ${CRON_MARKER}"

    # 添加到 crontab
    local temp_cron
    temp_cron=$(mktemp)
    crontab -l 2>/dev/null > "$temp_cron" || true

    # 添加注释说明
    echo "" >> "$temp_cron"
    echo "# Linux Server Inspection Tool - 每日自动巡检 ${CRON_MARKER}" >> "$temp_cron"
    echo "${cron_entry}" >> "$temp_cron"

    if crontab "$temp_cron" 2>/dev/null; then
        rm -f "$temp_cron"
        echo -e "${GREEN}定时巡检任务安装成功${NC}"
        echo ""
        echo "执行计划: ${schedule}"
        echo "对应含义: $(translate_schedule "$schedule")"
        echo "执行脚本: ${MAIN_SCRIPT}"
        echo "报告目录: ${PROJECT_DIR}/reports/"
        echo ""
        echo "查看状态: $0 status"
        echo "查看日志: ${PROJECT_DIR}/logs/"
    else
        rm -f "$temp_cron"
        echo -e "${RED}[错误] crontab 写入失败${NC}"
        return 1
    fi

    echo ""
}

# 静默卸载（供 install 内部调用）
uninstall_cron_quiet() {
    local temp_cron
    temp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" > "$temp_cron" || true
    crontab "$temp_cron" 2>/dev/null || true
    rm -f "$temp_cron"
}

# ---------- 卸载定时任务 ----------
uninstall_cron() {
    echo "========== 卸载定时巡检任务 =========="
    echo ""

    local existing
    existing=$(crontab -l 2>/dev/null | grep "$CRON_MARKER" || true)

    if [[ -z "$existing" ]]; then
        echo -e "${YELLOW}未找到定时巡检任务，无需卸载${NC}"
        echo ""
        return
    fi

    uninstall_cron_quiet

    # 验证卸载结果
    if crontab -l 2>/dev/null | grep -q "$CRON_MARKER"; then
        echo -e "${RED}[错误] 卸载失败，请手动编辑 crontab -e${NC}"
    else
        echo -e "${GREEN}定时巡检任务已卸载${NC}"
    fi

    echo ""
}

# ---------- 列出当前 crontab ----------
list_cron() {
    echo "========== 当前 crontab 配置 =========="
    echo ""

    local cron_content
    cron_content=$(crontab -l 2>/dev/null || true)

    if [[ -z "$cron_content" ]]; then
        echo "(空 — 无任何定时任务)"
    else
        echo "$cron_content"
    fi

    echo ""
}

# ---------- Cron 表达式翻译 ----------
translate_schedule() {
    local s="$1"
    local minute=$(echo "$s" | awk '{print $1}')
    local hour=$(echo "$s" | awk '{print $2}')
    local dom=$(echo "$s" | awk '{print $3}')
    local month=$(echo "$s" | awk '{print $4}')
    local dow=$(echo "$s" | awk '{print $5}')

    local desc=""

    # 分钟
    if [[ "$minute" == "0" ]]; then
        desc="整点"
    elif [[ "$minute" == "30" ]]; then
        desc="半点"
    else
        desc="${minute}分"
    fi

    # 小时
    if [[ "$hour" != "*" ]] && [[ "$hour" =~ ^[0-9]+$ ]]; then
        desc="每天 ${hour}:${minute}"
    else
        desc="每小时${desc}"
    fi

    # 星期
    case "$dow" in
        "1-5") desc="${desc}，工作日" ;;
        "0,6") desc="${desc}，周末" ;;
        "*") ;;
        *) desc="${desc}，星期${dow}" ;;
    esac

    echo "$desc"
}

# ---------- 帮助信息 ----------
show_help() {
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  install [cron表达式]   安装定时巡检任务（默认: ${DEFAULT_SCHEDULE}）"
    echo "  uninstall              卸载定时巡检任务"
    echo "  status                 查看定时巡检状态"
    echo "  list                   列出所有 crontab 任务"
    echo "  help                   显示此帮助"
    echo ""
    echo "示例:"
    echo "  $0 install                   # 每天 8:00 执行"
    echo "  $0 install \"0 20 * * *\"      # 每天 20:00 执行"
    echo "  $0 install \"*/30 * * * *\"    # 每 30 分钟执行"
    echo "  $0 status                    # 查看配置状态"
    echo "  $0 uninstall                 # 移除定时任务"
    echo ""
    echo "Cron 表达式格式: 分 时 日 月 星期"
}

# ---------- 主入口 ----------
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        install)
            install_cron "${2:-}"
            ;;
        uninstall)
            uninstall_cron
            ;;
        status)
            show_status
            list_cron
            ;;
        list)
            list_cron
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}未知命令: ${cmd}${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
