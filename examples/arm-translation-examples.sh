#!/usr/bin/env bash

# ARM Translation Usage Examples
# Practical examples for using ARM translation with Waydroid
#
# DO NOT RUN THIS FILE DIRECTLY - it's a reference guide
# Copy and paste individual examples as needed

# ============================================================================
# Example 1: Basic Installation (Intel CPU)
# ============================================================================

basic_intel_installation() {
    # Check current system status
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status

    # Install libhoudini (recommended for Intel)
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libhoudini

    # Test the installation
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh test

    # Now you can install ARM apps
    waydroid app install /path/to/arm-app.apk
}

# ============================================================================
# Example 2: Basic Installation (AMD CPU)
# ============================================================================

basic_amd_installation() {
    # Check current system status
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status

    # Install libndk (recommended for AMD)
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libndk

    # Test the installation
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh test

    # Now you can install ARM apps
    waydroid app install /path/to/arm-app.apk
}

# ============================================================================
# Example 3: Check if APK Needs Translation Before Installing
# ============================================================================

check_before_install() {
    local apk_path="$1"

    # First, check if the APK needs ARM translation
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh verify "$apk_path"

    # Based on output:
    # - If it says "REQUIRED", install translation layer first
    # - If it says "NOT REQUIRED", install directly

    # Example output interpretation:
    # "Translation layer: REQUIRED" → Install libhoudini/libndk first
    # "Translation layer: NOT REQUIRED" → Install directly with waydroid
}

# ============================================================================
# Example 4: Complete Workflow - Installing ARM Game
# ============================================================================

install_arm_game() {
    local game_apk="$1"

    echo "Installing ARM game: $game_apk"

    # Step 1: Verify APK architecture
    echo "Step 1: Checking APK architecture..."
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh verify "$game_apk"

    # Step 2: Check if translation is already installed
    echo "Step 2: Checking translation status..."
    current_layer=$(sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status | grep "Current Layer" || echo "none")

    if [[ "$current_layer" == *"none"* ]]; then
        echo "Step 3: Installing translation layer..."
        # Detect CPU and install appropriate layer
        cpu_vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
        if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
            sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libhoudini
        else
            sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libndk
        fi
    else
        echo "Translation layer already installed: $current_layer"
    fi

    # Step 4: Restart Waydroid
    echo "Step 4: Restarting Waydroid..."
    waydroid container stop
    sleep 2
    waydroid container start
    sleep 3

    # Step 5: Install the game
    echo "Step 5: Installing game APK..."
    waydroid app install "$game_apk"

    # Step 6: Launch Waydroid UI
    echo "Step 6: Launching Waydroid..."
    waydroid show-full-ui &

    echo "Installation complete! The game should appear in the app drawer."
}

# ============================================================================
# Example 5: Troubleshooting - App Won't Install
# ============================================================================

troubleshoot_install_failure() {
    echo "Troubleshooting ARM app installation failure..."

    # Check 1: Verify translation layer is installed
    echo "Check 1: Translation layer status"
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status

    # Check 2: Verify Waydroid is running
    echo "Check 2: Waydroid status"
    waydroid status

    # Check 3: Check CPU ABI list
    echo "Check 3: Supported CPU architectures"
    waydroid prop get ro.product.cpu.abilist

    # Should show: x86_64,x86,arm64-v8a,armeabi-v7a,armeabi

    # Check 4: Restart Waydroid container
    echo "Check 4: Restarting Waydroid..."
    waydroid container stop
    sleep 2
    waydroid container start
    sleep 3

    # Check 5: Try installation again
    echo "Check 5: Retry installation"
    # waydroid app install /path/to/app.apk

    # If still failing, check logs
    echo "Check 6: Viewing installation logs"
    tail -n 50 /var/log/waydroid-arm/setup-*.log | tail -20
}

# ============================================================================
# Example 6: Troubleshooting - App Crashes on Launch
# ============================================================================

