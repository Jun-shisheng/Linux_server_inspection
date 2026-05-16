#!/bin/bash
# ============================================
# 模块5：安全检测
# 功能：失败登录检查、SUID 文件、开放端口、用户安全状态
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
AUTH_LOG_PATHS=("/var/log/auth.log" "/var/log/secure")
FAILED_LOGIN_THRESHOLD=5
SUID_PATH_LIST=("/usr/bin" "/usr/sbin" "/usr/local/bin" "/usr/local/sbin")

# ---------- 异常标记 ----------
SEC_ANOMALY_FOUND=0

# ---------- 失败登录检测 ----------
check_failed_logins() {
    echo "========== 失败登录检测 =========="

    local auth_log=""
    for p in "${AUTH_LOG_PATHS[@]}"; do
        if [[ -f "$p" ]] && [[ -r "$p" ]]; then
            auth_log="$p"
            break
        fi
    done

    if [[ -z "$auth_log" ]]; then
        echo -e "${YELLOW}[警告] 未找到认证日志文件（auth.log/secure）${NC}"
        echo ""
        return
    fi

    local failed_count
    failed_count=$(grep -c "Failed password" "$auth_log" 2>/dev/null || echo 0)

    echo "认证日志: ${auth_log}"
    echo "失败登录次数（总）: ${failed_count}"

    if [[ $failed_count -gt $FAILED_LOGIN_THRESHOLD ]]; then
        echo -e "${RED}[异常] 失败登录次数过多（${failed_count} 次），可能存在暴力破解${NC}"
        SEC_ANOMALY_FOUND=1

        # 显示 TOP5 失败登录 IP
        echo ""
        echo "失败登录 IP TOP5:"
        grep "Failed password" "$auth_log" 2>/dev/null \
            | grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
            | sort | uniq -c | sort -rn | head -5 \
            | awk '{printf "  %-5s 次  %s\n", $1, $2}'
    else
        echo -e "${GREEN}[正常] 失败登录次数在正常范围内${NC}"
    fi

    echo ""
}

# ---------- 当前登录用户 ----------
check_logged_users() {
    echo "========== 当前登录用户 =========="

    if ! command -v who &>/dev/null; then
        echo -e "${YELLOW}[警告] who 命令不可用${NC}"
        echo ""; return
    fi

    local users
    users=$(who 2>/dev/null)
    if [[ -z "$users" ]]; then
        echo "(除当前会话外无其他登录用户)"
    else
        echo "用户  终端    登录时间        来源IP"
        echo "----------------------------------------------"
        echo "$users" | awk '{printf "%-8s %-8s %-15s %s\n", $1, $2, $3" "$4, $5}'

        local user_count
        user_count=$(echo "$users" | wc -l)
        echo "当前在线用户数: ${user_count}"
    fi

    # 检查是否有 root 远程登录
    if echo "$users" | grep -q "^root.*:"; then
        echo -e "${YELLOW}[注意] root 用户当前正在远程登录${NC}"
    fi

    echo ""
}

# ---------- SUID / SGID 文件检测 ----------
check_suid_files() {
    echo "========== SUID/SGID 文件检测 =========="

    if ! command -v find &>/dev/null; then
        echo -e "${YELLOW}[警告] find 命令不可用${NC}"
        echo ""; return
    fi

    local suid_count=0
    local suid_list=""

    for dir in "${SUID_PATH_LIST[@]}"; do
        if [[ -d "$dir" ]]; then
            local found
            found=$(find "$dir" -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null)
            if [[ -n "$found" ]]; then
                suid_list+="$found"$'\n'
                suid_count=$((suid_count + $(echo "$found" | wc -l)))
            fi
        fi
    done

    echo "SUID/SGID 文件总数: ${suid_count}"
    if [[ $suid_count -gt 0 ]]; then
        echo ""
        echo "文件列表（前 10）:"
        echo "$suid_list" | head -10 | while read -r f; do
            [[ -z "$f" ]] && continue
            local perms
            perms=$(ls -l "$f" 2>/dev/null | awk '{print $1}')
            echo "  ${perms}  ${f}"
        done

        if [[ $suid_count -gt 10 ]]; then
            echo "  ... 及其他 ${suid_count} 个文件"
        fi

        echo -e "${YELLOW}[注意] 发现 ${suid_count} 个 SUID/SGID 文件，请确认均为预期配置${NC}"
    else
        echo -e "${GREEN}[正常] 标准路径下无异常 SUID/SGID 文件${NC}"
    fi

    echo ""
}

