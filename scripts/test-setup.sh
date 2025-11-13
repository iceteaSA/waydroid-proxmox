#!/usr/bin/env bash

# Test script to verify Waydroid LXC setup
# Run this inside the LXC container to verify everything is working
#
# Usage: test-setup.sh [OPTIONS]
#   --json          Output results in JSON format for CI/CD
#   --verbose       Enable verbose output with detailed diagnostics
#   --help          Show this help message

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helper-functions.sh"

# Configuration
JSON_OUTPUT=false
VERBOSE=false
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Arrays to store test results
declare -a TEST_RESULTS=()
declare -a TEST_NAMES=()
declare -a TEST_MESSAGES=()
declare -a FIX_SUGGESTIONS=()

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
Waydroid LXC Setup Verification Tool

Usage: $(basename "$0") [OPTIONS]

Options:
  --json          Output results in JSON format for CI/CD integration
  --verbose, -v   Enable verbose output with detailed diagnostics
  --help, -h      Show this help message

Examples:
  $(basename "$0")                    # Run all tests with standard output
  $(basename "$0") --verbose          # Run with detailed diagnostics
  $(basename "$0") --json             # Output in JSON format for CI/CD
  $(basename "$0") --json --verbose   # JSON output with verbose details

Exit Codes:
  0 - All tests passed
  1 - Some tests failed
  2 - Critical failure (e.g., not running in LXC)
EOF
}

# Verbose logging
verbose_log() {
    if $VERBOSE && ! $JSON_OUTPUT; then
        echo -e "${YW}[VERBOSE]${CL} $1"
    fi
}

# Record test result
record_test() {
    local name=$1
    local result=$2  # "pass", "fail", "warn"
    local message=$3
    local fix_suggestion=$4

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TEST_NAMES+=("$name")
    TEST_RESULTS+=("$result")
    TEST_MESSAGES+=("$message")
    FIX_SUGGESTIONS+=("$fix_suggestion")

    case $result in
        pass)
            PASSED_TESTS=$((PASSED_TESTS + 1))
            ;;
        fail)
            FAILED_TESTS=$((FAILED_TESTS + 1))
            ;;
        warn)
            WARNINGS=$((WARNINGS + 1))
            ;;
    esac
}

# Print test header
print_test_header() {
    if ! $JSON_OUTPUT; then
        echo -e "${BL}$1${CL}"
    fi
}

# Print test result
print_test_result() {
    local result=$1
    local message=$2

    if ! $JSON_OUTPUT; then
        case $result in
            pass)
                echo -e "${CM} $message"
                ;;
            fail)
                echo -e "${CROSS} $message"
                ;;
            warn)
                echo -e "${YW}[WARN]${CL} $message"
                ;;
        esac
    fi
}

