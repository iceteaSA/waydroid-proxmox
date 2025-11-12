# Configuration Guide

Advanced configuration options for Waydroid Proxmox LXC.

## LXC Container Configuration

### Container Resources

Edit the installation script (`install/install.sh`) before installation:

```bash
# Default values
CORES="2"          # CPU cores allocated
RAM="2048"         # RAM in MB
DISK_SIZE="16"     # Disk size in GB
BRIDGE="vmbr0"     # Network bridge
```

### GPU Passthrough

The container configuration (`/etc/pve/lxc/<ctid>.conf`) includes:

```
# GPU Passthrough
lxc.cgroup2.devices.allow: c 226:* rwm    # DRM devices
lxc.cgroup2.devices.allow: c 29:0 rwm     # Framebuffer
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file

# Security
lxc.apparmor.profile: unconfined
lxc.cap.drop:
lxc.cgroup2.devices.allow: a
```

**To modify after installation:**
```bash
# Stop container
pct stop <ctid>

# Edit config
nano /etc/pve/lxc/<ctid>.conf

# Start container
pct start <ctid>
```

## Waydroid Configuration

### Properties

Waydroid properties are stored in `/var/lib/waydroid/waydroid.prop`

**Set properties:**
```bash
waydroid prop set <property> <value>
```

**Common properties:**
```bash
# GPU acceleration
waydroid prop set ro.hardware.gralloc gbm
waydroid prop set ro.hardware.egl mesa

# Display resolution
waydroid prop set ro.sf.lcd_density 240

# Performance
waydroid prop set dalvik.vm.heapsize 512m
```

### Display Configuration

**Resolution:**
```bash
# Set custom resolution
waydroid prop set persist.waydroid.width 1920
waydroid prop set persist.waydroid.height 1080

# Restart Waydroid
systemctl restart waydroid-vnc
```

**DPI (Density):**
```bash
# Higher DPI = smaller UI elements
waydroid prop set ro.sf.lcd_density 240  # Tablet (default)
waydroid prop set ro.sf.lcd_density 320  # Phone
waydroid prop set ro.sf.lcd_density 160  # Large tablet
```

### Network Configuration

**Default**: Waydroid uses its own network namespace.

**Bridge mode** (share LXC network):
```bash
# Edit Waydroid config
nano /var/lib/waydroid/lxc/waydroid/config_nodes

# Change network to use host
lxc.net.0.type = none
```

**DNS Configuration:**
```bash
# Set custom DNS
waydroid prop set net.dns1 8.8.8.8
waydroid prop set net.dns2 8.8.4.4
```

## Compositor Configuration

### Sway

Configuration file: `/root/.config/sway/config`

**Auto-start apps:**
```
exec waydroid session start
exec wayvnc 0.0.0.0 5900
```

**Display settings:**
```
output * resolution 1920x1080
output * scale 1
```

### Weston

Configuration file: `/root/.config/weston.ini`

```ini
[core]
backend=drm-backend.so

[output]
name=HDMI-A-1
mode=1920x1080

[shell]
background-color=0xff000000
```

## VNC Configuration

Configuration file: `/root/.config/wayvnc/config`

### Basic Settings

```yaml
address=0.0.0.0
port=5900
enable_auth=false
```

### Enable Authentication

```yaml
enable_auth=true
username=admin
password=yourpassword
```

### Performance Tuning

```yaml
# Compression level (0-9, higher = more CPU, less bandwidth)
compression_level=6

# Quality (0-9, higher = better quality)
quality=7
```

## API Configuration

Edit `/usr/local/bin/waydroid-api.py`

### Change Port

```python
if __name__ == '__main__':
    run_server(port=8080)  # Change port here
```

### Add Authentication

Add basic auth to the API:

```python
import base64

class WaydroidAPIHandler(BaseHTTPRequestHandler):
    def do_authhead(self):
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="Waydroid"')
        self.end_headers()

    def do_GET(self):
        auth = self.headers.get('Authorization')
        if auth is None:
            self.do_authhead()
            return

        # Verify credentials
        if auth != 'Basic ' + base64.b64encode(b'admin:password').decode():
            self.do_authhead()
            return

        # Continue with normal handling
        ...
```

## Intel N150 Optimizations

Configuration file: `config/intel-n150.conf`

### i915 Module Parameters

On Proxmox host:

```bash
# Edit module config
nano /etc/modprobe.d/i915.conf
```

```
# Intel N150 optimizations
options i915 enable_guc=3 enable_fbc=1 fastboot=1
```

**Parameters:**
- `enable_guc=3`: Enable GuC and HuC firmware loading
- `enable_fbc=1`: Enable framebuffer compression
- `fastboot=1`: Skip unnecessary mode sets during boot

### Mesa Environment Variables

In container, edit `/usr/local/bin/start-waydroid.sh`:

```bash
export MESA_LOADER_DRIVER_OVERRIDE=iris
export MESA_GL_VERSION_OVERRIDE=4.6
export MESA_GLSL_VERSION_OVERRIDE=460
export INTEL_DEBUG=norbc  # Disable render buffer compression if issues
```

### CPU Governor

For better performance:

