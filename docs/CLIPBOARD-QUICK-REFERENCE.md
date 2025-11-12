# Clipboard Sharing Quick Reference

Quick commands and troubleshooting for Waydroid clipboard sharing.

## Installation

```bash
# Install clipboard sharing
./scripts/setup-clipboard.sh --install

# Install with custom settings
./scripts/setup-clipboard.sh --install --sync-interval 5 --max-size 2097152
```

## Daily Usage

```bash
# Start clipboard sync
waydroid-clipboard start

# Stop clipboard sync
waydroid-clipboard stop

# Restart clipboard sync
waydroid-clipboard restart

# Check status
waydroid-clipboard status

# View logs
waydroid-clipboard logs

# Test functionality
waydroid-clipboard test
```

## Sync Flow

```
┌─────────────┐
│  VNC Client │
│   (Copy)    │
└──────┬──────┘
       │ VNC Protocol
       ▼
┌─────────────┐
│   WayVNC    │
└──────┬──────┘
       │
       ▼
┌─────────────┐      ┌──────────────┐
│   Wayland   │◄────►│ Sync Daemon  │
│  Clipboard  │      │  (Auto Sync) │
└─────────────┘      └──────┬───────┘
                            │ ADB
                            ▼
                     ┌──────────────┐
                     │   Android    │
                     │  Clipboard   │
                     └──────────────┘
```

## Common Tasks

### Test Clipboard

```bash
# Full test suite
waydroid-clipboard test

# Manual test - Wayland to Android
echo "test from wayland" | wl-copy
# Wait 2-3 seconds for sync
adb shell cmd clipboard get

# Manual test - Android to Wayland
adb shell cmd clipboard put "test from android"
# Wait 2-3 seconds for sync
wl-paste
```

### View Sync Statistics

```bash
# Show detailed status
waydroid-clipboard status

# Watch real-time sync activity
journalctl -u waydroid-clipboard-sync -f

# Count today's syncs
grep $(date +%Y-%m-%d) /var/log/waydroid-clipboard.log | \
  grep "Syncing" | wc -l
```

### Troubleshoot Sync Issues

```bash
# 1. Check service
systemctl status waydroid-clipboard-sync

# 2. Check ADB connection
adb devices
# Should show: localhost:5555    device

# 3. Reconnect ADB if needed
adb kill-server && adb start-server && adb connect localhost:5555

# 4. Check logs for errors
waydroid-clipboard logs | grep ERROR

# 5. Restart service
waydroid-clipboard restart
```

### Clear Clipboard Cache

```bash
# Clear cache (useful if clipboard stuck)
waydroid-clipboard clear

# Manual cache clear
rm -rf /var/lib/waydroid-clipboard/*
systemctl restart waydroid-clipboard-sync
```

## Configuration Files

```bash
# Systemd service
/etc/systemd/system/waydroid-clipboard-sync.service

# Sync daemon script
/usr/local/bin/waydroid-clipboard-sync.sh

# Management tool
/usr/local/bin/waydroid-clipboard

# Cache directory
/var/lib/waydroid-clipboard/

# Log file
/var/log/waydroid-clipboard.log
```

## Quick Configuration Changes

### Change Sync Interval

```bash
# Edit service file
nano /etc/systemd/system/waydroid-clipboard-sync.service

# Change this line:
Environment="CLIPBOARD_SYNC_INTERVAL=2"
# To (for 5 second interval):
Environment="CLIPBOARD_SYNC_INTERVAL=5"

# Apply changes
systemctl daemon-reload
systemctl restart waydroid-clipboard-sync
```

### Change Max Clipboard Size

```bash
# Edit service file
nano /etc/systemd/system/waydroid-clipboard-sync.service

# Change this line:
Environment="CLIPBOARD_MAX_SIZE=1048576"
# To (for 5MB):
Environment="CLIPBOARD_MAX_SIZE=5242880"

# Apply changes
systemctl daemon-reload
systemctl restart waydroid-clipboard-sync
```

### Enable Debug Logging

```bash
# Quick enable
waydroid-clipboard debug

# Or manually
mkdir -p /etc/systemd/system/waydroid-clipboard-sync.service.d
cat > /etc/systemd/system/waydroid-clipboard-sync.service.d/debug.conf <<EOF
[Service]
Environment="CLIPBOARD_DEBUG=true"
EOF

systemctl daemon-reload
systemctl restart waydroid-clipboard-sync

# View debug logs
journalctl -u waydroid-clipboard-sync -f
```

## Troubleshooting Flowchart

