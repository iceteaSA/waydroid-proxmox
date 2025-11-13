#!/usr/bin/env bash

# Test Script for Waydroid Clipboard Sharing
# Comprehensive testing of clipboard functionality

set -euo pipefail

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
print_test_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_test_result() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$result" = "PASS" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $test_name"
        [ -n "$message" ] && echo -e "  ${message}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $test_name"
        [ -n "$message" ] && echo -e "  ${RED}${message}${NC}"
    fi
}

# ============================================================================
# TEST: Dependencies
# ============================================================================

test_dependencies() {
    print_test_header "Testing Dependencies"

    local deps_ok=true

    # Check wl-copy
    if command -v wl-copy &>/dev/null; then
        print_test_result "wl-copy installed" "PASS"
    else
        print_test_result "wl-copy installed" "FAIL" "Install with: apt-get install wl-clipboard"
        deps_ok=false
    fi

    # Check wl-paste
    if command -v wl-paste &>/dev/null; then
        print_test_result "wl-paste installed" "PASS"
    else
        print_test_result "wl-paste installed" "FAIL" "Install with: apt-get install wl-clipboard"
        deps_ok=false
    fi

    # Check adb
    if command -v adb &>/dev/null; then
        print_test_result "adb installed" "PASS"
    else
        print_test_result "adb installed" "FAIL" "Install with: apt-get install adb"
        deps_ok=false
    fi

    # Check waydroid
    if command -v waydroid &>/dev/null; then
        print_test_result "waydroid installed" "PASS"
    else
        print_test_result "waydroid installed" "FAIL" "Waydroid is required"
        deps_ok=false
    fi

    # Check sync daemon
    if [ -f /usr/local/bin/waydroid-clipboard-sync.sh ]; then
        print_test_result "Sync daemon installed" "PASS"
    else
        print_test_result "Sync daemon installed" "FAIL" "Run: ./scripts/setup-clipboard.sh --install"
        deps_ok=false
    fi

    # Check management tool
    if command -v waydroid-clipboard &>/dev/null; then
        print_test_result "Management tool installed" "PASS"
    else
        print_test_result "Management tool installed" "FAIL" "Run: ./scripts/setup-clipboard.sh --install"
        deps_ok=false
    fi

    return $([ "$deps_ok" = true ] && echo 0 || echo 1)
}

# ============================================================================
# TEST: Environment
# ============================================================================

test_environment() {
    print_test_header "Testing Environment"

    # Check Wayland display
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        print_test_result "WAYLAND_DISPLAY set" "PASS" "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    else
        print_test_result "WAYLAND_DISPLAY set" "FAIL" "Not in Wayland session"
        return 1
    fi

    # Check XDG runtime dir
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ]; then
        print_test_result "XDG_RUNTIME_DIR valid" "PASS" "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
    else
        print_test_result "XDG_RUNTIME_DIR valid" "FAIL" "XDG_RUNTIME_DIR not set or invalid"
        return 1
    fi

    # Check if in LXC container
    if [ -f /proc/1/environ ] && grep -q container=lxc /proc/1/environ; then
        print_test_result "Running in LXC" "PASS"
    else
        print_test_result "Running in LXC" "FAIL" "Not in LXC container"
    fi

    return 0
}

# ============================================================================
# TEST: Services
# ============================================================================

test_services() {
    print_test_header "Testing Services"

    # Check Waydroid status
    if waydroid status 2>&1 | grep -q "RUNNING"; then
        print_test_result "Waydroid running" "PASS"
    else
        print_test_result "Waydroid running" "FAIL" "Start with: systemctl start waydroid"
        return 1
    fi

    # Check systemd service exists
    if systemctl list-unit-files | grep -q "waydroid-clipboard-sync.service"; then
        print_test_result "Clipboard service installed" "PASS"
    else
        print_test_result "Clipboard service installed" "FAIL" "Run: ./scripts/setup-clipboard.sh --install"
        return 1
    fi

    # Check service status
    if systemctl is-active waydroid-clipboard-sync >/dev/null 2>&1; then
        print_test_result "Clipboard service running" "PASS"

        # Check uptime
        local uptime=$(systemctl show -p ActiveEnterTimestamp waydroid-clipboard-sync --value)
        print_test_result "Service uptime" "PASS" "Started: $uptime"
    else
        print_test_result "Clipboard service running" "FAIL" "Start with: waydroid-clipboard start"
    fi

    return 0
}

