# Clipboard Sharing - Usage Examples

Real-world usage examples for Waydroid clipboard sharing.

## Installation Examples

### Basic Installation

```bash
# Standard installation with defaults
cd /home/user/waydroid-proxmox
./scripts/setup-clipboard.sh --install

# Expected output:
# ========================================
#   Waydroid Clipboard Sharing Setup
# ========================================
#
# [INFO] Installing Waydroid Clipboard Sharing...
# [INFO] Installing clipboard dependencies...
# [OK] wl-clipboard already installed
# [OK] adb already installed
# ...
# [OK] Clipboard sharing installation complete!
```

### Custom Configuration Installation

```bash
# Install with faster sync (1 second interval)
./scripts/setup-clipboard.sh --install --sync-interval 1

# Install with larger clipboard size (5MB)
./scripts/setup-clipboard.sh --install --max-size 5242880

# Install with both custom settings
./scripts/setup-clipboard.sh --install --sync-interval 1 --max-size 5242880
```

## Daily Usage Examples

### Starting and Stopping

```bash
# Start clipboard sync
waydroid-clipboard start
# Output: Clipboard sync started

# Check if it's running
waydroid-clipboard status
# Output:
# Waydroid Clipboard Sync Status
# ===============================
#
# Service Status:
#   Status: Running
#   Uptime: 2025-01-12 10:30:00
#
# Statistics (today):
#   Wayland -> Android: 15 syncs
#   Android -> Wayland: 12 syncs
#   Errors: 0

# Stop clipboard sync
waydroid-clipboard stop
# Output: Clipboard sync stopped

# Restart clipboard sync
waydroid-clipboard restart
# Output: Clipboard sync restarted
```

### Testing Clipboard Functionality

```bash
# Run comprehensive tests
./scripts/test-clipboard.sh

# Expected output:
# ========================================
#   Waydroid Clipboard Test Suite
# ========================================
#
# ========================================
# Testing Dependencies
# ========================================
#
# ✓ wl-copy installed
# ✓ wl-paste installed
# ✓ adb installed
# ✓ waydroid installed
# ✓ Sync daemon installed
# ✓ Management tool installed
# ...
# Tests run: 25
# Passed: 25
# Failed: 0
#
# Pass rate: 100%
#
# ✓ All tests passed!

# Quick test using management tool
waydroid-clipboard test

# Manual test - copy from Wayland
echo "Hello from Wayland!" | wl-copy
sleep 3
adb shell cmd clipboard get
# Output: Hello from Wayland!

# Manual test - copy from Android
adb shell cmd clipboard put "Hello from Android!"
sleep 3
wl-paste
# Output: Hello from Android!
```

### Viewing Logs and Statistics

```bash
# View recent logs
waydroid-clipboard logs

# Expected output:
# Recent Clipboard Sync Logs:
# ===========================
# [2025-01-12 10:30:15] [INFO] Clipboard sync daemon starting...
# [2025-01-12 10:30:16] [INFO] ADB reconnected successfully
# [2025-01-12 10:30:25] [INFO] Syncing Wayland -> Android (23 bytes)
# [2025-01-12 10:30:25] [INFO] Sync successful
# [2025-01-12 10:31:30] [INFO] Syncing Android -> Wayland (45 bytes)
# [2025-01-12 10:31:30] [INFO] Sync successful

# Follow logs in real-time
journalctl -u waydroid-clipboard-sync -f

# Check for errors
waydroid-clipboard logs | grep ERROR

# View detailed statistics
waydroid-clipboard status
```

## Use Case Examples

### Use Case 1: Copy URL from Browser to Android

**Scenario:** You're browsing on your desktop VNC client and want to open a URL in an Android app.

```bash
# 1. On VNC client: Copy URL from browser
#    (Ctrl+C in browser)

# 2. Wait 2-3 seconds for sync

# 3. In Android (via VNC):
#    - Open any app that accepts URLs (Chrome, email, etc.)
#    - Long press in text field
#    - Select "Paste"
#    - URL appears from clipboard!
```

### Use Case 2: Copy Text from Android App to Host

**Scenario:** You want to copy text from an Android app to use on your host system.