```
Clipboard not syncing?
        │
        ├─► Is service running?
        │   ├─ No  → waydroid-clipboard start
        │   └─ Yes → Continue
        │
        ├─► Is ADB connected?
        │   ├─ No  → adb connect localhost:5555
        │   └─ Yes → Continue
        │
        ├─► Is Waydroid running?
        │   ├─ No  → systemctl start waydroid
        │   └─ Yes → Continue
        │
        ├─► Any errors in logs?
        │   ├─ Yes → waydroid-clipboard logs
        │   └─ No  → Continue
        │
        └─► Try restart
            └─ waydroid-clipboard restart
```

## Error Messages & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| "ADB not connected" | ADB connection lost | `adb connect localhost:5555` |
| "WAYLAND_DISPLAY not set" | Not in Wayland session | Check Wayland is running |
| "clipboard too large" | Content > max size | Increase max size or copy less data |
| "Failed to set Android clipboard" | ADB issue or Android not ready | Restart Waydroid, reconnect ADB |
| "timeout" | Operation took too long | Check system load, restart service |

## Performance Tuning

### Low CPU Usage (Slower Sync)
```bash
# Set interval to 10 seconds
Environment="CLIPBOARD_SYNC_INTERVAL=10"
```

### Fast Sync (Higher CPU)
```bash
# Set interval to 1 second
Environment="CLIPBOARD_SYNC_INTERVAL=1"
```

### Balanced (Default)
```bash
# Set interval to 2 seconds
Environment="CLIPBOARD_SYNC_INTERVAL=2"
```

## Service Management

```bash
# Enable auto-start on boot
systemctl enable waydroid-clipboard-sync

# Disable auto-start
systemctl disable waydroid-clipboard-sync

# Check if enabled
systemctl is-enabled waydroid-clipboard-sync

# Check if active
systemctl is-active waydroid-clipboard-sync

# View full status
systemctl status waydroid-clipboard-sync -l

# View recent logs
journalctl -u waydroid-clipboard-sync -n 50

# Follow logs
journalctl -u waydroid-clipboard-sync -f
```

## Manual Operations

### Directly Access Clipboards

```bash
# Read Wayland clipboard
wl-paste

# Write Wayland clipboard
echo "content" | wl-copy

# Read Android clipboard
adb shell cmd clipboard get

# Write Android clipboard
adb shell cmd clipboard put "content"
```

### Check Clipboard State

```bash
# View cached clipboard hashes
cat /var/lib/waydroid-clipboard/wayland_hash
cat /var/lib/waydroid-clipboard/android_hash

# View cached clipboard content
cat /var/lib/waydroid-clipboard/wayland_last
cat /var/lib/waydroid-clipboard/android_last
```

## Useful One-Liners

```bash
# Count syncs in last hour
journalctl -u waydroid-clipboard-sync --since "1 hour ago" | \
  grep -c "Sync successful"

# Show only errors from today
grep $(date +%Y-%m-%d) /var/log/waydroid-clipboard.log | grep ERROR

# Watch clipboard changes live
watch -n 1 'echo "Wayland:"; wl-paste 2>/dev/null | head -c 100; \
  echo -e "\nAndroid:"; adb shell cmd clipboard get 2>/dev/null | head -c 100'

# Test sync latency
echo "test-$(date +%s)" | wl-copy && \
  sleep 3 && \
  adb shell cmd clipboard get

# Monitor service resources
systemd-cgtop | grep waydroid-clipboard-sync
```

## Uninstallation

```bash
# Full uninstall
./scripts/setup-clipboard.sh --uninstall

# Verify removal
systemctl status waydroid-clipboard-sync  # Should show "not found"
which waydroid-clipboard  # Should return nothing
```

## Integration with Other Tools

### Home Assistant

```yaml
# Example: Get Android clipboard in Home Assistant
shell_command:
  get_android_clipboard: >
    ssh root@<container-ip>
    'adb -s localhost:5555 shell cmd clipboard get'
```

### Scripts

```bash
#!/bin/bash
# Example: Monitor clipboard for specific content

while true; do
  content=$(wl-paste 2>/dev/null)
  if [[ "$content" == *"trigger-word"* ]]; then
    echo "Trigger detected in clipboard!"
    # Do something
  fi
  sleep 2
done
```

## Best Practices

1. **Regular Testing**: Run `waydroid-clipboard test` periodically
2. **Monitor Logs**: Check logs weekly for errors
3. **Keep Updated**: Update dependencies with system updates
4. **Size Limits**: Don't copy extremely large content
5. **Security**: Clear clipboard cache if handling sensitive data

## Getting Help

```bash
# Show help
waydroid-clipboard help

# Show setup script help
./scripts/setup-clipboard.sh --help

# Check service logs for detailed errors
journalctl -u waydroid-clipboard-sync -n 100 --no-pager
```

## References

- Full Documentation: `docs/CLIPBOARD-SHARING.md`
- Project README: `README.md`
- VNC Enhancements: `docs/VNC-ENHANCEMENTS.md`
