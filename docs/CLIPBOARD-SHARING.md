# Clipboard Sharing for Waydroid

This document describes the clipboard sharing functionality that enables bidirectional clipboard synchronization between the host/VNC and Android in Waydroid.

## Overview

The clipboard sharing system provides seamless copy-paste functionality across three environments:

1. **Wayland (Host)** - The Wayland compositor running in the LXC container
2. **VNC Client** - Remote desktop client connecting via VNC
3. **Android (Waydroid)** - The Android system running in Waydroid

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    VNC Client                           │
│                  (Remote Desktop)                       │
└─────────────────────┬───────────────────────────────────┘
                      │ VNC Protocol
                      │ (Native Clipboard Support)
                      ▼
┌─────────────────────────────────────────────────────────┐
│              LXC Container (Wayland)                    │
│  ┌─────────────────────────────────────────────────┐   │
│  │           WayVNC Server                         │   │
│  │  (Handles VNC ↔ Wayland Clipboard)              │   │
│  └─────────────────┬───────────────────────────────┘   │
│                    │                                    │
│  ┌─────────────────▼───────────────────────────────┐   │
│  │        Wayland Clipboard (wl-clipboard)         │   │
│  │        - wl-copy (set clipboard)                │   │
│  │        - wl-paste (get clipboard)               │   │
│  └─────────────────┬───────────────────────────────┘   │
│                    │                                    │
│  ┌─────────────────▼───────────────────────────────┐   │
│  │    Clipboard Sync Daemon                        │   │
│  │    (Bidirectional Sync Service)                 │   │
│  │    - Monitors clipboard changes                 │   │
│  │    - Hash-based change detection                │   │
│  │    - Loop prevention                            │   │
│  │    - Error handling & reconnection              │   │
│  └─────────────────┬───────────────────────────────┘   │
│                    │ ADB (Android Debug Bridge)         │
│                    ▼                                    │
│  ┌──────────────────────────────────────────────────┐  │
│  │         Waydroid Android System                  │  │
│  │         - Android Clipboard Service              │  │
│  │         - cmd clipboard get/put                  │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Features

### Core Functionality

- **Bidirectional Sync**: Copy from any source, paste to any destination
- **Automatic Detection**: Monitors clipboard changes in real-time
- **Loop Prevention**: Intelligent hash-based tracking prevents sync loops
- **Size Limits**: Configurable maximum clipboard size (default 1MB)
- **Performance**: Adjustable sync interval (default 2 seconds)

### Integration Points

1. **Wayland Clipboard** (wl-clipboard)
   - Uses `wl-copy` to set clipboard content
   - Uses `wl-paste` to read clipboard content
   - Works with any Wayland application

2. **VNC Clipboard** (WayVNC)
   - Native clipboard support via VNC protocol
   - No additional configuration needed
   - Works with any VNC client that supports clipboard

3. **Android Clipboard** (ADB)
   - Uses `adb shell cmd clipboard` for modern Android (API 29+)
   - Fallback methods for older Android versions
   - Automatic reconnection on connection loss

### Advanced Features

- **Error Recovery**: Automatic reconnection and error handling
- **Logging**: Detailed sync logs with timestamps
- **Statistics**: Track sync operations and errors
- **Debug Mode**: Enable verbose logging for troubleshooting
- **Cache Management**: Efficient clipboard content caching
- **Security**: Size limits and input validation

## Installation

### Prerequisites

- Waydroid installed and running
- WayVNC configured for remote access
- Root access to the LXC container

### Quick Install

```bash
# Inside the LXC container
cd /root/waydroid-proxmox
./scripts/setup-clipboard.sh --install
```

### Custom Configuration

```bash
# Install with custom sync interval (5 seconds)
./scripts/setup-clipboard.sh --install --sync-interval 5

# Install with custom max size (5MB)
./scripts/setup-clipboard.sh --install --max-size 5242880
```

### What Gets Installed

The installation creates:

1. **Dependencies**
   - `wl-clipboard` - Wayland clipboard tools
   - `adb` - Android Debug Bridge
   - `inotify-tools` - File system monitoring
   - `socat` - Socket operations

2. **System Components**
   - `/usr/local/bin/waydroid-clipboard-sync.sh` - Sync daemon
   - `/usr/local/bin/waydroid-clipboard` - Management tool
   - `/etc/systemd/system/waydroid-clipboard-sync.service` - Systemd service