```bash
# 1. In Android app (via VNC):
#    - Select text
#    - Tap "Copy"

# 2. Wait 2-3 seconds for sync

# 3. On host/VNC client:
#    - Paste anywhere (Ctrl+V)
#    - Text from Android appears!
```

### Use Case 3: Share Shopping List

**Scenario:** Create a shopping list in Android notes app, copy to host for editing.

```bash
# 1. Android: Copy shopping list from Notes app
#    (Long press, select all, copy)

# 2. Wait for sync

# 3. Host: Paste into text editor
#    - Edit the list
#    - Copy updated version

# 4. Wait for sync

# 5. Android: Paste updated list back into Notes app
```

### Use Case 4: Development Workflow

**Scenario:** Testing Android app with copied data.

```bash
# 1. Copy test JSON data from host
echo '{"user": "test", "token": "abc123"}' | wl-copy

# 2. Wait for sync (2-3 seconds)

# 3. Paste into Android app for testing
#    App receives the test data

# 4. App generates output, copy from Android

# 5. Verify output on host
wl-paste
```

### Use Case 5: Copying Credentials

**Scenario:** Securely copy passwords from password manager to Android app.

```bash
# 1. Copy password from password manager (via VNC)
#    (Use your password manager's copy function)

# 2. Paste into Android app login field
#    (Long press, paste)

# 3. Clear clipboard for security
echo "" | wl-copy

# Or manually clear cache
waydroid-clipboard clear
```

## Troubleshooting Examples

### Example 1: Clipboard Not Syncing

```bash
# Symptom: Copy/paste not working between environments

# Step 1: Check service status
waydroid-clipboard status
# If shows "Status: Stopped", start it:
waydroid-clipboard start

# Step 2: Check ADB connection
adb devices
# If not showing "localhost:5555    device", reconnect:
adb connect localhost:5555

# Step 3: Run tests
waydroid-clipboard test
# Review any failed tests

# Step 4: Check logs for errors
waydroid-clipboard logs | grep ERROR

# Step 5: Restart service
waydroid-clipboard restart
```

### Example 2: ADB Connection Lost

```bash
# Symptom: Logs show "ADB not connected" errors

# Solution 1: Manual reconnect
adb kill-server
adb start-server
adb connect localhost:5555

# Verify connection
adb devices
# Should show: localhost:5555    device

# Solution 2: Restart Waydroid and clipboard service
systemctl restart waydroid
sleep 5
waydroid-clipboard restart

# Verify sync is working
waydroid-clipboard test
```

### Example 3: Slow Clipboard Sync

```bash
# Symptom: Clipboard takes too long to sync

# Check current sync interval
grep CLIPBOARD_SYNC_INTERVAL /etc/systemd/system/waydroid-clipboard-sync.service
# Shows: Environment="CLIPBOARD_SYNC_INTERVAL=2"

# Reduce interval to 1 second
sudo nano /etc/systemd/system/waydroid-clipboard-sync.service
# Change to: Environment="CLIPBOARD_SYNC_INTERVAL=1"

# Apply changes
systemctl daemon-reload
systemctl restart waydroid-clipboard-sync

# Verify faster sync
echo "test-$(date +%s)" | wl-copy
# Count to 2
adb shell cmd clipboard get
# Should see text faster
```

### Example 4: Large Clipboard Content Not Syncing

```bash
# Symptom: Large text not syncing

# Check logs
waydroid-clipboard logs | grep "too large"
# Shows: [WARN] Wayland clipboard too large (2048576 bytes), skipping

# Check current limit
grep CLIPBOARD_MAX_SIZE /etc/systemd/system/waydroid-clipboard-sync.service
# Shows: Environment="CLIPBOARD_MAX_SIZE=1048576"

# Increase limit to 5MB
sudo nano /etc/systemd/system/waydroid-clipboard-sync.service
# Change to: Environment="CLIPBOARD_MAX_SIZE=5242880"

# Apply changes
systemctl daemon-reload
systemctl restart waydroid-clipboard-sync

# Test with larger content
head -c 2097152 /dev/urandom | base64 | wl-copy
sleep 3
# Should sync now
```

