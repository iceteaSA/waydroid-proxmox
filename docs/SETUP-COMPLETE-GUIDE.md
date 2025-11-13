# Complete Setup Guide

## Overview

The `setup-complete.sh` script is a master orchestration tool that provides a guided, menu-driven interface for applying all Waydroid Proxmox enhancements in the correct order with comprehensive error handling and reporting.

## Features

- **Interactive Menu-Driven Interface** - Easy-to-use menu for selecting enhancements
- **Non-Interactive Automation** - Configuration file support for automated deployments
- **Dry-Run Mode** - Preview all changes before applying
- **Prerequisite Checking** - Validates requirements before execution
- **Progress Tracking** - Real-time progress updates during execution
- **Error Handling** - Graceful error recovery with detailed error messages
- **Configuration Management** - Save and load configurations for reuse
- **Comprehensive Reporting** - Detailed execution logs and summaries
- **Environment Detection** - Automatically detects host vs container environment

## Available Enhancements

### 1. LXC Performance Tuning
**What it does:**
- Optimizes container cgroup settings (CPU, memory, I/O)
- Configures security capabilities
- Sets up resource monitoring
- Applies NUMA and performance optimizations

**Runs on:** Proxmox host
**Requirements:** Container ID (CTID), pct access
**Script:** `scripts/tune-lxc.sh`

### 2. VNC Security Enhancement
**What it does:**
- Configures password authentication with systemd credentials
- Optional TLS encryption with self-signed certificates
- Connection rate limiting via iptables
- Performance optimization (FPS, quality settings)
- Connection monitoring and logging

**Runs in:** LXC container
**Requirements:** WayVNC installed
**Script:** `scripts/enhance-vnc.sh`

### 3. Audio Passthrough
**What it does:**
- Auto-detects PulseAudio or PipeWire on host
- Configures device passthrough (/dev/snd)
- Sets up audio socket bind mounts
- Configures Waydroid audio properties
- Tests audio functionality

**Runs on:** Host (configures both host and container)
**Requirements:** Container ID, audio system on host
**Script:** `scripts/setup-audio.sh`

### 4. Clipboard Sharing
**What it does:**
- Bidirectional clipboard sync (Wayland ↔ Android)
- VNC clipboard integration
- ADB-based Android clipboard access
- Automatic conflict resolution
- Systemd service for background sync

**Runs in:** LXC container
**Requirements:** Waydroid running, ADB access
**Script:** `scripts/setup-clipboard.sh`

### 5. App Installation
**What it does:**
- Install APKs from local files
- Download and install from URLs
- F-Droid repository integration
- Batch installation from config files
- APK verification and signature checking

**Runs in:** LXC container
**Requirements:** Waydroid initialized and running
**Script:** `scripts/install-apps.sh`

## Usage Modes

### Interactive Mode (Recommended for first-time setup)

Simply run the script without arguments to launch the interactive menu:

```bash
./scripts/setup-complete.sh
```

**Interactive Menu Features:**
- Toggle enhancements on/off with number keys
- Configure options for each enhancement
- Check prerequisites before running
- Save/load configurations
- Run or dry-run selected enhancements

### Non-Interactive (Automated) Mode

Use a configuration file for automated, repeatable deployments:

```bash
# Copy example configuration
cp config/setup-example.conf config/my-setup.conf

# Edit configuration
nano config/my-setup.conf

# Run automated setup
./scripts/setup-complete.sh --auto --config config/my-setup.conf
```

### Dry-Run Mode

Preview all changes without applying them:

```bash
# Interactive dry-run
./scripts/setup-complete.sh --dry-run

# Automated dry-run
./scripts/setup-complete.sh --auto --config config/my-setup.conf --dry-run
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `--help` | Show comprehensive help message |
| `--auto` | Enable automatic (non-interactive) mode |
| `--dry-run` | Preview changes without applying |
| `--config <file>` | Load configuration from file |
| `--save-config <file>` | Save current configuration to file |
| `--skip-confirm` | Skip confirmation prompts |
| `--ctid <id>` | Set container ID for LXC/audio operations |
| `--report <file>` | Specify custom report output file |

## Configuration File Format

Configuration files use simple `key=value` format:

```bash
# Enhancement selections (true/false)
select_lxc=true
select_vnc=true
select_audio=true
select_clipboard=true
select_apps=false

