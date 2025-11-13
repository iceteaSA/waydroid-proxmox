#!/usr/bin/env bash

################################################################################
# Example Usage Scripts for test-complete.sh
#
# This file demonstrates various ways to use the comprehensive testing script.
# You can copy these examples and adapt them to your needs.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="${SCRIPT_DIR}/test-complete.sh"

# Colors for output
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
NC="\033[0m" # No Color

print_example() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Command:${NC} $2"
    echo ""
}

################################################################################
# Example 1: Quick Development Test
################################################################################
example_quick_dev_test() {
    print_example "Example 1: Quick Development Test" \
        "$TEST_SCRIPT --quick --verbose"

    echo "Use Case: Rapid validation during development"
    echo "Duration: ~30 seconds"
    echo "Tests: Basic functionality only"
    echo ""
    echo "Run now? (y/n)"
    read -r response
    if [ "$response" = "y" ]; then
        $TEST_SCRIPT --quick --verbose
    fi
}

################################################################################
# Example 2: Thorough Production Test
################################################################################
example_thorough_prod_test() {
    print_example "Example 2: Thorough Production Test" \
        "$TEST_SCRIPT --thorough --format all --output-dir /var/log/waydroid-tests"

    echo "Use Case: Complete system validation before deployment"
    echo "Duration: ~2 minutes"
    echo "Tests: All components including performance"
    echo "Output: Text, JSON, and HTML reports"
    echo ""
    echo "Run now? (y/n)"
    read -r response
    if [ "$response" = "y" ]; then
        sudo mkdir -p /var/log/waydroid-tests
        $TEST_SCRIPT --thorough --format all --output-dir /var/log/waydroid-tests
    fi
}

################################################################################
# Example 3: CI/CD Integration
################################################################################
example_cicd_integration() {
    print_example "Example 3: CI/CD Integration" \
        "$TEST_SCRIPT --quick --ci --format json | jq"

    echo "Use Case: Automated testing in CI/CD pipeline"
    echo "Output: Machine-readable JSON"
    echo "Exit Code: 0 on success, 1 on failure"
    echo ""
    echo "Example CI/CD script:"
    echo ""
    cat << 'CICD_EXAMPLE'
#!/bin/bash
set -e

# Run tests and save results
./scripts/test-complete.sh --quick --ci --format json > test-results.json
EXIT_CODE=$?

# Parse results
TOTAL=$(jq -r '.summary.total' test-results.json)
PASSED=$(jq -r '.summary.passed' test-results.json)
FAILED=$(jq -r '.summary.failed' test-results.json)

echo "Tests: $PASSED/$TOTAL passed"

# Upload to artifact storage
if [ -n "$CI_ARTIFACTS_URL" ]; then
    curl -F "file=@test-results.json" "$CI_ARTIFACTS_URL"
fi

# Fail build if tests failed
exit $EXIT_CODE
CICD_EXAMPLE
    echo ""
}

################################################################################
# Example 4: Scheduled Health Checks (Cron)
################################################################################
example_scheduled_cron() {
    print_example "Example 4: Scheduled Health Checks (Cron)" \
        "crontab -e"

    echo "Use Case: Automated periodic testing"
    echo "Frequency: Every hour"
    echo ""
    echo "Add this to your crontab:"
    echo ""
    cat << 'CRON_EXAMPLE'
# Waydroid health check every hour
0 * * * * /path/to/scripts/test-complete.sh --quick --ci --format json > /var/log/waydroid-test-latest.json 2>&1 || echo "Waydroid tests failed" | mail -s "Waydroid Alert" admin@example.com
CRON_EXAMPLE
    echo ""
    echo "Or using systemd timer (recommended):"
    echo ""
    cat << 'SYSTEMD_EXAMPLE'
# /etc/systemd/system/waydroid-test.timer
[Unit]
Description=Waydroid System Test Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target

# /etc/systemd/system/waydroid-test.service
[Unit]
Description=Waydroid System Test

[Service]
Type=oneshot
ExecStart=/path/to/scripts/test-complete.sh --quick --ci --format json
StandardOutput=append:/var/log/waydroid-test.log
StandardError=append:/var/log/waydroid-test.log

# Enable with:
# systemctl enable --now waydroid-test.timer
SYSTEMD_EXAMPLE
    echo ""
}