### Example 5: Service Won't Start

```bash
# Symptom: Service fails to start

# Check detailed status
systemctl status waydroid-clipboard-sync -l

# Check for dependency issues
apt-get install wl-clipboard adb inotify-tools

# Check if Waydroid is running
waydroid status
# If not running:
systemctl start waydroid

# Verify script permissions
ls -l /usr/local/bin/waydroid-clipboard-sync.sh
# Should show: -rwxr-xr-x

# If not executable:
chmod +x /usr/local/bin/waydroid-clipboard-sync.sh

# Try starting again
systemctl start waydroid-clipboard-sync

# Check logs
journalctl -u waydroid-clipboard-sync -n 50
```

## Advanced Examples

### Example 1: Monitoring Clipboard Activity

```bash
# Watch clipboard changes in real-time
watch -n 1 'echo "Wayland:"; wl-paste 2>/dev/null | head -c 100; echo -e "\n\nAndroid:"; adb shell cmd clipboard get 2>/dev/null | head -c 100'

# Monitor sync statistics
watch -n 5 'waydroid-clipboard status'

# Count syncs in last hour
journalctl -u waydroid-clipboard-sync --since "1 hour ago" | grep -c "Sync successful"

# View only sync operations from logs
grep "Syncing" /var/log/waydroid-clipboard.log | tail -20
```

### Example 2: Debugging with Enhanced Logging

```bash
# Enable debug mode
waydroid-clipboard debug

# Output:
# Enabling debug logging...
# Debug logging enabled. View logs with: journalctl -u waydroid-clipboard-sync -f

# Watch debug logs
journalctl -u waydroid-clipboard-sync -f

# Now perform clipboard operations and see detailed logs:
echo "test" | wl-copy

# Debug log shows:
# [2025-01-12 10:45:30] [INFO] Wayland clipboard changed
# [2025-01-12 10:45:30] [INFO] Hash: 098f6bcd4621d373cade4e832627b4f6
# [2025-01-12 10:45:30] [INFO] Syncing Wayland -> Android (4 bytes)
# [2025-01-12 10:45:30] [INFO] ADB command: adb shell cmd clipboard put 'test'
# [2025-01-12 10:45:31] [INFO] Sync successful

# Disable debug mode
# Edit service file and change CLIPBOARD_DEBUG=false
sudo nano /etc/systemd/system/waydroid-clipboard-sync.service.d/debug.conf
systemctl daemon-reload
systemctl restart waydroid-clipboard-sync
```

### Example 3: Performance Testing

```bash
# Test sync latency
for i in {1..10}; do
  timestamp=$(date +%s%N)
  echo "test-$timestamp" | wl-copy
  sleep 3
  result=$(adb shell cmd clipboard get)
  if [[ "$result" == *"$timestamp"* ]]; then
    echo "Sync $i: Success"
  else
    echo "Sync $i: Failed"
  fi
done

# Test large clipboard performance
time (head -c 1048576 /dev/urandom | base64 | wl-copy && sleep 3 && adb shell cmd clipboard get >/dev/null)

# Monitor resource usage
systemd-cgtop | grep waydroid-clipboard-sync

# Check memory usage
systemctl show waydroid-clipboard-sync -p MemoryCurrent
```

### Example 4: Integration with Scripts

```bash
#!/bin/bash
# Example: Auto-copy Android device info to host

# Get Android device info
device_info=$(adb shell getprop ro.product.model)
android_version=$(adb shell getprop ro.build.version.release)

# Create formatted output
output="Device: $device_info
Android Version: $android_version"

# Copy to Android clipboard
adb shell cmd clipboard put "$output"

# Wait for sync to host
sleep 3

# Verify it's on host
echo "Clipboard content:"
wl-paste
```

```bash
#!/bin/bash
# Example: Monitor clipboard for URLs and log them

previous_hash=""
while true; do
  current=$(wl-paste 2>/dev/null)
  current_hash=$(echo -n "$current" | md5sum | cut -d' ' -f1)

  if [ "$current_hash" != "$previous_hash" ]; then
    if [[ "$current" =~ ^https?:// ]]; then
      echo "[$(date)] URL detected: $current" >> ~/clipboard-urls.log
    fi
    previous_hash="$current_hash"
  fi

  sleep 2
done
```

