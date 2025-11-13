#!/usr/bin/env bash

# Test script for update-system.sh improvements
# This script tests all new features without making actual changes

SCRIPT_DIR="/home/user/waydroid-proxmox/scripts"
UPDATE_SCRIPT="${SCRIPT_DIR}/update-system.sh"

echo "========================================"
echo "Testing Update System Improvements"
echo "========================================"
echo ""

# Test 1: Help output
echo "Test 1: Help output shows new options"
echo "--------------------------------------"
bash "$UPDATE_SCRIPT" --help | grep -E "components=|timeout=|gpu-only"
if [ $? -eq 0 ]; then
    echo "✓ New options visible in help"
else
    echo "✗ New options missing from help"
fi
echo ""

# Test 2: Component-specific updates
echo "Test 2: Component-specific updates (--components)"
echo "------------------------------------------------"
bash "$UPDATE_SCRIPT" --components=waydroid --dry-run 2>&1 | grep -q "Updating Waydroid"
if [ $? -eq 0 ]; then
    echo "✓ --components=waydroid works"
else
    echo "✗ --components=waydroid failed"
fi
echo ""

# Test 3: GPU-only option
echo "Test 3: GPU-only update option"
echo "-------------------------------"
bash "$UPDATE_SCRIPT" --gpu-only --dry-run 2>&1 | grep -q "Checking GPU Drivers"
if [ $? -eq 0 ]; then
    echo "✓ --gpu-only works"
else
    echo "✗ --gpu-only failed"
fi
echo ""

# Test 4: Timestamp logging
echo "Test 4: Timestamp logging"
echo "-------------------------"
bash "$UPDATE_SCRIPT" --dry-run 2>&1 | grep -q "\[2025-"
if [ $? -eq 0 ]; then
    echo "✓ Timestamps present in logs"
else
    echo "✗ Timestamps missing from logs"
fi
echo ""

# Test 5: Timeout option
echo "Test 5: Custom timeout option"
echo "------------------------------"
bash "$UPDATE_SCRIPT" --timeout=1200 --dry-run &>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ --timeout option accepted"
else
    echo "✗ --timeout option failed"
fi
echo ""

# Test 6: Utility functions exist
echo "Test 6: Utility functions defined"
echo "----------------------------------"
for func in check_disk_space run_with_timeout verify_service create_restore_point; do
    grep -q "^${func}()" "$UPDATE_SCRIPT"
    if [ $? -eq 0 ]; then
        echo "✓ Function $func() defined"
    else
        echo "✗ Function $func() missing"
    fi
done
echo ""

# Test 7: Script syntax
echo "Test 7: Script syntax validation"
echo "---------------------------------"
bash -n "$UPDATE_SCRIPT"
if [ $? -eq 0 ]; then
    echo "✓ No syntax errors"
else
    echo "✗ Syntax errors found"
fi
echo ""

# Test 8: Verify all new features in code
echo "Test 8: Code contains new features"
echo "-----------------------------------"
features=(
    "verify_service"
    "run_with_timeout"
    "check_disk_space"
    "create_restore_point"
    "UPDATE_GPU"
    "UPDATE_TIMEOUT"
    "MIN_DISK_SPACE_MB"
    "components="
)

for feature in "${features[@]}"; do
    grep -q "$feature" "$UPDATE_SCRIPT"
    if [ $? -eq 0 ]; then
        echo "✓ Feature: $feature"
    else
        echo "✗ Missing: $feature"
    fi
done
echo ""

echo "========================================"
echo "All Tests Complete"
echo "========================================"