# Test 1: GPU Device Access
test_gpu_access() {
    print_test_header "Test 1: GPU Device Access"
    local result="pass"
    local message=""
    local fix=""

    verbose_log "Checking /dev/dri/card0..."
    if [ ! -e /dev/dri/card0 ]; then
        result="fail"
        message="GPU device /dev/dri/card0 not found"
        fix="Ensure GPU passthrough is configured in Proxmox LXC config. Add 'lxc.cgroup2.devices.allow: c 226:* rwm' and 'lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir'"
    elif [ ! -r /dev/dri/card0 ] || [ ! -w /dev/dri/card0 ]; then
        result="fail"
        message="No read/write access to /dev/dri/card0"
        fix="Check permissions: chmod 666 /dev/dri/card0 or add user to video/render group: usermod -aG video,render root"
    else
        verbose_log "Checking /dev/dri/renderD128..."
        if [ ! -e /dev/dri/renderD128 ]; then
            result="warn"
            message="GPU device accessible but renderD128 not found"
            fix="Render device may not be critical, but verify GPU drivers are properly installed"
        else
            message="GPU devices accessible and writable"
            verbose_log "GPU device check passed"
        fi
    fi

    print_test_result "$result" "$message"
    record_test "GPU Device Access" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 2: Kernel Modules
test_kernel_modules() {
    print_test_header "Test 2: Kernel Modules"
    local result="pass"
    local message=""
    local fix=""
    local missing_modules=()

    for module in binder_linux ashmem_linux; do
        verbose_log "Checking module: $module"
        if check_kernel_module "$module"; then
            print_test_result "pass" "$module loaded"
        else
            print_test_result "fail" "$module not loaded"
            missing_modules+=("$module")
            result="fail"
        fi
    done

    if [ "$result" = "pass" ]; then
        message="All required kernel modules loaded"
    else
        message="Missing modules: ${missing_modules[*]}"
        fix="Load modules manually: 'modprobe ${missing_modules[*]}' or ensure they're loaded at boot via /etc/modules-load.d/"
    fi

    record_test "Kernel Modules" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 3: Waydroid Installation
test_waydroid_installation() {
    print_test_header "Test 3: Waydroid Installation"
    local result="pass"
    local message=""
    local fix=""

    verbose_log "Checking if Waydroid is installed..."
    if is_waydroid_installed; then
        local version=$(waydroid --version 2>/dev/null || echo 'unknown')
        local status=$(get_waydroid_status)
        message="Waydroid installed (version: $version, status: $status)"
        print_test_result "pass" "Waydroid installed"
        print_test_result "pass" "Version: $version"
        print_test_result "pass" "Status: $status"

        verbose_log "Checking Waydroid initialization..."
        if [ ! -d "/var/lib/waydroid/overlay" ]; then
            result="warn"
            message="Waydroid installed but not initialized"
            fix="Initialize Waydroid: waydroid init -s GAPPS"
        fi
    else
        result="fail"
        message="Waydroid not installed"
        fix="Install Waydroid using the setup script or manually from https://github.com/waydroid/waydroid"
    fi

    record_test "Waydroid Installation" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 4: Wayland Compositor
test_wayland_compositor() {
    print_test_header "Test 4: Wayland Compositor"
    local result="fail"
    local message=""
    local fix=""
    local compositors=()

    verbose_log "Checking for Sway..."
    if command -v sway &> /dev/null; then
        print_test_result "pass" "Sway installed"
        compositors+=("sway")
        result="pass"
    else
        print_test_result "warn" "Sway not found"
    fi

    verbose_log "Checking for Weston..."
    if command -v weston &> /dev/null; then
        print_test_result "pass" "Weston installed"
        compositors+=("weston")
        result="pass"
    else
        print_test_result "warn" "Weston not found"
    fi

    if [ "$result" = "pass" ]; then
        message="Wayland compositor(s) found: ${compositors[*]}"
    else
        message="No Wayland compositor found"
        fix="Install a Wayland compositor: apt install sway weston"
    fi

    record_test "Wayland Compositor" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 5: VNC Server
test_vnc_server() {
    print_test_header "Test 5: VNC Server"
    local result="pass"
    local message=""
    local fix=""

    verbose_log "Checking for WayVNC..."
    if command -v wayvnc &> /dev/null; then
        print_test_result "pass" "WayVNC installed"

        verbose_log "Checking VNC service status..."
        if systemctl is-active --quiet waydroid-vnc.service; then
            print_test_result "pass" "VNC service running"

            verbose_log "Testing VNC port 5900..."
            if netstat -tuln 2>/dev/null | grep -q ":5900" || ss -tuln 2>/dev/null | grep -q ":5900"; then
                print_test_result "pass" "VNC listening on port 5900"
                message="VNC server operational"
            else
                result="warn"
                message="VNC service running but not listening on port 5900"
                fix="Check VNC service logs: journalctl -u waydroid-vnc.service -n 50"
            fi
        else
            result="warn"
            message="VNC installed but service not running"
            fix="Start VNC service: systemctl start waydroid-vnc.service && systemctl enable waydroid-vnc.service"
        fi
    else
        result="fail"
        message="WayVNC not installed"
        fix="Install WayVNC: apt install wayvnc or build from source"
    fi

    record_test "VNC Server" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 6: API Server
test_api_server() {
    print_test_header "Test 6: Home Assistant API"
    local result="pass"
    local message=""
    local fix=""

    verbose_log "Checking for API script..."
    if [ -f /usr/local/bin/waydroid-api.py ]; then
        print_test_result "pass" "API script exists"

        verbose_log "Checking API service status..."
        if systemctl is-active --quiet waydroid-api.service; then
            print_test_result "pass" "API service running"

            verbose_log "Testing API port 8080..."
            if netstat -tuln 2>/dev/null | grep -q ":8080" || ss -tuln 2>/dev/null | grep -q ":8080"; then
                print_test_result "pass" "API listening on port 8080"
                message="API server operational"
            else
                result="warn"
                message="API service running but not listening on port 8080"
                fix="Check API service logs: journalctl -u waydroid-api.service -n 50"
            fi
        else
            result="warn"
            message="API script exists but service not running"
            fix="Start API service: systemctl start waydroid-api.service && systemctl enable waydroid-api.service"
        fi
    else
        result="fail"
        message="API script not found"
        fix="Install API script from the project repository to /usr/local/bin/waydroid-api.py"
    fi

    record_test "API Server" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 7: Systemd Services
test_systemd_services() {
    print_test_header "Test 7: Systemd Services"
    local result="pass"
    local message=""
    local fix=""
    local service_issues=()

    for service in waydroid-container.service waydroid-vnc.service waydroid-api.service; do
        verbose_log "Checking service: $service"
        if systemctl list-unit-files | grep -q "$service"; then
            local enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
            local active=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
            print_test_result "pass" "$service: enabled=$enabled, active=$active"

            if [ "$active" != "active" ]; then
                service_issues+=("$service not active")
            fi
        else
            print_test_result "warn" "$service not found"
            service_issues+=("$service not installed")
        fi
    done

    if [ ${#service_issues[@]} -gt 0 ]; then
        result="warn"
        message="Service issues: ${service_issues[*]}"
        fix="Review service configuration and start required services with systemctl"
    else
        message="All services configured and running"
    fi

    record_test "Systemd Services" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 8: Network Connectivity
test_network_connectivity() {
    print_test_header "Test 8: Network Connectivity"
    local result="pass"
    local message=""
    local fix=""

    verbose_log "Testing DNS resolution..."
    if host google.com &> /dev/null || nslookup google.com &> /dev/null || dig google.com &> /dev/null; then
        print_test_result "pass" "DNS resolution working"
    else
        result="fail"
        message="DNS resolution failed"
        fix="Check /etc/resolv.conf and network configuration. Ensure nameserver is set correctly"
        print_test_result "fail" "DNS resolution failed"
        record_test "Network Connectivity" "$result" "$message" "$fix"
        ! $JSON_OUTPUT && echo ""
        return
    fi

    verbose_log "Testing outbound connectivity..."
    if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        print_test_result "pass" "Outbound connectivity working (ping 8.8.8.8)"
    else
        result="fail"
        message="Outbound connectivity failed"
        fix="Check network configuration, firewall rules, and LXC network settings"
        print_test_result "fail" "Cannot reach external hosts"
        record_test "Network Connectivity" "$result" "$message" "$fix"
        ! $JSON_OUTPUT && echo ""
        return
    fi

    verbose_log "Testing HTTP connectivity..."
    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 3 https://google.com > /dev/null; then
            print_test_result "pass" "HTTP/HTTPS connectivity working"
            message="Network fully operational"
        else
            result="warn"
            message="ICMP works but HTTP fails"
            fix="Check proxy settings and firewall rules for HTTP/HTTPS traffic"
        fi
    else
        verbose_log "curl not available, skipping HTTP test"
        message="Basic network connectivity working"
    fi

    record_test "Network Connectivity" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 9: GPU Performance
test_gpu_performance() {
    print_test_header "Test 9: GPU Performance"
    local result="pass"
    local message=""
    local fix=""

    verbose_log "Checking for glxinfo..."
    if command -v glxinfo &> /dev/null; then
        verbose_log "Running glxinfo..."
        local glx_output=$(glxinfo 2>&1)

        if echo "$glx_output" | grep -q "direct rendering: Yes"; then
            print_test_result "pass" "Direct rendering enabled"

            local renderer=$(echo "$glx_output" | grep "OpenGL renderer" | cut -d: -f2 | xargs)
            if [ -n "$renderer" ]; then
                print_test_result "pass" "GPU renderer: $renderer"
                message="GPU acceleration working ($renderer)"
            else
                message="GPU acceleration working"
            fi
        else
            result="fail"
            message="Direct rendering not available"
            fix="Check GPU drivers installation and configuration. For Intel: apt install mesa-utils intel-gpu-tools"
        fi
    else
        result="warn"
        message="glxinfo not available, cannot verify GPU acceleration"
        fix="Install mesa-utils: apt install mesa-utils"
    fi

    verbose_log "Checking for intel_gpu_top..."
    if command -v intel_gpu_top &> /dev/null; then
        print_test_result "pass" "Intel GPU tools available"
    else
        if [ "$result" != "fail" ]; then
            result="warn"
        fi
        verbose_log "intel_gpu_top not found"
    fi

    record_test "GPU Performance" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 10: Waydroid App Launch
test_waydroid_app_launch() {
    print_test_header "Test 10: Waydroid App Launch"
    local result="pass"
    local message=""
    local fix=""

    if ! is_waydroid_installed; then
        result="skip"
        message="Waydroid not installed, skipping app launch test"
        record_test "Waydroid App Launch" "$result" "$message" "$fix"
        print_test_result "warn" "$message"
        ! $JSON_OUTPUT && echo ""
        return
    fi

    if [ "$(get_waydroid_status)" != "running" ]; then
        result="skip"
        message="Waydroid not running, skipping app launch test"
        fix="Start Waydroid: waydroid session start"
        record_test "Waydroid App Launch" "$result" "$message" "$fix"
        print_test_result "warn" "$message"
        ! $JSON_OUTPUT && echo ""
        return
    fi

    verbose_log "Checking installed apps..."
    local app_list=$(waydroid app list 2>/dev/null)

    if [ -n "$app_list" ]; then
        local app_count=$(echo "$app_list" | wc -l)
        print_test_result "pass" "Found $app_count installed apps"
        message="Waydroid apps available ($app_count apps)"

        # Try to get app info (non-intrusive check)
        verbose_log "Verifying app manager accessibility..."
        if waydroid app list &> /dev/null; then
            print_test_result "pass" "App manager accessible"
        fi
    else
        result="warn"
        message="No apps installed in Waydroid"
        fix="Install apps via: waydroid app install <apk_file> or use Waydroid's built-in app store"
    fi

    record_test "Waydroid App Launch" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 11: VNC Connection Test
test_vnc_connection() {
    print_test_header "Test 11: VNC Connection Test"
    local result="pass"
    local message=""
    local fix=""

    if ! command -v timeout &> /dev/null; then
        result="skip"
        message="timeout command not available"
        record_test "VNC Connection Test" "$result" "$message" "$fix"
        print_test_result "warn" "$message"
        ! $JSON_OUTPUT && echo ""
        return
    fi

    verbose_log "Testing actual VNC connection to localhost:5900..."
    if timeout 2 bash -c "</dev/tcp/localhost/5900" 2>/dev/null; then
        print_test_result "pass" "VNC port accepts connections"
        message="VNC connection test successful"
    else
        if systemctl is-active --quiet waydroid-vnc.service; then
            result="warn"
            message="VNC service running but connection test failed"
            fix="Check firewall rules and VNC configuration. Test with: nc -zv localhost 5900"
        else
            result="fail"
            message="Cannot connect to VNC port"
            fix="Start VNC service: systemctl start waydroid-vnc.service"
        fi
    fi

    record_test "VNC Connection Test" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Test 12: API Endpoint Tests
test_api_endpoints() {
    print_test_header "Test 12: API Endpoint Tests"
    local result="pass"
    local message=""
    local fix=""

    if ! command -v curl &> /dev/null; then
        result="skip"
        message="curl not available"
        fix="Install curl: apt install curl"
        record_test "API Endpoint Tests" "$result" "$message" "$fix"
        print_test_result "warn" "$message"
        ! $JSON_OUTPUT && echo ""
        return
    fi

    if ! systemctl is-active --quiet waydroid-api.service; then
        result="skip"
        message="API service not running"
        fix="Start API service: systemctl start waydroid-api.service"
        record_test "API Endpoint Tests" "$result" "$message" "$fix"
        print_test_result "warn" "$message"
        ! $JSON_OUTPUT && echo ""
        return
    fi

    verbose_log "Testing API status endpoint..."
    local api_response=$(curl -s --connect-timeout 2 http://localhost:8080/status 2>/dev/null)

    if [ -n "$api_response" ]; then
        print_test_result "pass" "API /status endpoint responding"

        verbose_log "Checking API response format..."
        if echo "$api_response" | grep -q -E '(status|waydroid|state)'; then
            print_test_result "pass" "API response format valid"
            message="API endpoints functional"
        else
            result="warn"
            message="API responding but unexpected format"
            fix="Check API service logs: journalctl -u waydroid-api.service -n 50"
        fi
    else
        result="fail"
        message="API not responding to requests"
        fix="Check API service status and logs: systemctl status waydroid-api.service"
    fi

    record_test "API Endpoint Tests" "$result" "$message" "$fix"
    ! $JSON_OUTPUT && echo ""
}

# Generate JSON output
generate_json_output() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local exit_code=0
    [ $FAILED_TESTS -gt 0 ] && exit_code=1

    cat << EOF
{
  "timestamp": "$timestamp",
  "summary": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "warnings": $WARNINGS,
    "exit_code": $exit_code
  },
  "system": {
    "hostname": "$(hostname)",
    "ip": "$(get_container_ip)",
    "os": "$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2)",
    "kernel": "$(uname -r)"
  },
  "tests": [
EOF

    for i in "${!TEST_NAMES[@]}"; do
        local comma=","
        [ $i -eq $((${#TEST_NAMES[@]} - 1)) ] && comma=""

        cat << EOF
    {
      "name": "${TEST_NAMES[$i]}",
      "result": "${TEST_RESULTS[$i]}",
      "message": "${TEST_MESSAGES[$i]}",
      "fix_suggestion": "${FIX_SUGGESTIONS[$i]}"
    }$comma
EOF
    done

    cat << EOF
  ]
}
EOF
}

# Generate text summary
generate_text_summary() {
    echo -e "${GN}==================================================${CL}"
    echo -e "${GN}  Verification Complete${CL}"
    echo -e "${GN}==================================================${CL}\n"

    echo -e "${BL}Test Summary:${CL}"
    echo -e "  Total Tests: $TOTAL_TESTS"
    echo -e "  ${GN}Passed: $PASSED_TESTS${CL}"
    [ $FAILED_TESTS -gt 0 ] && echo -e "  ${RD}Failed: $FAILED_TESTS${CL}"
    [ $WARNINGS -gt 0 ] && echo -e "  ${YW}Warnings: $WARNINGS${CL}"
    echo ""

    # Show failed tests and fixes
    if [ $FAILED_TESTS -gt 0 ] || [ $WARNINGS -gt 0 ]; then
        echo -e "${RD}Failed Tests and Recommended Fixes:${CL}"
        for i in "${!TEST_NAMES[@]}"; do
            if [ "${TEST_RESULTS[$i]}" = "fail" ] || [ "${TEST_RESULTS[$i]}" = "warn" ]; then
                echo -e "\n${BL}${TEST_NAMES[$i]}:${CL}"
                echo -e "  ${RD}Issue:${CL} ${TEST_MESSAGES[$i]}"
                if [ -n "${FIX_SUGGESTIONS[$i]}" ]; then
                    echo -e "  ${GN}Fix:${CL} ${FIX_SUGGESTIONS[$i]}"
                fi
            fi
        done
        echo ""
    fi

    # Additional recommendations
    echo -e "${BL}Additional Recommendations:${CL}"
    if ! systemctl is-active --quiet waydroid-vnc.service; then
        echo -e "  • Start VNC: ${GN}systemctl start waydroid-vnc${CL}"
        echo -e "  • Enable VNC: ${GN}systemctl enable waydroid-vnc${CL}"
    fi

    if ! systemctl is-active --quiet waydroid-api.service; then
        echo -e "  • Start API: ${GN}systemctl start waydroid-api${CL}"
        echo -e "  • Enable API: ${GN}systemctl enable waydroid-api${CL}"
    fi

    if [ "$(get_waydroid_status)" != "running" ]; then
        if [ ! -d "/var/lib/waydroid/overlay" ]; then
            echo -e "  • Initialize Waydroid: ${GN}waydroid init -s GAPPS${CL}"
        fi
        echo -e "  • Start Waydroid: ${GN}waydroid session start${CL}"
    fi

    echo -e "\n${BL}Access Information:${CL}"
    echo -e "  • VNC: ${GN}$(get_container_ip):5900${CL}"
    echo -e "  • API: ${GN}http://$(get_container_ip):8080${CL}\n"
}

# Main execution
main() {
    parse_args "$@"

    # Print header (skip for JSON)
    if ! $JSON_OUTPUT; then
        echo -e "${GN}==================================================${CL}"
        echo -e "${GN}  Waydroid LXC Setup Verification${CL}"
        echo -e "${GN}==================================================${CL}\n"
    fi

    # Check if running in LXC
    if ! is_lxc; then
        if $JSON_OUTPUT; then
            echo '{"error": "This script must be run inside an LXC container", "exit_code": 2}'
        else
            msg_error "This script should be run inside the LXC container"
        fi
        exit 2
    fi

    # Display system info (skip for JSON)
    if ! $JSON_OUTPUT; then
        show_system_info
    fi

    # Run all tests
    test_gpu_access
    test_kernel_modules
    test_waydroid_installation
    test_wayland_compositor
    test_vnc_server
    test_api_server
    test_systemd_services
    test_network_connectivity
    test_gpu_performance
    test_waydroid_app_launch
    test_vnc_connection
    test_api_endpoints

    # Output results
    if $JSON_OUTPUT; then
        generate_json_output
    else
        generate_text_summary
    fi

    # Exit with appropriate code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
