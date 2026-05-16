#!/bin/bash
# ============================================
# 模块4：网络连通性检测
# 功能：公网连通性、本地端口监听、DNS 解析、网关状态
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
PING_TARGET="114.114.114.114"     # 国内通用 DNS，连通性测试目标
PING_COUNT=3
DNS_TEST_DOMAIN="baidu.com"

# ---------- 异常标记 ----------
NET_ANOMALY_FOUND=0

# ---------- 公网连通性检测 ----------
check_internet() {
    echo "========== 公网连通性 =========="

    # 检查 ping 命令是否可用
    if ! command -v ping &>/dev/null; then
        echo -e "${YELLOW}[警告] ping 命令不可用，尝试其他连通性检测方式${NC}"
        # 改用 curl 或 wget 测试
        if command -v curl &>/dev/null; then
            if curl -s --connect-timeout 5 -o /dev/null "http://${PING_TARGET}" 2>/dev/null; then
                echo -e "${GREEN}[正常] HTTP 连通性正常（ping不可用，curl 替代）${NC}"
            else
                echo -e "${RED}[异常] HTTP 连通性测试失败${NC}"
                NET_ANOMALY_FOUND=1
            fi
        elif command -v wget &>/dev/null; then
            if wget -q --timeout=5 -O /dev/null "http://${PING_TARGET}" 2>/dev/null; then
                echo -e "${GREEN}[正常] HTTP 连通性正常（ping不可用，wget 替代）${NC}"
            else
                echo -e "${RED}[异常] HTTP 连通性测试失败${NC}"
                NET_ANOMALY_FOUND=1
            fi
        else
            echo -e "${RED}[错误] 所有连通性检测工具（ping/curl/wget）均不可用${NC}"
            NET_ANOMALY_FOUND=1
        fi
        echo ""
        return
    fi

    # ping 测试（兼容无 -oP 的 grep）
    local ping_result
    if ping_result=$(ping -c "$PING_COUNT" -W 3 "$PING_TARGET" 2>&1); then
        # grep -oP 在 BusyBox/macOS 上不可用，使用兼容方式解析
        local loss
        loss=$(echo "$ping_result" | grep -o '[0-9]*% packet loss' | grep -o '[0-9]*' || echo "0")
        local avg_rtt
        avg_rtt=$(echo "$ping_result" | grep -o 'avg = [0-9]*\.[0-9]*' | grep -o '[0-9]*\.[0-9]*' | tail -1 || echo "")
        if [[ -z "$avg_rtt" ]]; then
            avg_rtt=$(echo "$ping_result" | grep -o 'time=[0-9]*\.[0-9]*' | head -1 | grep -o '[0-9]*\.[0-9]*' || echo "N/A")
        fi

        echo "Ping 目标: ${PING_TARGET}"
        echo "丢包率: ${loss}%"
        echo "平均延迟: ${avg_rtt} ms"

        if [[ $loss -ge 100 ]]; then
            echo -e "${RED}[异常] 公网完全不通，请检查网络连接${NC}"
            NET_ANOMALY_FOUND=1
        elif [[ $loss -gt 0 ]]; then
            echo -e "${YELLOW}[注意] 存在 ${loss}% 丢包${NC}"
        else
            echo -e "${GREEN}[正常] 公网连通性正常${NC}"
        fi
    else
        echo -e "${RED}[异常] Ping 完全失败，公网不可达${NC}"
        echo "Ping 输出: $(echo "$ping_result" | tail -1)"
        NET_ANOMALY_FOUND=1
    fi

    echo ""
}

# ---------- DNS 解析测试 ----------
check_dns() {
    echo "========== DNS 解析 =========="

    local resolved_ip=""

    # 依次尝试 dig → nslookup → host
    if command -v dig &>/dev/null; then
        resolved_ip=$(dig +short "$DNS_TEST_DOMAIN" 2>/dev/null | head -1)
    elif command -v nslookup &>/dev/null; then
        local dns_result
        dns_result=$(nslookup "$DNS_TEST_DOMAIN" 2>&1)
        resolved_ip=$(echo "$dns_result" | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
    elif command -v host &>/dev/null; then
        resolved_ip=$(host "$DNS_TEST_DOMAIN" 2>/dev/null | grep "has address" | awk '{print $NF}' | head -1)
    else
        echo -e "${YELLOW}[警告] DNS 解析工具（dig/nslookup/host）均不可用${NC}"
        echo ""; return
    fi

    echo "DNS 测试域名: ${DNS_TEST_DOMAIN}"
    if [[ -n "$resolved_ip" ]]; then
        echo "解析结果: ${resolved_ip}"
        echo -e "${GREEN}[正常] DNS 解析正常${NC}"
    else
        echo -e "${RED}[异常] DNS 解析失败${NC}"
        NET_ANOMALY_FOUND=1
    fi

    echo ""
}

# ---------- 本地端口监听 ----------
check_listening_ports() {
    echo "========== 本地监听端口 =========="

    local port_count=0

    if command -v ss &>/dev/null; then
        echo ""
        echo "协议  本地地址:端口           进程"
        echo "----------------------------------------------"
        local ss_data
        ss_data=$(ss -tlnp 2>/dev/null | grep "LISTEN" || true)
        while read -r line; do
            [[ -z "$line" ]] && continue
            port_count=$((port_count + 1))
            local proto=$(echo "$line" | awk '{print $1}')
            local addr=$(echo "$line" | awk '{print $4}')
            local proc=$(echo "$line" | awk '{for(i=5;i<=NF;i++){if($i ~ /users:/){print $(i+1); exit}}}' | sed 's/[",]//g')
            printf "%-6s %-24s %s\n" "$proto" "$addr" "${proc:-(权限不足未显示)}"
        done <<< "$ss_data"
    elif command -v netstat &>/dev/null; then
        echo -e "${YELLOW}[信息] ss 不可用，使用 netstat 替代${NC}"
        echo ""
        echo "协议  本地地址:端口           进程"
        echo "--------------------------------"
        local ns_data
        ns_data=$(netstat -tlnp 2>/dev/null | grep "LISTEN" || true)
        while read -r line; do
            [[ -z "$line" ]] && continue
            port_count=$((port_count + 1))
            local proto=$(echo "$line" | awk '{print $1}')
            local addr=$(echo "$line" | awk '{print $4}')
            local proc=$(echo "$line" | awk '{print $7}')
            printf "%-6s %-24s %s\n" "$proto" "$addr" "${proc:-(权限不足未显示)}"
        done <<< "$ns_data"
    else
        echo "(无法检测监听端口：ss 和 netstat 均不可用)"
        echo ""
        return
    fi

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
            NET_ANOMALY_FOUND=1
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

    local ip_data
    ip_data=$(ip -brief addr show 2>/dev/null || true)
    while read -r line; do
        [[ -z "$line" ]] && continue
        local iface=$(echo "$line" | awk '{print $1}')
        local state=$(echo "$line" | awk '{print $2}')
        local ip_addr=$(echo "$line" | awk '{print $3}')
        [[ "$iface" == "lo" ]] && continue
        if [[ "$state" == "UP" ]]; then
            echo -e "  ${GREEN}${iface}${NC}: ${state}  IP: ${ip_addr:-无}"
        else
            echo -e "  ${YELLOW}${iface}${NC}: ${state}"
        fi
    done <<< "$ip_data"

    echo ""
}

# ---------- 执行全部巡检 ----------
run_network_check() {
    NET_ANOMALY_FOUND=0
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

    if [[ $NET_ANOMALY_FOUND -eq 1 ]]; then
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