troubleshoot_crash() {
    echo "Troubleshooting ARM app crashes..."

    # Step 1: Check Waydroid logs
    echo "Step 1: Checking Waydroid logs for errors..."
    waydroid logcat | grep -i "crash\|error\|exception" | tail -20

    # Step 2: Try switching translation layer
    echo "Step 2: Switching to alternative translation layer..."

    current=$(sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status | grep "Current Layer")

    if [[ "$current" == *"libhoudini"* ]]; then
        echo "Switching from libhoudini to libndk..."
        sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh uninstall libhoudini
        sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libndk
    elif [[ "$current" == *"libndk"* ]]; then
        echo "Switching from libndk to libhoudini..."
        sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh uninstall libndk
        sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libhoudini
    fi

    # Step 3: Restart and retry
    waydroid container stop && waydroid container start
    sleep 3

    echo "Try launching the app again"
}

# ============================================================================
# Example 7: Performance Optimization for ARM Apps
# ============================================================================

optimize_arm_performance() {
    echo "Optimizing performance for ARM translation..."

    # 1. Ensure only one translation layer is installed
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status

    # 2. Use LXC tuning script (if on Proxmox)
    # sudo /home/user/waydroid-proxmox/scripts/tune-lxc.sh <ctid>

    # 3. Increase LXC resources (run on Proxmox host)
    # pct set <VMID> -cores 4 -memory 4096

    # 4. Close unnecessary background processes
    # Use Android settings to limit background apps

    # 5. Monitor resource usage
    echo "CPU and Memory usage:"
    top -b -n 1 | head -20

    # 6. Check I/O performance
    echo "I/O stats:"
    iostat -x 1 2 || echo "iostat not installed"
}

# ============================================================================
# Example 8: Batch Install Multiple ARM Apps
# ============================================================================