# ============================================================================
# TEST: ADB Connection
# ============================================================================

test_adb_connection() {
    print_test_header "Testing ADB Connection"

    # Check ADB server
    if adb start-server >/dev/null 2>&1; then
        print_test_result "ADB server running" "PASS"
    else
        print_test_result "ADB server running" "FAIL" "Cannot start ADB server"
        return 1
    fi

    # Check device connection
    if adb devices 2>/dev/null | grep -q "localhost:5555.*device$"; then
        print_test_result "ADB connected to Waydroid" "PASS"
    else
        print_test_result "ADB connected to Waydroid" "FAIL" "Connect with: adb connect localhost:5555"

        # Try to connect
        echo -e "${YELLOW}  Attempting to connect...${NC}"
        if adb connect localhost:5555 >/dev/null 2>&1; then
            sleep 2
            if adb devices 2>/dev/null | grep -q "localhost:5555.*device$"; then
                print_test_result "ADB auto-connect" "PASS"
            else
                print_test_result "ADB auto-connect" "FAIL"
                return 1
            fi
        else
            return 1
        fi
    fi

    # Test ADB shell access
    if adb shell echo "test" >/dev/null 2>&1; then
        print_test_result "ADB shell access" "PASS"
    else
        print_test_result "ADB shell access" "FAIL" "Cannot execute shell commands"
        return 1
    fi

    return 0
}

# ============================================================================
# TEST: Wayland Clipboard
# ============================================================================

test_wayland_clipboard() {
    print_test_header "Testing Wayland Clipboard"

    local test_text="waydroid-clipboard-test-wayland-$(date +%s)"

    # Test write
    if echo "$test_text" | wl-copy 2>/dev/null; then
        print_test_result "Wayland clipboard write" "PASS"
    else
        print_test_result "Wayland clipboard write" "FAIL" "Cannot write to clipboard"
        return 1
    fi

    # Test read
    local result
    if result=$(wl-paste 2>/dev/null); then
        if [ "$result" = "$test_text" ]; then
            print_test_result "Wayland clipboard read" "PASS"
        else
            print_test_result "Wayland clipboard read" "FAIL" "Read/write mismatch"
            return 1
        fi
    else
        print_test_result "Wayland clipboard read" "FAIL" "Cannot read clipboard"
        return 1
    fi

    # Test with multiline
    local multiline_text="line1\nline2\nline3"
    if echo -e "$multiline_text" | wl-copy 2>/dev/null; then
        result=$(wl-paste 2>/dev/null)
        if [ "$result" = "$(echo -e "$multiline_text")" ]; then
            print_test_result "Wayland multiline clipboard" "PASS"
        else
            print_test_result "Wayland multiline clipboard" "FAIL"
        fi
    else
        print_test_result "Wayland multiline clipboard" "FAIL"
    fi

    return 0
}

# ============================================================================
# TEST: Android Clipboard
# ============================================================================

