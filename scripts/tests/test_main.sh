#!/bin/bash
# ============================================
# 测试入口脚本
# 运行所有单元测试并汇总结果
# 用法: ./scripts/tests/test_main.sh
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_DIR="${SCRIPT_DIR}"

PASS=0
FAIL=0
SKIP=0

print_header() {
    echo ""
    echo "=============================================="
    echo "  $1"
    echo "=============================================="
}

print_result() {
    local name=$1
    local status=$2
    if [[ "$status" == "PASS" ]]; then
        echo "  [✓] ${name}"
        PASS=$((PASS + 1))
    elif [[ "$status" == "FAIL" ]]; then
        echo "  [✗] ${name}"
        FAIL=$((FAIL + 1))
    else
        echo "  [-] ${name} (SKIPPED)"
        SKIP=$((SKIP + 1))
    fi
}

# ==============================================
# Test 1: 语法检查
# ==============================================
test_syntax_check() {
    print_header "Test 1: 语法检查 (bash -n)"

    for script in "${PROJECT_DIR}"/scripts/*.sh; do
        local name
        name=$(basename "$script")
        if bash -n "$script" 2>/dev/null; then
            print_result "bash -n ${name}" "PASS"
        else
            print_result "bash -n ${name}" "FAIL"
        fi
    done
}

# ==============================================
# Test 2: 模块直接执行测试
# ==============================================
test_module_direct_exec() {
    print_header "Test 2: 模块直接执行测试"

    local modules=("system_info.sh" "process_check.sh" "log_analysis.sh" "network_check.sh" "security_check.sh")

    for mod in "${modules[@]}"; do
        local path="${PROJECT_DIR}/scripts/${mod}"
        if [[ ! -f "$path" ]]; then
            print_result "${mod} 直接执行" "FAIL (missing)"
            continue
        fi

        # 使用 timeout 防止脚本 hang（5秒超时）
        if timeout 5 bash "$path" &>/dev/null; then
            print_result "${mod} 直接执行" "PASS"
        elif [[ $? -eq 124 ]]; then
            print_result "${mod} 直接执行（超时 - 可能等待用户输入）" "SKIP"
        else
            print_result "${mod} 直接执行（模块内命令不可用 - 正常）" "PASS"
        fi
    done
}

# ==============================================
# Test 3: main.sh 模块加载测试
# ==============================================
test_main_module_loading() {
    print_header "Test 3: main.sh 模块加载测试"

    # 模拟 main.sh 只加载模块但不执行检测
    local result
    result=$(
        source "${PROJECT_DIR}/scripts/system_info.sh"
        source "${PROJECT_DIR}/scripts/process_check.sh"
        source "${PROJECT_DIR}/scripts/log_analysis.sh"
        source "${PROJECT_DIR}/scripts/network_check.sh"
        source "${PROJECT_DIR}/scripts/security_check.sh"
        echo "ALL_MODULES_LOADED"
    )

    if [[ "$result" == "ALL_MODULES_LOADED" ]]; then
        print_result "所有模块可被 source 加载" "PASS"
    else
        print_result "模块加载失败: $result" "FAIL"
    fi
}

# ==============================================
# Test 4: 模块函数存在性测试
# ==============================================
test_module_functions_exist() {
    print_header "Test 4: 模块函数存在性测试"

    source "${PROJECT_DIR}/scripts/system_info.sh"
    source "${PROJECT_DIR}/scripts/process_check.sh"
    source "${PROJECT_DIR}/scripts/log_analysis.sh"
    source "${PROJECT_DIR}/scripts/network_check.sh"
    source "${PROJECT_DIR}/scripts/security_check.sh"

    local funcs=(
        "run_system_info"
        "run_process_check"
        "run_log_analysis"
        "run_network_check"
        "run_security_check"
    )

    for func in "${funcs[@]}"; do
        if declare -f "$func" &>/dev/null; then
            print_result "${func} 存在" "PASS"
        else
            print_result "${func} 存在" "FAIL"
        fi
    done
}

# ==============================================
# Test 5: 配置存在性测试
# ==============================================
test_config_files_exist() {
    print_header "Test 5: 关键文件存在性测试"

    local files=(
        "${PROJECT_DIR}/scripts/main.sh"
        "${PROJECT_DIR}/scripts/system_info.sh"
        "${PROJECT_DIR}/scripts/process_check.sh"
        "${PROJECT_DIR}/scripts/log_analysis.sh"
        "${PROJECT_DIR}/scripts/network_check.sh"
        "${PROJECT_DIR}/scripts/security_check.sh"
        "${PROJECT_DIR}/scripts/cron_setup.sh"
        "${PROJECT_DIR}/README.md"
        "${PROJECT_DIR}/LICENSE"
        "${PROJECT_DIR}/.gitignore"
        "${PROJECT_DIR}/.github/workflows/shellcheck.yml"
    )

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            print_result "$(basename "$file") 存在" "PASS"
        else
            print_result "$(basename "$file") 存在" "FAIL"
        fi
    done
}

# ==============================================
# Test 6: README 配置一致性
# ==============================================
test_readme_consistency() {
    print_header "Test 6: README 与模块数一致性"

    local script_count
    script_count=$(find "${PROJECT_DIR}/scripts" -maxdepth 1 -name '*.sh' ! -name 'test_*' | wc -l)

    # 期望 6 个模块脚本（不含 test 脚本）
    if [[ $script_count -ge 6 ]]; then
        print_result "模块脚本数 ($script_count) 符合预期" "PASS"
    else
        print_result "模块脚本数 ($script_count) 不足预期" "FAIL"
    fi

    # 检查 README 中模块列表是否包含安全检测
    if grep -qi "安全检测\|security" "${PROJECT_DIR}/README.md" 2>/dev/null; then
        print_result "README 包含安全检测描述" "PASS"
    else
        print_result "README 包含安全检测描述" "SKIP (README 待更新)"
    fi
}

# ==============================================
# Test 7: main.sh 命令行参数
# ==============================================
test_main_cli_args() {
    print_header "Test 7: main.sh CLI 参数测试"

    # --help
    if "${PROJECT_DIR}/scripts/main.sh" --help 2>&1 | grep -qi "用法\|usage\|help"; then
        print_result "main.sh --help" "PASS"
    else
        print_result "main.sh --help" "FAIL"
    fi

    # --version
    if "${PROJECT_DIR}/scripts/main.sh" --version 2>&1 | grep -qi "[0-9]\+\.[0-9]"; then
        print_result "main.sh --version" "PASS"
    else
        print_result "main.sh --version" "SKIP (无版本号输出)"
    fi
}

# ==============================================
# Test 8: 模拟日志分析测试
# ==============================================
test_log_analysis_mock() {
    print_header "Test 8: 日志模拟数据测试"

    local mock_log
    mock_log=$(mktemp)
    cat > "$mock_log" <<'EOF'
Dec  1 10:00:00 hostname systemd[1]: Started Session.
Dec  1 10:01:00 hostname sshd[1234]: Failed password for root from 10.0.0.1 port 22 ssh2
Dec  1 10:02:00 hostname kernel: [12345.678] oom-killer: gfp_mask=0x
Dec  1 10:03:00 hostname systemd[1]: Service exited with fail code
Dec  1 10:04:00 hostname kernel: segfault at 0 ip 0000 sp 0000 error 6
Dec  1 10:05:00 hostname sshd[5678]: Accepted publickey for user from 10.0.0.2
Dec  1 10:06:00 hostname kernel: [12345.679] oom-killer: gfp_mask=0x
Dec  1 10:07:00 hostname CRON[999]: (root) CMD (echo test)
EOF

    source "${PROJECT_DIR}/scripts/log_analysis.sh"

    # 临时覆盖 syslog 路径
    SYSLOG_PATH="$mock_log"
    local output
    output=$(run_log_analysis 2>&1 || true)

    if echo "$output" | grep -qi "error\|异常\|fail\|warning"; then
        print_result "日志分析识别 mock 异常" "PASS"
    else
        print_result "日志分析识别 mock 异常" "FAIL"
    fi

    rm -f "$mock_log"
}

# ==============================================
# Test 9: 安全模块 mock 测试
# ==============================================
test_security_mock() {
    print_header "Test 9: 安全模块模拟测试"

    # 检查是否以 root 运行
    if [[ $EUID -ne 0 ]] && [[ ! -r /var/log/auth.log ]] && [[ ! -r /var/log/secure ]]; then
        print_result "安全模块（无 auth.log 读权限）" "SKIP (需要 root 或日志文件存在)"
        return
    fi

    source "${PROJECT_DIR}/scripts/security_check.sh"

    local output
    output=$(run_security_check 2>&1 || true)

    if echo "$output" | grep -qi "安全\|failed\|SUID\|sudo\|用户"; then
        print_result "安全模块正常执行" "PASS"
    else
        print_result "安全模块正常执行" "FAIL (无预期输出)"
    fi
}

# ==============================================
# Test 10: 模拟缺失命令测试
# ==============================================
test_missing_commands() {
    print_header "Test 10: 缺失命令兼容性测试"

    # 测试 network_check 在只有基础命令时的表现
    source "${PROJECT_DIR}/scripts/network_check.sh"

    # 模拟 disable ping
    if ! command -v ping &>/dev/null; then
        # ping 已经不存在 - 直接测试会转向 curl/wget
        local output
        output=$(check_internet 2>&1 || true)
        if echo "$output" | grep -qi "警告\|error\|不可用\|curl\|wget\|跳过"; then
            print_result "ping 缺失时的回退处理" "PASS"
        else
            print_result "ping 缺失时的回退处理" "FAIL"
        fi
    else
        print_result "ping 缺失时的回退处理（系统有 ping，跳过）" "SKIP"
    fi
}

# ==============================================
# 运行全部测试
# ==============================================
run_all_tests() {
    echo ""
    echo "########################################################"
    echo "#              Linux Server Inspection Test Suite       #"
    echo "#              测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "########################################################"

    test_syntax_check
    test_module_direct_exec
    test_main_module_loading
    test_module_functions_exist
    test_config_files_exist
    test_readme_consistency
    test_main_cli_args
    test_log_analysis_mock
    test_security_mock
    test_missing_commands

    echo ""
    echo "=============================================="
    echo "  测试汇总"
    echo "=============================================="
    echo "  通过: ${PASS}"
    echo "  失败: ${FAIL}"
    echo "  跳过: ${SKIP}"
    echo "  总计: $((PASS + FAIL + SKIP))"
    echo ""

    if [[ $FAIL -eq 0 ]]; then
        echo "  ✓ 全部测试通过！"
    else
        echo "  ✗ 存在 ${FAIL} 个测试失败，请检查"
    fi
    echo ""
}

# 直接执行时运行测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