batch_install_arm_apps() {
    local apps_dir="$1"

    # First ensure translation layer is installed
    current=$(sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status | grep "Current Layer")
    if [[ "$current" == *"none"* ]]; then
        echo "Installing translation layer first..."
        sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libhoudini
    fi

    # Restart Waydroid
    waydroid container stop && waydroid container start
    sleep 3

    # Install all APKs in directory
    for apk in "$apps_dir"/*.apk; do
        if [ -f "$apk" ]; then
            echo "Installing: $(basename "$apk")"

            # Check architecture
            sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh verify "$apk"

            # Install
            if waydroid app install "$apk"; then
                echo "✓ Installed: $(basename "$apk")"
            else
                echo "✗ Failed: $(basename "$apk")"
            fi
        fi
    done

    echo "Batch installation complete!"
}

# ============================================================================
# Example 9: Migration - Switch Translation Layers
# ============================================================================

migrate_translation_layer() {
    local target_layer="$1"  # libhoudini or libndk

    echo "Migrating to $target_layer..."

    # Backup current configuration
    echo "Creating backup..."
    cp /var/lib/waydroid/waydroid.cfg /tmp/waydroid.cfg.backup

    # Get current layer
    current=$(sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status | grep "Current Layer" | awk '{print $NF}')

    if [ "$current" = "$target_layer" ]; then
        echo "Already using $target_layer"
        return 0
    fi

    # Stop Waydroid
    echo "Stopping Waydroid..."
    waydroid container stop
    sleep 2

    # Uninstall current layer
    if [ "$current" != "none" ]; then
        echo "Uninstalling $current..."
        sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh uninstall "$current"
    fi

    # Install new layer
    echo "Installing $target_layer..."
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install "$target_layer"

    # Test
    echo "Testing new translation layer..."
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh test

    echo "Migration complete!"
}

# ============================================================================
# Example 10: Complete Setup - New Waydroid Installation
# ============================================================================

complete_setup_with_arm() {
    echo "Complete Waydroid setup with ARM translation..."

    # 1. Ensure Waydroid is initialized
    if [ ! -d /var/lib/waydroid/overlay ]; then
        echo "Initializing Waydroid..."
        waydroid init -s GAPPS
    fi

    # 2. Start Waydroid
    echo "Starting Waydroid..."
    waydroid container start
    sleep 5

    # 3. Install ARM translation
    echo "Installing ARM translation layer..."
    cpu_vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
    if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
        sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libhoudini
    else
        sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libndk
    fi

    # 4. Test ARM translation
    echo "Testing ARM translation..."
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh test

    # 5. Show warnings
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh warnings

    echo "Setup complete! You can now install ARM apps."
}

# ============================================================================
# Example 11: Recovery - Restore from Backup
# ============================================================================

emergency_recovery() {
    echo "Emergency recovery - restoring from backup..."

    # Stop Waydroid
    waydroid container stop
    pkill -9 waydroid 2>/dev/null

    # Restore using script
    sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh restore

    # Alternative: Manual restore
    # if [ -f /var/cache/waydroid-arm/backup/latest ]; then
    #     backup_path=$(cat /var/cache/waydroid-arm/backup/latest)
    #     if [ -d "$backup_path" ]; then
    #         cp "$backup_path/waydroid.cfg" /var/lib/waydroid/waydroid.cfg
    #     fi
    # fi

    # Restart Waydroid
    waydroid container start

    echo "Recovery complete!"
}

# ============================================================================
# Example 12: Monitoring - Check Translation Performance
# ============================================================================

monitor_translation_performance() {
    echo "Monitoring ARM translation performance..."

    # Check CPU usage
    echo "=== CPU Usage ==="
    top -b -n 1 | grep waydroid | head -5

    # Check memory usage
    echo "=== Memory Usage ==="
    ps aux | grep waydroid | awk '{sum+=$4} END {print "Total Memory: " sum "%"}'

    # Monitor in real-time
    echo "=== Real-time monitoring (Ctrl+C to stop) ==="
    watch -n 1 'ps aux | grep waydroid | grep -v grep | awk "{print \$2, \$3, \$4, \$11}"'
}

# ============================================================================
# Example 13: Automated Testing Script
# ============================================================================

automated_testing() {
    local test_apk="$1"

    echo "Automated ARM translation testing..."

    # Test 1: Verify installation
    echo "Test 1: Verify translation layer installation"
    if sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status | grep -q "libhoudini\|libndk"; then
        echo "✓ Translation layer installed"
    else
        echo "✗ Translation layer not installed"
        return 1
    fi

    # Test 2: Verify configuration
    echo "Test 2: Verify native bridge configuration"
    if grep -q "ro.dalvik.vm.native.bridge" /var/lib/waydroid/waydroid.cfg; then
        echo "✓ Native bridge configured"
    else
        echo "✗ Native bridge not configured"
        return 1
    fi

    # Test 3: Verify ABI list
    echo "Test 3: Verify ARM architectures in ABI list"
    abi_list=$(waydroid prop get ro.product.cpu.abilist 2>/dev/null)
    if [[ "$abi_list" == *"arm64-v8a"* ]] && [[ "$abi_list" == *"armeabi-v7a"* ]]; then
        echo "✓ ARM architectures in ABI list"
    else
        echo "✗ ARM architectures missing from ABI list"
        return 1
    fi

    # Test 4: Try installing test APK if provided
    if [ -n "$test_apk" ] && [ -f "$test_apk" ]; then
        echo "Test 4: Installing test APK"
        if waydroid app install "$test_apk" 2>&1 | grep -q "Success"; then
            echo "✓ Test APK installed successfully"
        else
            echo "⚠ Test APK installation had issues"
        fi
    fi

    echo "Automated testing complete!"
}

# ============================================================================
# Usage Instructions
# ============================================================================

show_usage() {
    cat << 'EOF'
ARM Translation Examples - Usage Guide

This file contains practical examples for using ARM translation with Waydroid.
DO NOT run this script directly - copy and paste individual functions.

Available examples:

1. basic_intel_installation     - Install libhoudini on Intel CPU
2. basic_amd_installation       - Install libndk on AMD CPU
3. check_before_install         - Verify APK architecture before installing
4. install_arm_game             - Complete workflow for installing ARM game
5. troubleshoot_install_failure - Fix installation failures
6. troubleshoot_crash           - Fix app crashes
7. optimize_arm_performance     - Improve ARM app performance
8. batch_install_arm_apps       - Install multiple ARM APKs
9. migrate_translation_layer    - Switch between libhoudini and libndk
10. complete_setup_with_arm     - Full setup from scratch
11. emergency_recovery          - Restore from backup
12. monitor_translation_performance - Monitor CPU/memory usage
13. automated_testing           - Run automated tests

Usage:
  # Copy function to terminal and run it
  <function_name> [arguments]

  # Or source this file and call functions
  source /home/user/waydroid-proxmox/examples/arm-translation-examples.sh
  install_arm_game /path/to/game.apk

EOF
}

# Show usage if run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    show_usage
fi