################################################################################
# Example 5: Pre-Deployment Validation
################################################################################
example_pre_deployment() {
    print_example "Example 5: Pre-Deployment Validation" \
        "bash -c 'script...'"

    echo "Use Case: Validate system before making changes"
    echo ""
    cat << 'DEPLOY_EXAMPLE'
#!/bin/bash
# pre-deploy-check.sh

set -e

echo "Running pre-deployment validation..."

# Take baseline snapshot
echo "Creating backup..."
./scripts/backup-restore.sh --backup

# Run thorough tests
echo "Running tests..."
./scripts/test-complete.sh --thorough --format all --output-dir /var/log/pre-deploy-$(date +%Y%m%d)

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ All tests passed. Safe to deploy."
    exit 0
else
    echo "✗ Tests failed. Review results before deploying."
    echo "Backup available at: /var/backups/waydroid-backup-latest.tar.gz"
    exit 1
fi
DEPLOY_EXAMPLE
    echo ""
}

################################################################################
# Example 6: Host Pre-Check Before Container Creation
################################################################################
example_host_precheck() {
    print_example "Example 6: Host Pre-Check" \
        "$TEST_SCRIPT --from-host --quick"

    echo "Use Case: Verify host is ready before creating LXC container"
    echo "Run on: Proxmox host"
    echo ""
    echo "Run now? (y/n)"
    read -r response
    if [ "$response" = "y" ]; then
        $TEST_SCRIPT --from-host --quick
    fi
}

################################################################################
# Example 7: Monitoring Integration (Prometheus)
################################################################################
example_prometheus() {
    print_example "Example 7: Prometheus Integration" \
        "bash -c 'script...'"

    echo "Use Case: Export metrics to Prometheus"
    echo ""
    cat << 'PROM_EXAMPLE'
#!/bin/bash
# waydroid-metrics-exporter.sh

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
TEMP_FILE="/tmp/waydroid-metrics.json"

# Run tests and generate JSON
/path/to/scripts/test-complete.sh --quick --ci --format json > "$TEMP_FILE"

# Convert to Prometheus format
{
    echo "# HELP waydroid_tests_total Total number of tests"
    echo "# TYPE waydroid_tests_total gauge"
    echo "waydroid_tests_total $(jq -r '.summary.total' "$TEMP_FILE")"

    echo "# HELP waydroid_tests_passed Number of passed tests"
    echo "# TYPE waydroid_tests_passed gauge"
    echo "waydroid_tests_passed $(jq -r '.summary.passed' "$TEMP_FILE")"

    echo "# HELP waydroid_tests_failed Number of failed tests"
    echo "# TYPE waydroid_tests_failed gauge"
    echo "waydroid_tests_failed $(jq -r '.summary.failed' "$TEMP_FILE")"

    echo "# HELP waydroid_success_rate Test success rate percentage"
    echo "# TYPE waydroid_success_rate gauge"
    echo "waydroid_success_rate $(jq -r '.summary.success_rate' "$TEMP_FILE")"
} > "${OUTPUT_DIR}/waydroid.prom"

# Add to crontab: */5 * * * * /path/to/waydroid-metrics-exporter.sh
PROM_EXAMPLE
    echo ""
}

################################################################################
# Example 8: Home Assistant Monitoring
################################################################################
example_home_assistant() {
    print_example "Example 8: Home Assistant Monitoring" \
        "configuration.yaml"

    echo "Use Case: Monitor Waydroid health in Home Assistant"
    echo ""
    cat << 'HA_EXAMPLE'
# configuration.yaml

sensor:
  - platform: command_line
    name: "Waydroid Test Status"
    command: "/path/to/scripts/test-complete.sh --quick --ci --format json | jq -r '.summary.success_rate'"
    unit_of_measurement: "%"
    scan_interval: 300

  - platform: command_line
    name: "Waydroid Tests Passed"
    command: "/path/to/scripts/test-complete.sh --quick --ci --format json | jq -r '.summary.passed'"
    scan_interval: 300

  - platform: command_line
    name: "Waydroid Tests Failed"
    command: "/path/to/scripts/test-complete.sh --quick --ci --format json | jq -r '.summary.failed'"
    scan_interval: 300

automation:
  - alias: "Alert on Waydroid Test Failure"
    trigger:
      - platform: numeric_state
        entity_id: sensor.waydroid_tests_failed
        above: 0
    action:
      - service: notify.mobile_app
        data:
          title: "Waydroid Alert"
          message: "{{ states('sensor.waydroid_tests_failed') }} tests failed"
HA_EXAMPLE
    echo ""
}