3. **Configuration & Data**
   - `/var/lib/waydroid-clipboard/` - Cache directory
   - `/var/log/waydroid-clipboard.log` - Sync logs
   - `/etc/logrotate.d/waydroid-clipboard` - Log rotation config

## Usage

### Starting Clipboard Sync

```bash
# Enable and start the service
waydroid-clipboard start

# Check if it's running
waydroid-clipboard status
```

### Testing Clipboard

```bash
# Run comprehensive clipboard tests
waydroid-clipboard test
```

This will test:
1. Dependencies (wl-copy, wl-paste, adb)
2. ADB connection to Android
3. Wayland clipboard read/write
4. Android clipboard read/write
5. Bidirectional sync (if service is running)

### Viewing Status & Logs

```bash
# Show detailed status
waydroid-clipboard status

# View recent sync logs
waydroid-clipboard logs

# Follow logs in real-time
journalctl -u waydroid-clipboard-sync -f
```

### Management Commands

```bash
# Start clipboard sync
waydroid-clipboard start

# Stop clipboard sync
waydroid-clipboard stop

# Restart clipboard sync
waydroid-clipboard restart

# Show status and statistics
waydroid-clipboard status

# View sync logs
waydroid-clipboard logs

# Test clipboard functionality
waydroid-clipboard test

# Clear clipboard cache
waydroid-clipboard clear

# Enable debug logging
waydroid-clipboard debug

# Show help
waydroid-clipboard help
```

## Configuration

### Sync Interval

The sync interval determines how frequently the daemon checks for clipboard changes.

- **Default**: 2 seconds
- **Range**: 1-60 seconds
- **Recommendation**:
  - 2 seconds for responsive syncing
  - 5 seconds for lower CPU usage
  - 1 second for ultra-responsive (higher CPU)

**Change interval after installation:**

Edit `/etc/systemd/system/waydroid-clipboard-sync.service`:
```ini
Environment="CLIPBOARD_SYNC_INTERVAL=5"
```

Then reload and restart:
```bash
systemctl daemon-reload
systemctl restart waydroid-clipboard-sync
```

### Maximum Clipboard Size

Prevents syncing of extremely large clipboard content.

- **Default**: 1,048,576 bytes (1MB)
- **Range**: 1KB - 10MB
- **Recommendation**: 1-2MB for general use

**Change max size after installation:**

Edit `/etc/systemd/system/waydroid-clipboard-sync.service`:
```ini
Environment="CLIPBOARD_MAX_SIZE=2097152"
```

### Debug Logging

Enable detailed logging for troubleshooting:

```bash
waydroid-clipboard debug
```

Or manually edit the service file:
```ini
Environment="CLIPBOARD_DEBUG=true"
```

## How It Works

### Sync Process

1. **Change Detection**
   - Daemon polls both Wayland and Android clipboards
   - Calculates MD5 hash of clipboard content
   - Compares with cached hash to detect changes

2. **Sync Decision**
   - If Wayland clipboard changed: sync to Android
   - If Android clipboard changed: sync to Wayland
   - If both changed: last change wins

3. **Loop Prevention**
   - Tracks hash of last synced content
   - Prevents syncing content that was just received
   - Avoids infinite sync loops

4. **Error Handling**
   - Automatic ADB reconnection on disconnect
   - Error counter with automatic shutdown on repeated failures
   - Timeout protection for all operations

### VNC Integration

WayVNC provides native clipboard support:

```
VNC Client Copy
      ↓
VNC Protocol (clipboard extension)
      ↓
WayVNC Server
      ↓
Wayland Clipboard (wl-copy)
      ↓
Clipboard Sync Daemon
      ↓
Android Clipboard (adb shell)
```

Paste operations work in reverse.

### ADB Connection

The daemon maintains a persistent ADB connection:

- **Initial Setup**: Connects to `localhost:5555`
- **Health Checks**: Verifies connection before each operation
- **Auto Reconnect**: Reconnects if connection is lost
- **Fallback Methods**: Supports multiple Android clipboard APIs

## Troubleshooting

### Clipboard Not Syncing

**Check service status:**
```bash
waydroid-clipboard status
```

**Check logs for errors:**
```bash
waydroid-clipboard logs
```