```bash
# On Proxmox host
echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

Make persistent:
```bash
apt-get install cpufrequtils
echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
systemctl restart cpufrequtils
```

## Systemd Services

### Waydroid VNC Service

Location: `/etc/systemd/system/waydroid-vnc.service`

**Customize startup delay:**
```ini
[Service]
ExecStartPre=/bin/sleep 5  # Wait 5 seconds before starting
```

**Auto-restart on failure:**
```ini
[Service]
Restart=always
RestartSec=10
```

### Waydroid API Service

Location: `/etc/systemd/system/waydroid-api.service`

**Custom port:**
```ini
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/waydroid-api.py 8888
```

**Enable logging:**
```ini
[Service]
StandardOutput=journal
StandardError=journal
```

## Android Configuration

### Enable ADB

```bash
# In container
waydroid shell

# In Android shell
setprop service.adb.tcp.port 5555
stop adbd
start adbd
```

**Connect from host:**
```bash
adb connect <container-ip>:5555
```

### Install ARM Translation

Some apps require ARM libraries on x86:

```bash
# Download libhoudini (for ARM translation)
cd /tmp
wget https://github.com/casualsnek/waydroid_script/archive/refs/heads/main.zip
unzip main.zip
cd waydroid_script-main

# Install ARM translation
python3 main.py install libhoudini

# Restart Waydroid
systemctl restart waydroid-vnc
```

### Google Play Certification

```bash
# Get Android ID
waydroid shell 'sqlite3 /data/data/com.google.android.gsf/databases/gservices.db "select * from main where name = \"android_id\";"'

# Register at: https://www.google.com/android/uncertified/
```

## Performance Tuning

### Memory

**Increase Waydroid heap:**
```bash
waydroid prop set dalvik.vm.heapsize 512m
waydroid prop set dalvik.vm.heapmaxfree 8m
```

**LXC memory limits:**
```bash
# On Proxmox host
pct set <ctid> -memory 4096  # Increase to 4GB
```

### CPU Pinning

Pin LXC to specific cores:

```bash
# Edit /etc/pve/lxc/<ctid>.conf
lxc.cgroup2.cpuset.cpus: 0,1  # Use cores 0 and 1
```

### I/O Priority

Give Waydroid higher I/O priority:

```bash
# Edit /etc/systemd/system/waydroid-vnc.service
[Service]
IOSchedulingClass=realtime
IOSchedulingPriority=0
```

### Disk Performance

Use SSD storage and enable trim:

```bash
# On Proxmox host
pct set <ctid> -rootfs local-lvm:16,mountoptions=discard
```

## Firewall Configuration

### UFW (Uncomplicated Firewall)

```bash
# In container
apt-get install ufw

# Allow VNC
ufw allow 5900/tcp

# Allow API
ufw allow 8080/tcp

# Enable
ufw enable
```

### Proxmox Firewall

Via Proxmox web UI:
1. Datacenter → Firewall → Add
2. Allow ports 5900 (VNC) and 8080 (API)

## Backup and Restore

### Backup LXC

```bash
# On Proxmox host
vzdump <ctid> --compress zstd --mode stop

# Backup location
ls /var/lib/vz/dump/
```

### Backup Waydroid Data

```bash
# In container
tar -czf /root/waydroid-backup.tar.gz /var/lib/waydroid/
```

### Restore

```bash
# Restore LXC
pct restore <new-ctid> /var/lib/vz/dump/vzdump-lxc-<ctid>-*.tar.zst

# Restore Waydroid data
tar -xzf waydroid-backup.tar.gz -C /
```

## Advanced: Multiple Android Instances

Run multiple Android sessions in different containers:

```bash
# Create second container
./install/install.sh
# Use different CTID

# Different ports for each
# Container 1: VNC 5900, API 8080
# Container 2: VNC 5901, API 8081
```

## Troubleshooting Configuration Issues

### Check Current Configuration

```bash
# Waydroid properties
waydroid show-full-ui

# Container config
cat /etc/pve/lxc/<ctid>.conf

# Systemd service status
systemctl status waydroid-vnc waydroid-api
```

### Reset to Defaults

```bash
# Reinitialize Waydroid
waydroid init -f

# Reset container (destructive!)
pct destroy <ctid>
./install/install.sh
```

### Logs

```bash
# Waydroid logs
journalctl -u waydroid-container -f

# VNC logs
journalctl -u waydroid-vnc -f

# API logs
journalctl -u waydroid-api -f

# System logs
dmesg | grep -i waydroid
```

## Environment Variables

Useful environment variables for debugging:

```bash
# Enable Wayland debugging
export WAYLAND_DEBUG=1

# Mesa debugging
export MESA_DEBUG=1
export LIBGL_DEBUG=verbose

# Waydroid debugging
export WAYDROID_DEBUG=1
```

Add to `/usr/local/bin/start-waydroid.sh` for persistent debugging.

## Resources

- [Waydroid Properties](https://docs.waydro.id/usage/prop-options)
- [LXC Configuration](https://linuxcontainers.org/lxc/manpages/man5/lxc.container.conf.5.html)
- [Intel Graphics](https://wiki.archlinux.org/title/Intel_graphics)
- [Sway Configuration](https://man.archlinux.org/man/sway.5)