################################################################################
# Example 9: Slack/Discord Notifications
################################################################################
example_notifications() {
    print_example "Example 9: Slack/Discord Notifications" \
        "bash -c 'script...'"

    echo "Use Case: Send alerts on test failures"
    echo ""
    cat << 'NOTIFY_EXAMPLE'
#!/bin/bash
# waydroid-test-notify.sh

WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
TEMP_FILE="/tmp/waydroid-test-results.json"

# Run tests
/path/to/scripts/test-complete.sh --quick --ci --format json > "$TEMP_FILE"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    FAILED=$(jq -r '.summary.failed' "$TEMP_FILE")
    WARNINGS=$(jq -r '.summary.warnings' "$TEMP_FILE")
    HOSTNAME=$(jq -r '.system.hostname' "$TEMP_FILE")

    # Create message
    MESSAGE="🚨 Waydroid Tests Failed on $HOSTNAME\n"
    MESSAGE+="Failed: $FAILED, Warnings: $WARNINGS\n"

    # Get first failed test for context
    FIRST_FAIL=$(jq -r '.tests[] | select(.result=="fail") | .name' "$TEMP_FILE" | head -1)
    if [ -n "$FIRST_FAIL" ]; then
        MESSAGE+="First failure: $FIRST_FAIL"
    fi

    # Send to Slack
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"$MESSAGE\"}" \
        "$WEBHOOK_URL"
fi
NOTIFY_EXAMPLE
    echo ""
}

################################################################################
# Example 10: Regression Testing
################################################################################
example_regression_testing() {
    print_example "Example 10: Regression Testing" \
        "bash -c 'script...'"

    echo "Use Case: Compare test results over time"
    echo ""
    cat << 'REGRESSION_EXAMPLE'
#!/bin/bash
# regression-test.sh

BASELINE_FILE="/var/log/waydroid-tests/baseline.json"
CURRENT_FILE="/tmp/waydroid-current.json"

# Run current tests
./scripts/test-complete.sh --thorough --format json > "$CURRENT_FILE"

if [ ! -f "$BASELINE_FILE" ]; then
    echo "No baseline found. Creating baseline..."
    cp "$CURRENT_FILE" "$BASELINE_FILE"
    exit 0
fi

# Compare results
BASELINE_PASSED=$(jq -r '.summary.passed' "$BASELINE_FILE")
CURRENT_PASSED=$(jq -r '.summary.passed' "$CURRENT_FILE")

BASELINE_FAILED=$(jq -r '.summary.failed' "$BASELINE_FILE")
CURRENT_FAILED=$(jq -r '.summary.failed' "$CURRENT_FILE")

echo "Baseline: $BASELINE_PASSED passed, $BASELINE_FAILED failed"
echo "Current:  $CURRENT_PASSED passed, $CURRENT_FAILED failed"

if [ "$CURRENT_FAILED" -gt "$BASELINE_FAILED" ]; then
    echo "⚠ REGRESSION DETECTED: More tests failing than baseline"

    # Show which tests regressed
    comm -13 \
        <(jq -r '.tests[] | select(.result=="fail") | .name' "$BASELINE_FILE" | sort) \
        <(jq -r '.tests[] | select(.result=="fail") | .name' "$CURRENT_FILE" | sort)

    exit 1
else
    echo "✓ No regression detected"

    # Update baseline if all tests pass
    if [ "$CURRENT_FAILED" -eq 0 ]; then
        cp "$CURRENT_FILE" "$BASELINE_FILE"
        echo "✓ Baseline updated"
    fi

    exit 0
fi
REGRESSION_EXAMPLE
    echo ""
}

################################################################################
# Main Menu
################################################################################
show_menu() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Waydroid Test Script Examples                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Choose an example to view:"
    echo ""
    echo "  1) Quick Development Test"
    echo "  2) Thorough Production Test"
    echo "  3) CI/CD Integration"
    echo "  4) Scheduled Health Checks (Cron/Systemd)"
    echo "  5) Pre-Deployment Validation"
    echo "  6) Host Pre-Check"
    echo "  7) Prometheus Integration"
    echo "  8) Home Assistant Monitoring"
    echo "  9) Slack/Discord Notifications"
    echo " 10) Regression Testing"
    echo ""
    echo "  a) Show all examples"
    echo "  q) Quit"
    echo ""
    echo -n "Selection: "
}

main() {
    while true; do
        show_menu
        read -r choice

        case $choice in
            1) example_quick_dev_test ;;
            2) example_thorough_prod_test ;;
            3) example_cicd_integration ;;
            4) example_scheduled_cron ;;
            5) example_pre_deployment ;;
            6) example_host_precheck ;;
            7) example_prometheus ;;
            8) example_home_assistant ;;
            9) example_notifications ;;
            10) example_regression_testing ;;
            a)
                example_quick_dev_test
                example_thorough_prod_test
                example_cicd_integration
                example_scheduled_cron
                example_pre_deployment
                example_host_precheck
                example_prometheus
                example_home_assistant
                example_notifications
                example_regression_testing
                ;;
            q)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid selection"
                ;;
        esac

        echo ""
        echo "Press Enter to continue..."
        read -r
    done
}

# Run main menu if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
fi