**Common issues:**

1. **ADB not connected**
   ```bash
   # Manually connect ADB
   adb kill-server
   adb start-server
   adb connect localhost:5555
   ```

2. **Waydroid not running**
   ```bash
   systemctl status waydroid
   systemctl start waydroid
   ```

3. **Service not running**
   ```bash
   waydroid-clipboard start
   ```

### Slow Clipboard Sync

If clipboard sync feels sluggish:

1. **Reduce sync interval** (increases CPU usage):
   ```bash
   # Edit service file
   nano /etc/systemd/system/waydroid-clipboard-sync.service
   # Change CLIPBOARD_SYNC_INTERVAL to 1
   systemctl daemon-reload
   systemctl restart waydroid-clipboard-sync
   ```

2. **Check system load**:
   ```bash
   top
   # Look for high CPU usage
   ```

### Large Clipboard Content Not Syncing

Content larger than max size is skipped:

```bash
# Check logs for "too large" messages
waydroid-clipboard logs | grep "too large"

# Increase max size if needed
nano /etc/systemd/system/waydroid-clipboard-sync.service
# Change CLIPBOARD_MAX_SIZE to larger value
```

### ADB Connection Lost

If ADB keeps disconnecting:

1. **Check Waydroid ADB settings**:
   ```bash
   waydroid shell getprop service.adb.tcp.port
   # Should show: 5555
   ```

2. **Manually restart ADB in Waydroid**:
   ```bash
   waydroid shell setprop service.adb.tcp.port 5555
   waydroid shell stop adbd
   waydroid shell start adbd
   adb connect localhost:5555
   ```

3. **Check for port conflicts**:
   ```bash
   netstat -tuln | grep 5555
   ```

### VNC Clipboard Not Working

VNC clipboard is handled separately by WayVNC:

1. **Verify wl-clipboard is installed**:
   ```bash
   which wl-copy wl-paste
   ```

2. **Check VNC client settings**:
   - Ensure clipboard sharing is enabled in VNC client
   - Some clients call it "clipboard synchronization"

3. **Test Wayland clipboard directly**:
   ```bash
   echo "test" | wl-copy
   wl-paste
   ```

### Service Won't Start

**Check service errors:**
```bash
systemctl status waydroid-clipboard-sync -l
journalctl -u waydroid-clipboard-sync -n 50
```

**Common issues:**

1. **Missing dependencies**:
   ```bash
   apt-get install wl-clipboard adb inotify-tools
   ```

2. **Permission issues**:
   ```bash
   chmod +x /usr/local/bin/waydroid-clipboard-sync.sh
   ```

3. **Invalid configuration**:
   ```bash
   systemd-analyze verify waydroid-clipboard-sync.service
   ```

## Performance Optimization

### CPU Usage

The sync daemon uses minimal CPU:
- **Idle**: < 0.1% CPU
- **Active sync**: < 1% CPU
- **Polling**: Configurable interval reduces overhead

**Reduce CPU usage:**
- Increase sync interval to 5-10 seconds
- Reduce max clipboard size
- Disable debug logging

### Memory Usage

Memory footprint is minimal:
- **Base**: ~5-10MB RAM
- **Cache**: ~1-2MB (depends on clipboard content)
- **Total**: ~10-15MB RAM

### Network Impact

Minimal network usage:
- ADB uses local loopback (localhost)
- No external network traffic
- Bandwidth: < 1KB/s average

## Security Considerations

### Clipboard Privacy

- Clipboard content is stored temporarily in `/var/lib/waydroid-clipboard/`
- Cache directory has restrictive permissions (700)
- Logs may contain clipboard metadata (but not content)

**Clear sensitive data:**
```bash
waydroid-clipboard clear
```

### ADB Security

- ADB connection is local only (localhost:5555)
- No network exposure by default
- Consider firewall rules if exposing ADB externally

### Size Limits

- Default 1MB limit prevents clipboard bombs
- Adjust based on your needs and security requirements
- Very large clipboards can impact performance

## Advanced Usage

### Custom Sync Logic

The sync daemon can be customized by editing:
```bash
/usr/local/bin/waydroid-clipboard-sync.sh
```

**Example modifications:**

1. **Filter clipboard content**:
   Add filtering before sync operations

2. **Add clipboard history**:
   Store multiple clipboard entries