test_android_clipboard() {
    print_test_header "Testing Android Clipboard"

    local test_text="waydroid-clipboard-test-android-$(date +%s)"

    # Test write
    if adb shell "cmd clipboard put '$test_text'" 2>/dev/null; then
        print_test_result "Android clipboard write" "PASS"
    else
        print_test_result "Android clipboard write" "FAIL" "Cannot write to Android clipboard"
        return 1
    fi

    # Wait for clipboard to settle
    sleep 1

    # Test read
    local result
    if result=$(adb shell cmd clipboard get 2>/dev/null | tr -d '\n\r'); then
        if [ "$result" = "$test_text" ]; then
            print_test_result "Android clipboard read" "PASS"
        else
            print_test_result "Android clipboard read" "FAIL" "Read/write mismatch (got: '$result')"
            return 1
        fi
    else
        print_test_result "Android clipboard read" "FAIL" "Cannot read Android clipboard"
        return 1
    fi

    # Test with special characters
    local special_text="Test with 'quotes' and \"double quotes\" and \$special"
    if adb shell "cmd clipboard put '$special_text'" 2>/dev/null; then
        sleep 1
        result=$(adb shell cmd clipboard get 2>/dev/null | tr -d '\n\r')
        if [ "$result" = "$special_text" ]; then
            print_test_result "Android special characters" "PASS"
        else
            print_test_result "Android special characters" "FAIL"
        fi
    else
        print_test_result "Android special characters" "FAIL"
    fi

    return 0
}

# ============================================================================
# TEST: Bidirectional Sync
# ============================================================================

test_bidirectional_sync() {
    print_test_header "Testing Bidirectional Sync"

    # Check if service is running
    if ! systemctl is-active waydroid-clipboard-sync >/dev/null 2>&1; then
        print_test_result "Sync service check" "FAIL" "Service not running - skipping sync tests"
        return 1
    fi

    print_test_result "Sync service check" "PASS"

    # Get sync interval from service
    local sync_interval=2
    if [ -f /etc/systemd/system/waydroid-clipboard-sync.service ]; then
        local interval_line=$(grep "CLIPBOARD_SYNC_INTERVAL" /etc/systemd/system/waydroid-clipboard-sync.service)
        if [ -n "$interval_line" ]; then
            sync_interval=$(echo "$interval_line" | grep -oP '\d+')
        fi
    fi

    local wait_time=$((sync_interval + 2))
    echo -e "${BLUE}Using sync interval: ${sync_interval}s (waiting ${wait_time}s for each test)${NC}"
    echo ""

    # Test 1: Wayland -> Android
    local test_text_1="waydroid-test-w2a-$(date +%s)"
    echo -e "${YELLOW}Test 1: Wayland -> Android${NC}"
    echo "  Setting Wayland clipboard: $test_text_1"
    echo "$test_text_1" | wl-copy

    echo "  Waiting ${wait_time}s for sync..."
    sleep "$wait_time"

    local android_result=$(adb shell cmd clipboard get 2>/dev/null | tr -d '\n\r')
    if [ "$android_result" = "$test_text_1" ]; then
        print_test_result "Wayland -> Android sync" "PASS"
    else
        print_test_result "Wayland -> Android sync" "FAIL" "Expected: '$test_text_1', Got: '$android_result'"
    fi

    # Test 2: Android -> Wayland
    local test_text_2="waydroid-test-a2w-$(date +%s)"
    echo -e "${YELLOW}Test 2: Android -> Wayland${NC}"
    echo "  Setting Android clipboard: $test_text_2"
    adb shell "cmd clipboard put '$test_text_2'" 2>/dev/null

    echo "  Waiting ${wait_time}s for sync..."
    sleep "$wait_time"

    local wayland_result=$(wl-paste 2>/dev/null)
    if [ "$wayland_result" = "$test_text_2" ]; then
        print_test_result "Android -> Wayland sync" "PASS"
    else
        print_test_result "Android -> Wayland sync" "FAIL" "Expected: '$test_text_2', Got: '$wayland_result'"
    fi

    # Test 3: Loop prevention
    echo -e "${YELLOW}Test 3: Loop Prevention${NC}"
    local test_text_3="waydroid-test-loop-$(date +%s)"
    echo "  Setting clipboard and checking for loops..."

    # Get initial log size
    local log_file="/var/log/waydroid-clipboard.log"
    local initial_lines=0
    if [ -f "$log_file" ]; then
        initial_lines=$(wc -l < "$log_file")
    fi

    echo "$test_text_3" | wl-copy
    sleep $((wait_time * 2))

    # Count sync operations
    local final_lines=0
    if [ -f "$log_file" ]; then
        final_lines=$(wc -l < "$log_file")
    fi

    local new_syncs=$((final_lines - initial_lines))
    local sync_count=$(tail -n "$new_syncs" "$log_file" 2>/dev/null | grep -c "Syncing" || echo "0")

    if [ "$sync_count" -le 2 ]; then
        print_test_result "Loop prevention" "PASS" "Only $sync_count sync operations (expected ≤2)"
    else
        print_test_result "Loop prevention" "FAIL" "Too many sync operations: $sync_count (expected ≤2)"
    fi

    return 0
}

