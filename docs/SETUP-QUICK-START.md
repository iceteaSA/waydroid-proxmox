# Quick Start Guide - Setup Complete Script

## TL;DR - Get Started in 3 Steps

```bash
# 1. Run the interactive setup wizard
cd /path/to/waydroid-proxmox
./scripts/setup-complete.sh

# 2. Select enhancements with number keys (1-5)
#    Configure options (press 'o')
#    Check prerequisites (press 'c')

# 3. Run selected enhancements (press 'r')
```

## Common Use Cases

### First-Time Interactive Setup

```bash
./scripts/setup-complete.sh
```

**What to do:**
1. Select enhancements by pressing numbers 1-5
2. Press 'o' to configure options (important: set Container ID!)
3. Press 'c' to check prerequisites
4. Press 'r' to run

### Preview Changes (Dry-Run)

```bash
./scripts/setup-complete.sh --dry-run
```

Shows what would be changed without actually changing anything.

### Automated Setup with Config File

```bash
# Step 1: Create config
cp config/setup-example.conf config/my-setup.conf
nano config/my-setup.conf  # Edit: set select_*=true, lxc_ctid=100, etc.

# Step 2: Test with dry-run
./scripts/setup-complete.sh --auto --config config/my-setup.conf --dry-run

# Step 3: Apply
./scripts/setup-complete.sh --auto --config config/my-setup.conf
```

## What Each Enhancement Does

| Enhancement | What It Does | Where It Runs |
|------------|--------------|---------------|
| **LXC Performance** | Optimizes container CPU, memory, I/O, security | Proxmox Host |
| **VNC Security** | Adds auth, TLS, rate limiting, monitoring | LXC Container |
| **Audio Passthrough** | Enables audio in Android apps | Host + Container |
| **Clipboard Sharing** | Sync clipboard between VNC ↔ Android | LXC Container |
| **App Installation** | Install Android apps (APK, F-Droid) | LXC Container |

## Minimum Configuration Required

For automated setup, you need at least:

```bash
# config/minimal.conf
select_lxc=true
select_vnc=true
lxc_ctid=100    # YOUR container ID
```

Then run:
```bash
./scripts/setup-complete.sh --auto --config config/minimal.conf
```

## Menu Quick Reference

When in interactive mode:

| Key | Action |
|-----|--------|
| `1-5` | Toggle enhancement selection |
| `o` | Configure options |
| `c` | Check prerequisites |
| `s` | Save current configuration |
| `l` | Load configuration from file |
| `r` | Run selected enhancements |
| `d` | Dry-run (preview only) |
| `q` | Quit |

## Configuration File Quick Reference

```bash
# Selections (true/false)
select_lxc=true
select_vnc=true
select_audio=true
select_clipboard=true
select_apps=false

# Required: Container ID
lxc_ctid=100

# VNC Options
vnc_enable_tls=false          # Enable TLS encryption?
vnc_enable_monitoring=true    # Enable connection monitoring?
vnc_fps=60                    # Frame rate (15-120)

# Audio Options
audio_system=auto             # auto, pulseaudio, or pipewire

# Clipboard Options
clipboard_interval=2          # Sync interval in seconds (1-60)

# App Installation Options
apps_config=                  # Path to apps.yaml (optional)
```

## Typical Setup Workflow

### On Proxmox Host

```bash
# 1. Clone the repository
cd /opt
git clone https://github.com/iceteaSA/waydroid-proxmox.git
cd waydroid-proxmox

# 2. Run LXC and Audio setup (host-side operations)
./scripts/setup-complete.sh

# In menu:
# - Select: 1 (LXC), 3 (Audio)
# - Press 'o', set Container ID
# - Press 'r' to run
```

### In LXC Container

```bash
# 1. Copy scripts to container (or clone repo)
pct push 100 /opt/waydroid-proxmox/scripts /root/scripts -r

# 2. Enter container
pct enter 100

# 3. Run container-side enhancements
cd /root/scripts
./setup-complete.sh

# In menu:
# - Select: 2 (VNC), 4 (Clipboard), 5 (Apps)
# - Press 'r' to run
```

## Command Line Examples

### Basic Operations

```bash
# Show help
./scripts/setup-complete.sh --help

# Dry-run everything
./scripts/setup-complete.sh --dry-run

# Automated with config
./scripts/setup-complete.sh --auto --config my-setup.conf

# Set container ID from command line
./scripts/setup-complete.sh --ctid 100
```

### Save and Reuse Configurations

```bash
# Interactive: configure in menu, then press 's'
./scripts/setup-complete.sh

# Or save current config
./scripts/setup-complete.sh --save-config my-saved.conf

# Later, reuse it
./scripts/setup-complete.sh --auto --config my-saved.conf
```

## Finding Your Container ID (CTID)

On Proxmox host:

```bash
# List all containers
pct list

# Get specific container info
pct config 100

# Check if container exists
pct status 100
```