# Options
lxc_ctid=100
vnc_enable_tls=false
vnc_enable_monitoring=true
vnc_fps=60
audio_system=auto
clipboard_interval=2
apps_config=/path/to/apps.yaml
```

See `config/setup-example.conf` for a complete example with detailed comments.

## Execution Order

The script automatically executes enhancements in the correct order:

1. **LXC Performance Tuning** (must run first on host)
2. **Audio Passthrough** (requires host access)
3. **VNC Security Enhancement** (container-based)
4. **Clipboard Sharing** (container-based)
5. **App Installation** (container-based, runs last)

This order ensures dependencies are satisfied and configuration is applied correctly.

## Prerequisite Checking

Before execution, the script validates:

### General Prerequisites
- Correct execution environment (host vs container)
- Required script files present
- Necessary system commands available

### Per-Enhancement Prerequisites

**LXC Tuning:**
- Running on Proxmox host (`pct` and `pveversion` available)
- Valid container ID provided
- Container exists and is accessible

**VNC Enhancement:**
- WayVNC installed in container
- Configuration directory writable

**Audio Setup:**
- Running on Proxmox host
- Audio system detected (PulseAudio or PipeWire)
- Valid container ID
- Audio devices present

**Clipboard Sharing:**
- Waydroid installed in container
- wl-clipboard available
- ADB installed

**App Installation:**
- Waydroid installed and initialized
- Waydroid container running
- App config file exists (if specified)

## Output and Reporting

The script generates detailed reports in `/var/log/waydroid-setup/`:

### Execution Log
Full detailed log of all operations:
```
/var/log/waydroid-setup/setup-report-YYYYMMDD-HHMMSS.txt
```

### Summary Report
Concise summary with results and statistics:
```
/var/log/waydroid-setup/setup-report-YYYYMMDD-HHMMSS-summary.txt
```

### Summary Contents
- Execution date and duration
- Status of each enhancement (success/failed/skipped)
- Execution time per enhancement
- Success/failure statistics
- Next steps and recommendations
- Troubleshooting guidance

## Example Workflows

### First-Time Setup (Interactive)

1. Run the script:
   ```bash
   ./scripts/setup-complete.sh
   ```

2. In the menu:
   - Select desired enhancements (1-5)
   - Press 'o' to configure options (set CTID, etc.)
   - Press 'c' to check prerequisites
   - Press 'r' to run selected enhancements

3. Review the summary report

### Dry-Run Before Applying

```bash
# Interactive with dry-run
./scripts/setup-complete.sh --dry-run

# Or with config file
./scripts/setup-complete.sh --auto --config my-setup.conf --dry-run
```

### Automated Deployment

1. Create configuration file:
   ```bash
   cp config/setup-example.conf config/production.conf
   nano config/production.conf
   ```

2. Test with dry-run:
   ```bash
   ./scripts/setup-complete.sh --auto --config config/production.conf --dry-run
   ```

3. Apply changes:
   ```bash
   ./scripts/setup-complete.sh --auto --config config/production.conf
   ```

### Selective Enhancement Application

Only apply specific enhancements:

```bash
# Configuration file
cat > config/audio-only.conf << EOF
select_lxc=false
select_vnc=false
select_audio=true
select_clipboard=false
select_apps=false
lxc_ctid=100
audio_system=pipewire
EOF

# Run
./scripts/setup-complete.sh --auto --config config/audio-only.conf
```

### Save Configuration for Reuse

```bash
# Interactive mode - configure in menu, then save
./scripts/setup-complete.sh
# In menu: configure options, then press 's' to save

# Or save current settings
./scripts/setup-complete.sh --save-config config/my-saved-config.conf
```

## Error Handling

The script includes comprehensive error handling:

- **Prerequisite Failures**: Script stops and reports missing requirements
- **Execution Errors**: Each enhancement failure is caught and logged
- **Partial Success**: Script continues even if one enhancement fails
- **Error Recovery**: Detailed error messages help diagnose issues
- **Exit Codes**: Non-zero exit code if any enhancement fails

## Environment Detection

The script automatically detects its execution environment:

| Environment | Detection Method | Enabled Operations |
|-------------|------------------|-------------------|
| Proxmox Host | `pct` and `pveversion` commands | LXC tuning, audio (host side) |
| LXC Container | `/proc/1/environ` contains `container=lxc` | VNC, audio (container side), clipboard, apps |
| Unknown | Neither detection succeeds | Warning issued, limited operations |

## Advanced Usage

### Running Individual Scripts

While `setup-complete.sh` provides orchestration, you can run individual scripts:

```bash
# LXC tuning
./scripts/tune-lxc.sh --dry-run 100