3. **Selective sync**:
   Only sync specific content types

### Integration with Other Tools

**Use with clipboard managers:**

The sync daemon works alongside clipboard managers:
- wl-clip-persist
- clipman
- cliphist

**Programmatic access:**

```bash
# Read current clipboard
wl-paste

# Set clipboard
echo "content" | wl-copy

# Android clipboard
adb shell cmd clipboard get
adb shell cmd clipboard put "content"
```

### Monitoring & Alerting

**Watch sync activity:**
```bash
watch -n 1 'waydroid-clipboard status'
```

**Alert on errors:**
```bash
journalctl -u waydroid-clipboard-sync -f | \
  grep --line-buffered "ERROR" | \
  while read line; do
    echo "Clipboard error: $line"
    # Send notification, email, etc.
  done
```

## Uninstallation

### Remove Clipboard Sharing

```bash
# Stop and remove
./scripts/setup-clipboard.sh --uninstall
```

This removes:
- Systemd service
- Sync daemon script
- Management tools
- Cache directory
- Log files

### Keep Dependencies

Dependencies (wl-clipboard, adb) are not automatically removed.

**Manual removal if needed:**
```bash
apt-get remove wl-clipboard adb inotify-tools
apt-get autoremove
```

## FAQ

### Q: Does this work with image clipboard?

**A:** Currently, only text clipboard is supported. Image support would require significant additional complexity.

### Q: What happens if I copy large files?

**A:** Content larger than the max size (default 1MB) is ignored and logged. Adjust max size if needed.

### Q: Can I sync clipboard over network?

**A:** Yes, VNC clipboard works over network automatically. The sync daemon handles local Wayland ↔ Android sync.

### Q: Does this affect battery life?

**A:** Minimal impact. The daemon polls every 2 seconds but operations are very lightweight.

### Q: Can I use this with multiple Android instances?

**A:** Currently supports one Waydroid instance per container. Multiple instances would need separate ADB ports.

### Q: What Android versions are supported?

**A:** Android 10 (API 29)+ fully supported. Older versions may work with limited functionality.

### Q: Is clipboard encrypted?

**A:** Local clipboard (Wayland ↔ Android) is not encrypted. VNC clipboard encryption depends on your VNC setup (use TLS/VeNCrypt).

## Technical Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLIPBOARD_SYNC_INTERVAL` | 2 | Sync check interval (seconds) |
| `CLIPBOARD_MAX_SIZE` | 1048576 | Max clipboard size (bytes) |
| `CLIPBOARD_CACHE_DIR` | /var/lib/waydroid-clipboard | Cache directory |
| `CLIPBOARD_LOG` | /var/log/waydroid-clipboard.log | Log file path |
| `CLIPBOARD_DEBUG` | false | Enable debug logging |

### File Locations

| Path | Purpose |
|------|---------|
| `/usr/local/bin/waydroid-clipboard-sync.sh` | Sync daemon |
| `/usr/local/bin/waydroid-clipboard` | Management CLI |
| `/etc/systemd/system/waydroid-clipboard-sync.service` | Systemd service |
| `/var/lib/waydroid-clipboard/` | Cache directory |
| `/var/log/waydroid-clipboard.log` | Sync logs |
| `/etc/logrotate.d/waydroid-clipboard` | Log rotation |

### ADB Commands Used

| Command | Purpose |
|---------|---------|
| `adb devices` | List connected devices |
| `adb connect localhost:5555` | Connect to Waydroid |
| `adb shell cmd clipboard get` | Read Android clipboard |
| `adb shell cmd clipboard put <text>` | Write Android clipboard |
| `adb kill-server` | Stop ADB server |
| `adb start-server` | Start ADB server |

### Wayland Commands Used

| Command | Purpose |
|---------|---------|
| `wl-paste` | Read Wayland clipboard |
| `wl-copy` | Write Wayland clipboard |

## Credits

- **wl-clipboard**: Wayland clipboard utilities
- **ADB**: Android Debug Bridge
- **WayVNC**: VNC server for Wayland

## License

MIT License - Part of the waydroid-proxmox project

## Support

- **Issues**: Report bugs on GitHub
- **Discussions**: Ask questions on GitHub Discussions
- **Logs**: Include logs when reporting issues (`waydroid-clipboard logs`)