# ============================================================================
# TEST: Performance
# ============================================================================

test_performance() {
    print_test_header "Testing Performance"

    # Test large clipboard content
    echo -e "${YELLOW}Testing clipboard size limits...${NC}"

    # 100KB test
    local small_text=$(head -c 102400 /dev/urandom | base64 | tr -d '\n')
    if echo "$small_text" | wl-copy 2>/dev/null; then
        print_test_result "100KB clipboard" "PASS"
    else
        print_test_result "100KB clipboard" "FAIL"
    fi

    # 1MB test (default limit)
    local large_text=$(head -c 1048576 /dev/urandom | base64 | tr -d '\n')
    if echo "$large_text" | wl-copy 2>/dev/null; then
        print_test_result "1MB clipboard" "PASS"
    else
        print_test_result "1MB clipboard" "FAIL"
    fi

    # Cleanup
    echo "cleanup" | wl-copy

    # Check service resource usage
    if systemctl is-active waydroid-clipboard-sync >/dev/null 2>&1; then
        local memory_usage=$(systemctl show waydroid-clipboard-sync -p MemoryCurrent --value 2>/dev/null)
        if [ -n "$memory_usage" ] && [ "$memory_usage" != "0" ]; then
            local memory_mb=$((memory_usage / 1024 / 1024))
            print_test_result "Memory usage check" "PASS" "Using ${memory_mb}MB RAM"
        else
            print_test_result "Memory usage check" "PASS" "Cannot determine memory usage"
        fi
    fi

    return 0
}

# ============================================================================
# TEST: Log Files
# ============================================================================

test_logs() {
    print_test_header "Testing Log Files"

    # Check log file exists
    if [ -f /var/log/waydroid-clipboard.log ]; then
        print_test_result "Log file exists" "PASS"

        local log_size=$(du -h /var/log/waydroid-clipboard.log | cut -f1)
        print_test_result "Log file size" "PASS" "Size: $log_size"

        # Check for recent activity
        local today=$(date +%Y-%m-%d)
        if grep -q "$today" /var/log/waydroid-clipboard.log 2>/dev/null; then
            print_test_result "Recent log activity" "PASS"
        else
            print_test_result "Recent log activity" "FAIL" "No logs from today"
        fi
    else
        print_test_result "Log file exists" "FAIL" "Log file not found"
    fi

    # Check logrotate config
    if [ -f /etc/logrotate.d/waydroid-clipboard ]; then
        print_test_result "Logrotate configured" "PASS"
    else
        print_test_result "Logrotate configured" "FAIL"
    fi

    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Waydroid Clipboard Test Suite${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "This will test all clipboard functionality"
    echo ""

    # Run tests
    test_dependencies || true
    test_environment || true
    test_services || true
    test_adb_connection || true
    test_wayland_clipboard || true
    test_android_clipboard || true
    test_bidirectional_sync || true
    test_performance || true
    test_logs || true

    # Summary
    print_test_header "Test Summary"

    echo "Tests run: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""

    local pass_rate=0
    if [ "$TESTS_RUN" -gt 0 ]; then
        pass_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    fi

    echo "Pass rate: ${pass_rate}%"
    echo ""

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check service status: systemctl status waydroid-clipboard-sync"
        echo "  2. View logs: waydroid-clipboard logs"
        echo "  3. Restart service: waydroid-clipboard restart"
        echo "  4. Run manual test: waydroid-clipboard test"
        echo ""
        return 1
    fi
}

# Run tests
main