# VNC enhancement
./scripts/enhance-vnc.sh --enable-tls --enable-monitoring

# Audio setup
./scripts/setup-audio.sh --force-pipewire 100

# Clipboard
./scripts/setup-clipboard.sh --install --sync-interval 2

# Apps
./scripts/install-apps.sh install-fdroid org.fdroid.fdroid
```

### Combining with Other Tools

```bash
# Run setup, then check health
./scripts/setup-complete.sh --auto --config my-setup.conf
./scripts/health-check.sh

# Setup with immediate testing
./scripts/setup-complete.sh && ./scripts/test-setup.sh
```

## Troubleshooting

### "Prerequisites check failed"

Check the detailed error messages. Common issues:
- Wrong environment (host vs container)
- Missing container ID
- Waydroid not running
- Missing required commands

Solution: Review error messages and ensure prerequisites are met.

### "Script not found" errors

Ensure you're running from the correct directory:

```bash
cd /path/to/waydroid-proxmox
./scripts/setup-complete.sh
```

Or use absolute paths in config files.

### Enhancements fail with permission errors

Some operations require root:

```bash
sudo ./scripts/setup-complete.sh
```

### Dry-run shows no changes

This is normal - dry-run mode previews without applying. Remove `--dry-run` to apply changes.

### Want to retry failed enhancements

The script tracks state. Simply run again with the same configuration - it will re-attempt failed operations.

## Integration with CI/CD

The script supports automated deployments:

```yaml
# GitLab CI example
deploy:
  script:
    - cp configs/production.conf /tmp/setup.conf
    - ./scripts/setup-complete.sh --auto --config /tmp/setup.conf --skip-confirm
  only:
    - main
```

```yaml
# GitHub Actions example
- name: Deploy Waydroid Setup
  run: |
    ./scripts/setup-complete.sh --auto \
      --config config/production.conf \
      --skip-confirm
```

## Best Practices

1. **Always dry-run first**: Test configuration before applying
2. **Save working configs**: Keep successful configurations for redeployment
3. **Review logs**: Check summary reports after execution
4. **Incremental deployment**: Start with basic enhancements, add more later
5. **Document customizations**: Comment configuration files
6. **Test individually**: If issues occur, test individual scripts
7. **Use version control**: Track configuration files in git

## Performance Considerations

- **LXC tuning**: Requires container restart for full effect
- **Audio setup**: May need container restart after setup
- **VNC enhancement**: Restart waydroid-vnc service to apply
- **Clipboard**: Service starts automatically after installation
- **Apps**: Can take time for large batch installations

Total setup time varies:
- Minimal (LXC + VNC): 2-5 minutes
- Standard (all except apps): 5-10 minutes
- Complete (all + apps): 10-30 minutes depending on app count

## Security Considerations

- Configuration files may contain sensitive paths
- Store configuration files securely
- Review dry-run output before applying in production
- Monitor logs for security-related issues
- Use TLS for VNC in production environments

## Limitations

- Cannot run across multiple hosts (must run on target host)
- Requires root/sudo for most operations
- LXC operations require Proxmox host environment
- Some operations cannot be easily rolled back
- Container must be stopped/restarted for some changes

## Support and Contribution

For issues, questions, or contributions:
- GitHub Issues: https://github.com/iceteaSA/waydroid-proxmox/issues
- Documentation: https://github.com/iceteaSA/waydroid-proxmox/tree/main/docs
- Discussions: https://github.com/iceteaSA/waydroid-proxmox/discussions

## Related Documentation

- [Main README](../README.md)
- [Audio Setup Guide](AUDIO-GUIDE.md) (if exists)
- [Clipboard Guide](CLIPBOARD-GUIDE.md) (if exists)
- [Individual script documentation](../scripts/)

## Version History

- **v1.0.0** (2025-01-XX): Initial release
  - Interactive menu interface
  - Non-interactive automation support
  - Dry-run mode
  - Comprehensive prerequisite checking
  - Detailed reporting

## License

MIT License - See [LICENSE](../LICENSE) file for details.