# ---------- 检查空密码用户 ----------
check_empty_password_users() {
    echo "========== 用户密码安全 =========="

    if ! command -v awk &>/dev/null || [[ ! -f /etc/shadow ]] || [[ ! -r /etc/shadow ]]; then
        echo -e "${YELLOW}[警告] 无法读取 /etc/shadow（需要 root 权限）${NC}"
        echo ""; return
    fi

    local empty_pwd_users
    empty_pwd_users=$(awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null || true)

    if [[ -n "$empty_pwd_users" ]]; then
        echo -e "${RED}[异常] 以下用户无密码或密码已锁定:${NC}"
        echo "$empty_pwd_users" | sed 's/^/  /'
        SEC_ANOMALY_FOUND=1
    else
        echo -e "${GREEN}[正常] 所有用户均有密码配置${NC}"
    fi

    # 列出所有人类用户（UID >= 1000）
    if command -v getent &>/dev/null; then
        local normal_users
        normal_users=$(getent passwd 2>/dev/null | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' | sort)
        echo ""
        echo "普通用户列表:"
        echo "$normal_users" | sed 's/^/  /'
    fi

    echo ""
}

# ---------- 检查世界可写文件 ----------
check_world_writable() {
    echo "========== 关键目录写权限检查 =========="

    local check_dirs=("/etc" "/bin" "/sbin" "/usr/bin" "/usr/sbin")
    local found_issues=0

    for dir in "${check_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local ww_count
            ww_count=$(find "$dir" -type f -perm -o=w 2>/dev/null | wc -l)
            if [[ $ww_count -gt 0 ]]; then
                echo -e "${RED}[异常] ${dir} 下有 ${ww_count} 个世界可写文件${NC}"
                found_issues=1
                SEC_ANOMALY_FOUND=1
            fi
        fi
    done

    if [[ $found_issues -eq 0 ]]; then
        echo -e "${GREEN}[正常] 关键目录下无世界可写文件${NC}"
    fi

    echo ""
}

# ---------- 最近 sudo 日志 ----------
check_sudo_log() {
    echo "========== 最近 sudo 使用记录 =========="

    local sudo_log="/var/log/auth.log"
    if [[ ! -f "$sudo_log" ]] || [[ ! -r "$sudo_log" ]]; then
        sudo_log="/var/log/secure"
    fi

    if [[ -f "$sudo_log" ]] && [[ -r "$sudo_log" ]]; then
        local sudo_entries
        sudo_entries=$(grep -a "sudo:" "$sudo_log" 2>/dev/null | tail -5)
        if [[ -n "$sudo_entries" ]]; then
            echo "最近 5 条 sudo 记录:"
            echo "$sudo_entries" | while read -r line; do
                local clean_line
                clean_line=$(echo "$line" | awk '{
                    # 提取关键字段
                    user=""; cmd=""
                    for(i=1;i<=NF;i++){
                        if($i ~ /^USER=/){user=substr($i,6)}
                        if($i ~ /^COMMAND=/){cmd=substr($i,9)}
                    }
                    if(user!="" || cmd!=""){
                        printf "  用户: %-12s 命令: %s\n", user, cmd
                    }else{
                        print "  " $0
                    }
                }')
                echo "$clean_line"
            done
        else
            echo "(无 sudo 使用记录)"
        fi
    else
        echo -e "${YELLOW}[警告] 无法读取认证日志${NC}"
    fi

    echo ""
}

# ---------- 执行全部安检 ----------
run_security_check() {
    SEC_ANOMALY_FOUND=0
    echo ""
    echo "########################################################"
    echo "#              安全检测报告                              #"
    echo "#              巡检时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "########################################################"
    echo ""

    check_failed_logins
    check_logged_users
    check_suid_files
    check_empty_password_users
    check_world_writable
    check_sudo_log

    if [[ $SEC_ANOMALY_FOUND -eq 1 ]]; then
        echo -e "${RED}=============================================${NC}"
        echo -e "${RED}  警告：安全检测发现异常，请及时处理！${NC}"
        echo -e "${RED}=============================================${NC}"
    else
        echo -e "${GREEN}=============================================${NC}"
        echo -e "${GREEN}  安全检测全部正常${NC}"
        echo -e "${GREEN}=============================================${NC}"
    fi

    echo ""
}

# 如果直接执行脚本，则运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_security_check
fi
