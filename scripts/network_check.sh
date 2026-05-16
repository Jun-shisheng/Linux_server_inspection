#!/bin/bash
# ============================================
# 模块4：网络连通性检测
# 功能：公网连通性、本地端口监听、DNS 解析、网关状态
# ============================================

set -euo pipefail

# ---------- 颜色定义 ----------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# ---------- 配置 ----------
PING_TARGET="114.114.114.114"     # 国内通用 DNS，连通性测试目标
PING_COUNT=3
DNS_TEST_DOMAIN="baidu.com"

# ---------- 异常标记 ----------
ANOMALY_FOUND=0

# ---------- 公网连通性检测 ----------
check_internet() {
    echo "========== 公网连通性 =========="

    # ping 测试
    local ping_result
    if ping_result=$(ping -c "$PING_COUNT" -W 3 "$PING_TARGET" 2>&1); then
        local loss
        loss=$(echo "$ping_result" | grep -oP '\d+(?=% packet loss)' || echo "0")
        local avg_rtt
        avg_rtt=$(echo "$ping_result" | grep -oP '[\d.]+(?=/\d+\.\d+/\d+\.\d+ ms)' | tail -1 || echo "N/A")

        echo "Ping 目标: ${PING_TARGET}"
        echo "丢包率: ${loss}%"
        echo "平均延迟: ${avg_rtt} ms"

        if [[ $loss -ge 100 ]]; then
            echo -e "${RED}[异常] 公网完全不通，请检查网络连接${NC}"
            ANOMALY_FOUND=1
        elif [[ $loss -gt 0 ]]; then
            echo -e "${YELLOW}[注意] 存在 ${loss}% 丢包${NC}"
        else
            echo -e "${GREEN}[正常] 公网连通性正常${NC}"
        fi
    else
        echo -e "${RED}[异常] Ping 完全失败，公网不可达${NC}"
        ANOMALY_FOUND=1
    fi

    echo ""
}

# ---------- DNS 解析测试 ----------
check_dns() {
    echo "========== DNS 解析 =========="

    local dns_result
    if dns_result=$(nslookup "$DNS_TEST_DOMAIN" 2>&1); then
        local ip
        ip=$(echo "$dns_result" | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
        echo "DNS 测试域名: ${DNS_TEST_DOMAIN}"
        echo "解析结果: ${ip:-N/A}"
        echo -e "${GREEN}[正常] DNS 解析正常${NC}"
    else
        echo -e "${RED}[异常] DNS 解析失败${NC}"
        ANOMALY_FOUND=1
    fi

    echo ""
}

# ---------- 本地端口监听 ----------
check_listening_ports() {
    echo "========== 本地监听端口 =========="

    if ! command -v ss &>/dev/null; then
        echo -e "${YELLOW}[警告] ss 命令不可用，尝试 netstat${NC}"
        if command -v netstat &>/dev/null; then
            echo ""
            echo "协议  本地地址:端口           状态"
            echo "--------------------------------"
            netstat -tlnp 2>/dev/null | grep "LISTEN" | awk '{printf "%-6s %-24s %s\n", $1, $4, $6}' || echo "(无监听端口)"
        else
            echo "(无法检测监听端口)"
            echo ""
            return
        fi
    else
        echo ""
        echo "协议  本地地址:端口           进程"
        echo "----------------------------------------------"
        ss -tlnp 2>/dev/null | grep "LISTEN" | while read -r line; do
            local proto=$(echo "$line" | awk '{print $1}')
            local addr=$(echo "$line" | awk '{print $4}')
            local proc=$(echo "$line" | awk '{for(i=5;i<=NF;i++){if($i ~ /users:/){print $(i+1); exit}}}' | sed 's/[",]//g')
            printf "%-6s %-24s %s\n" "$proto" "$addr" "${proc:-(权限不足未显示)}"
        done
    fi

    local port_count
    port_count=$(ss -tlnp 2>/dev/null | grep -c "LISTEN" || echo 0)
    echo ""
    echo "监听端口总数: ${port_count}"

    if [[ $port_count -eq 0 ]]; then
        echo -e "${YELLOW}[注意] 无 TCP 监听端口${NC}"
    else
        echo -e "${GREEN}[正常] 共 ${port_count} 个端口在监听${NC}"
    fi

    echo ""
}

# ---------- 默认网关 ----------
check_gateway() {
    echo "========== 默认网关 =========="

    local gateway

    # 尝试多种方式获取默认网关
    if command -v ip &>/dev/null; then
        gateway=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
    elif command -v route &>/dev/null; then
        gateway=$(route -n 2>/dev/null | awk '$1=="0.0.0.0" {print $2; exit}')
    elif command -v netstat &>/dev/null; then
        gateway=$(netstat -rn 2>/dev/null | awk '$1=="0.0.0.0" {print $2; exit}')
    fi

    if [[ -n "$gateway" ]]; then
        echo "默认网关: ${gateway}"

        # 测试网关连通性
        if ping -c 1 -W 2 "$gateway" &>/dev/null; then
            echo -e "${GREEN}[正常] 网关可达${NC}"
        else
            echo -e "${RED}[异常] 网关不可达${NC}"
            ANOMALY_FOUND=1
        fi
    else
        echo -e "${YELLOW}[警告] 未配置默认网关或无法获取网关信息${NC}"
    fi

    echo ""
}

# ---------- 网卡状态 ----------
check_interfaces() {
    echo "========== 网卡状态 =========="
    echo ""

    if ! command -v ip &>/dev/null; then
        echo -e "${YELLOW}[警告] ip 命令不可用，跳过网卡状态检测${NC}"
        echo ""; return
    fi

    ip -brief addr show 2>/dev/null | while read -r line; do
        local iface=$(echo "$line" | awk '{print $1}')
        local state=$(echo "$line" | awk '{print $2}')
        local ip_addr=$(echo "$line" | awk '{print $3}')

        # 跳过 lo
        if [[ "$iface" == "lo" ]]; then
            continue
        fi

        if [[ "$state" == "UP" ]]; then
            echo -e "  ${GREEN}${iface}${NC}: ${state}  IP: ${ip_addr:-无}"
        else
            echo -e "  ${YELLOW}${iface}${NC}: ${state}"
        fi
    done

    echo ""
}

# ---------- 执行全部巡检 ----------
run_network_check() {
    echo ""
    echo "########################################################"
    echo "#              网络连通性检测报告                        #"
    echo "#              巡检时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "########################################################"
    echo ""

    check_internet
    check_dns
    check_gateway
    check_interfaces
    check_listening_ports

    if [[ $ANOMALY_FOUND -eq 1 ]]; then
        echo -e "${RED}=============================================${NC}"
        echo -e "${RED}  警告：网络检测发现异常！${NC}"
        echo -e "${RED}=============================================${NC}"
    else
        echo -e "${GREEN}=============================================${NC}"
        echo -e "${GREEN}  网络连通性检测全部正常${NC}"
        echo -e "${GREEN}=============================================${NC}"
    fi

    echo ""
}

# 如果直接执行脚本，则运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_network_check
fi