### Example 5: Clipboard History

```bash
# Create simple clipboard history (last 10 items)
mkdir -p ~/.clipboard-history

# Monitor and save clipboard changes
previous_hash=""
while true; do
  current=$(wl-paste 2>/dev/null)
  current_hash=$(echo -n "$current" | md5sum | cut -d' ' -f1)

  if [ "$current_hash" != "$previous_hash" ] && [ -n "$current" ]; then
    timestamp=$(date +%Y%m%d-%H%M%S)
    echo "$current" > ~/.clipboard-history/clip-$timestamp.txt

    # Keep only last 10 items
    ls -t ~/.clipboard-history/ | tail -n +11 | xargs -I {} rm ~/.clipboard-history/{}

    previous_hash="$current_hash"
  fi

  sleep 2
done

# View clipboard history
ls -lt ~/.clipboard-history/

# Restore from history
cat ~/.clipboard-history/clip-20250112-103000.txt | wl-copy
```

## Configuration Examples

### Example 1: Change Sync Interval

```bash
# Edit service configuration
sudo nano /etc/systemd/system/waydroid-clipboard-sync.service

# Find and modify:
Environment="CLIPBOARD_SYNC_INTERVAL=2"

# Change to desired interval (in seconds):
# For fast sync (1 second):
Environment="CLIPBOARD_SYNC_INTERVAL=1"

# For slower sync (5 seconds):
Environment="CLIPBOARD_SYNC_INTERVAL=5"

# For very slow sync (10 seconds, low CPU usage):
Environment="CLIPBOARD_SYNC_INTERVAL=10"

# Apply changes
systemctl daemon-reload
systemctl restart waydroid-clipboard-sync

# Verify new interval
waydroid-clipboard status
```

### Example 2: Change Maximum Clipboard Size

```bash
# Edit service configuration
sudo nano /etc/systemd/system/waydroid-clipboard-sync.service

# Find and modify:
Environment="CLIPBOARD_MAX_SIZE=1048576"

# Change to desired size:
# For 5MB:
Environment="CLIPBOARD_MAX_SIZE=5242880"

# For 10MB:
Environment="CLIPBOARD_MAX_SIZE=10485760"

# For 512KB (smaller):
Environment="CLIPBOARD_MAX_SIZE=524288"

# Apply changes
systemctl daemon-reload
systemctl restart waydroid-clipboard-sync

# Test with large content
head -c 2097152 /dev/urandom | base64 | wl-copy
sleep 3
adb shell cmd clipboard get >/dev/null
echo "Sync successful for 2MB content"
```

### Example 3: Enable Auto-start on Boot

```bash
# Enable service to start automatically
systemctl enable waydroid-clipboard-sync

# Verify it's enabled
systemctl is-enabled waydroid-clipboard-sync
# Output: enabled

# Disable auto-start if needed
systemctl disable waydroid-clipboard-sync
```

## Uninstallation Example

```bash
# Stop the service
waydroid-clipboard stop

# Uninstall completely
./scripts/setup-clipboard.sh --uninstall

# Expected output:
# [INFO] Uninstalling Waydroid Clipboard Sharing...
# [OK] Clipboard sharing uninstalled

# Verify removal
systemctl status waydroid-clipboard-sync
# Output: Unit waydroid-clipboard-sync.service could not be found.

which waydroid-clipboard
# Output: (empty - command not found)

ls /var/lib/waydroid-clipboard/
# Output: No such file or directory
```

## Summary

This document provides practical examples for:
- Installation and configuration
- Daily usage patterns
- Troubleshooting scenarios
- Advanced monitoring
- Script integration
- Performance testing
- Configuration changes

For complete documentation, see:
- `docs/CLIPBOARD-SHARING.md` - Full documentation
- `docs/CLIPBOARD-QUICK-REFERENCE.md` - Quick reference
- `CLIPBOARD-IMPLEMENTATION-SUMMARY.md` - Technical overview