The CTID is the number in the first column (e.g., 100, 101, 102).

## Where Are The Logs?

All execution logs are saved in `/var/log/waydroid-setup/`:

```bash
# View latest summary
ls -lt /var/log/waydroid-setup/*-summary.txt | head -1 | xargs cat

# View full log
ls -lt /var/log/waydroid-setup/setup-report-*.txt | head -1 | xargs less

# Follow live during execution
tail -f /var/log/waydroid-setup/setup-report-*.txt
```

## Troubleshooting Quick Fixes

### "Prerequisites check failed"

**Problem:** Missing requirements

**Fix:**
```bash
# Check what's missing
./scripts/setup-complete.sh
# Press 'c' to see detailed prerequisite check

# Common fixes:
# - Set Container ID in options (press 'o')
# - Run on correct host (Proxmox for LXC/Audio, Container for others)
# - Start Waydroid if needed
```

### "Container does not exist"

**Problem:** Wrong CTID or container not created

**Fix:**
```bash
# Find your containers
pct list

# Use the correct CTID
./scripts/setup-complete.sh --ctid 100  # Replace 100 with your CTID
```

### "Must be run on Proxmox host"

**Problem:** Trying to run LXC/Audio operations in container

**Fix:** Run those enhancements on the Proxmox host, not in the container

### "Waydroid not running"

**Problem:** Clipboard or apps need Waydroid running

**Fix:**
```bash
# In container
waydroid container start
waydroid session start &

# Then run setup again
```

## Best Practices

✅ **DO:**
- Always try dry-run first
- Check prerequisites before running
- Save successful configurations
- Review summary reports after execution
- Use descriptive names for config files

❌ **DON'T:**
- Skip prerequisite checks
- Run without understanding what it does
- Ignore error messages in logs
- Mix up host and container operations

## Performance Tips

- **Fastest setup:** LXC + VNC only (~2-5 min)
- **Recommended:** All except apps (~5-10 min)
- **Complete:** All including apps (~10-30 min)

Restart services after setup for changes to take effect:
```bash
# On host
pct restart 100

# In container
systemctl restart waydroid-vnc
systemctl restart waydroid-clipboard-sync
```

## Getting Help

```bash
# Show detailed help
./scripts/setup-complete.sh --help

# Check individual script help
./scripts/tune-lxc.sh --help
./scripts/enhance-vnc.sh --help
./scripts/setup-audio.sh --help --help
./scripts/setup-clipboard.sh --help
./scripts/install-apps.sh --help
```

## Next Steps After Setup

1. **Verify services:**
   ```bash
   systemctl status waydroid-vnc
   systemctl status waydroid-clipboard-sync
   ```

2. **Test functionality:**
   ```bash
   ./scripts/test-setup.sh
   ./scripts/health-check.sh
   ```

3. **Connect via VNC:**
   ```bash
   # Get container IP
   pct exec 100 -- hostname -I

   # Connect with VNC client to: <IP>:5900
   ```

4. **Install more apps:**
   ```bash
   ./scripts/install-apps.sh install-fdroid org.fdroid.fdroid
   ```

## Full Documentation

For complete documentation, see:
- [Complete Setup Guide](SETUP-COMPLETE-GUIDE.md)
- [Main README](../README.md)
- Individual script documentation in `scripts/` directory

## Example: Complete Automated Setup

```bash
#!/bin/bash
# complete-setup.sh - Automated full setup script

# Configuration
CTID=100
SETUP_DIR="/opt/waydroid-proxmox"

# Create config
cat > /tmp/auto-setup.conf << EOF
select_lxc=true
select_vnc=true
select_audio=true
select_clipboard=true
select_apps=false
lxc_ctid=${CTID}
vnc_enable_tls=false
vnc_enable_monitoring=true
vnc_fps=60
audio_system=auto
clipboard_interval=2
apps_config=
EOF

# Test with dry-run
echo "Testing configuration..."
${SETUP_DIR}/scripts/setup-complete.sh \
    --auto \
    --config /tmp/auto-setup.conf \
    --dry-run

# Prompt for confirmation
read -p "Apply configuration? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Apply setup
    ${SETUP_DIR}/scripts/setup-complete.sh \
        --auto \
        --config /tmp/auto-setup.conf

    # Show results
    cat /var/log/waydroid-setup/*-summary.txt | tail -50
else
    echo "Setup cancelled"
fi

# Cleanup
rm /tmp/auto-setup.conf
```

## Summary

The setup-complete.sh script makes it easy to configure all Waydroid enhancements:

1. **Interactive**: Just run `./scripts/setup-complete.sh` and follow the menu
2. **Automated**: Create a config file and run with `--auto --config`
3. **Safe**: Use `--dry-run` to preview before applying
4. **Comprehensive**: Checks prerequisites, handles errors, generates reports

Start with the basics (LXC + VNC), then add more enhancements as needed!
