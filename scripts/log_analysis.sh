#!/bin/bash
# ============================================
# 模块3：日志异常分析
# 功能：读取 syslog，过滤异常关键词，统计高频错误
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

# ---------- 配置 ----------
SYSLOG_PATH="/var/log/syslog"
MAX_LINES=5000               # 最大读取行数，避免超大文件拖慢脚本
ERROR_KEYWORDS=("error" "fail" "warn" "critical" "emergency" "panic" "segfault" "oom")

# ---------- 异常标记 ----------
LOG_ANOMALY_FOUND=0

# ---------- 日志异常过滤 ----------
check_log_anomalies() {
    echo "========== 日志异常分析 =========="

    # 检查 syslog 是否存在
    if [[ ! -f "$SYSLOG_PATH" ]]; then
        echo -e "${YELLOW}[警告] 未找到 ${SYSLOG_PATH}，可能非 Debian/Ubuntu 系统${NC}"
        echo "提示：可尝试检查以下日志文件："
        for alt_log in /var/log/messages /var/log/syslog; do
            [[ -f "$alt_log" ]] && echo "  存在: ${alt_log}"
        done
        echo ""
        return
    fi

    # 检查是否可读
    if [[ ! -r "$SYSLOG_PATH" ]]; then
        echo -e "${RED}[错误] 无权限读取 ${SYSLOG_PATH}${NC}"
        echo ""
        return
    fi

    local log_size line_count
    log_size=$(du -h "$SYSLOG_PATH" | awk '{print $1}')
    line_count=$(wc -l < "$SYSLOG_PATH")
    echo "日志文件: ${SYSLOG_PATH}"
    echo "文件大小: ${log_size}  |  总行数: ${line_count}"
    echo ""

    # ---------- 关键词匹配与统计 ----------
    echo "---------- 异常关键词统计 ----------"
    echo ""

    local total_matches=0
    local tail_lines=$MAX_LINES
    if [[ $line_count -lt $MAX_LINES ]]; then
        tail_lines=$line_count
    else
        echo "(分析最近 ${MAX_LINES} 行)"
    fi

    # 优化：一次读取 + awk 多关键词扫描，避免对每个关键词跑一次 tail|grep
    local log_sample
    log_sample=$(tail -n "$tail_lines" "$SYSLOG_PATH" 2>/dev/null)

    for keyword in "${ERROR_KEYWORDS[@]}"; do
        local count
        count=$(echo "$log_sample" | grep -i -c "$keyword" 2>/dev/null || echo 0)
        total_matches=$((total_matches + count))

        if [[ $count -gt 0 ]]; then
            echo -e "  ${RED}${keyword}${NC}: ${count} 条"
        else
            echo "  ${keyword}: 0 条"
        fi
    done

    echo ""
    echo "异常关键词总命中数: ${total_matches}"

    if [[ $total_matches -gt 100 ]]; then
        echo -e "${RED}[异常] 日志异常条目过多（${total_matches}），建议详细排查${NC}"
        LOG_ANOMALY_FOUND=1
    elif [[ $total_matches -gt 0 ]]; then
        echo -e "${YELLOW}[注意] 存在 ${total_matches} 条异常日志，请关注${NC}"
    else
        echo -e "${GREEN}[正常] 近期日志无异常关键词${NC}"
    fi

    echo ""
}

# ---------- 高频错误展示 ----------
check_top_errors() {
    echo "---------- 高频错误 Top 5 ----------"
    echo ""

    if [[ ! -f "$SYSLOG_PATH" ]] || [[ ! -r "$SYSLOG_PATH" ]]; then
        echo "(无法读取日志文件，跳过)"
        echo ""
        return
    fi

    local line_count
    line_count=$(wc -l < "$SYSLOG_PATH")
    local tail_lines=$MAX_LINES
    if [[ $line_count -lt $MAX_LINES ]]; then
        tail_lines=$line_count
    fi

    # 构建关键词正则
    local pattern
    pattern=$(printf "%s|" "${ERROR_KEYWORDS[@]}")
    pattern=${pattern%|}  # 去掉末尾的 |

    # 提取匹配行，按来源进程统计
    local top_errors
    top_errors=$(tail -n "$tail_lines" "$SYSLOG_PATH" \
        | grep -i -E "$pattern" 2>/dev/null \
        | awk '{
            # 提取进程名（syslog 格式通常是：月 日 时:分:秒 主机名 进程名[PID]: 消息）
            for(i=1;i<=NF;i++) {
                if($i ~ /:$/ && i>4) {
                    proc=$(i>5 ? $5 : "kernel")
                    break
                }
            }
            if(proc=="") proc=$5
            # 截取消息的前60字符
            msg=$0
            if(length(msg)>80) msg=substr(msg,1,80)"..."
            print proc
        }' \
        | sort | uniq -c | sort -rn | head -5)

    if [[ -z "$top_errors" ]]; then
        echo "(无高频错误)"
    else
        echo "次数  来源进程"
        echo "--------------------------------"
        echo "$top_errors"
    fi

    echo ""
}

# ---------- 最近异常日志 ----------
check_recent_errors() {
    echo "---------- 最近 5 条异常日志 ----------"
    echo ""

    if [[ ! -f "$SYSLOG_PATH" ]] || [[ ! -r "$SYSLOG_PATH" ]]; then
        echo "(无法读取日志文件，跳过)"
        echo ""
        return
    fi

    local pattern
    pattern=$(printf "%s|" "${ERROR_KEYWORDS[@]}")
    pattern=${pattern%|}

    local recent
    recent=$(tail -n "$MAX_LINES" "$SYSLOG_PATH" \
        | grep -i -E "$pattern" 2>/dev/null \
        | tail -5)

    if [[ -z "$recent" ]]; then
        echo "(无最近异常)"
    else
        echo "$recent" | while read -r line; do
            # 截取关键内容
            if [[ ${#line} -gt 120 ]]; then
                echo "${line:0:120}..."
            else
                echo "$line"
            fi
        done
    fi

    echo ""
}

# ---------- 执行全部巡检 ----------
run_log_analysis() {
    LOG_ANOMALY_FOUND=0
    echo ""
    echo "########################################################"
    echo "#              日志异常分析报告                          #"
    echo "#              巡检时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "########################################################"
    echo ""

    check_log_anomalies
    check_top_errors
    check_recent_errors

    if [[ $LOG_ANOMALY_FOUND -eq 1 ]]; then
        echo -e "${RED}=============================================${NC}"
        echo -e "${RED}  警告：日志异常分析发现问题！${NC}"
        echo -e "${RED}=============================================${NC}"
    else
        echo -e "${GREEN}=============================================${NC}"
        echo -e "${GREEN}  日志异常分析完成${NC}"
        echo -e "${GREEN}=============================================${NC}"
    fi

    echo ""
}

# 如果直接执行脚本，则运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_log_analysis
fi
