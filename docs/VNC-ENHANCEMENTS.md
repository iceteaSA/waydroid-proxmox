# WayVNC Enhancement Guide

This guide covers the security, performance, and feature improvements available for the headless Waydroid WayVNC setup.

## Overview

The `enhance-vnc.sh` script provides comprehensive improvements to the WayVNC configuration:

- **Security**: TLS/RSA-AES encryption, systemd credentials, rate limiting, audit logging
- **Performance**: Optimized frame rates, encoding settings, clipboard support
- **Features**: noVNC web interface, connection monitoring, tuning tools

## Quick Start

### Basic Enhancement (Recommended)

Apply all security and performance enhancements with default settings:

```bash
cd /home/user/waydroid-proxmox/scripts
./enhance-vnc.sh --enable-tls --enable-monitoring
```

### Full Setup with noVNC

Install everything including web-based access:

```bash
./enhance-vnc.sh --enable-tls --install-novnc --enable-monitoring --fps 60
```

### Security-Only Mode

Apply only security enhancements without changing performance settings:

```bash
./enhance-vnc.sh --security-only --enable-tls --enable-rsa-aes
```

## Security Features

### TLS Encryption (VeNCrypt)

Enables encrypted VNC connections using TLS with self-signed certificates.

**Enable:**
```bash
./enhance-vnc.sh --enable-tls
```

**What it does:**
- Generates EC certificates using secp384r1 curve (recommended by WayVNC)
- Configures WayVNC to require TLS for all connections
- Creates certificate in `/root/.config/wayvnc/tls-cert.pem`
- Private key in `/root/.config/wayvnc/tls-key.pem`

**Verify certificate:**
```bash
openssl x509 -in /root/.config/wayvnc/tls-cert.pem -noout -text
```

**Client connection:**
```bash
# Using vncviewer with TLS
vncviewer -SecurityTypes VeNCrypt,TLSVnc <host>:5900
```

### RSA-AES Encryption

Alternative encryption method using RSA with AES in EAX mode.

**Enable:**
```bash
./enhance-vnc.sh --enable-rsa-aes
```

**What it does:**
- Generates 2048-bit RSA key pair
- Implements TOFU (Trust On First Use) security model similar to SSH
- Protects against eavesdropping and MITM attacks
- Client must verify server fingerprint on first connection

**Note:** RSA-AES uses TOFU, so clients will need to accept the server key on first connection.

### Password Management

Passwords are managed using systemd credentials for better security.

**Location:**
- Password file: `/root/.config/wayvnc/password`
- Systemd credential: `/etc/credstore/wayvnc.password`

**Change password:**
```bash
# Generate new password
tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c 24 > /root/.config/wayvnc/password
echo "" >> /root/.config/wayvnc/password
chmod 600 /root/.config/wayvnc/password

# Update credential
cp /root/.config/wayvnc/password /etc/credstore/wayvnc.password
chmod 600 /etc/credstore/wayvnc.password

# Restart service
systemctl restart waydroid
```

### Connection Rate Limiting

Prevents brute-force attacks by limiting connection attempts.

**Configuration:**
- Maximum: 10 connection attempts per minute per IP address
- Blocked attempts are logged with prefix "VNC rate limit:"

**View blocked IPs:**
```bash
journalctl | grep "VNC rate limit"
```

**Adjust limits:**
```bash
# Change to 5 connections per minute
iptables -D INPUT -p tcp --dport 5900 -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j DROP
iptables -I INPUT -p tcp --dport 5900 -m state --state NEW -m recent --update --seconds 60 --hitcount 5 -j DROP

# Save rules
netfilter-persistent save
```

### Audit Logging

All VNC connections and events are logged for security auditing.

**Log locations:**
- Main log: `/var/log/wayvnc.log`
- Connection log: `/var/log/wayvnc/connections.log`

**View logs:**
```bash
# Recent connections
tail -f /var/log/wayvnc/connections.log

# All WayVNC activity
journalctl -u waydroid -f

# Rate limiting events
journalctl | grep "VNC rate limit"
```

**Log rotation:**
- Logs are rotated daily
- Kept for 14 days
- Configuration: `/etc/logrotate.d/wayvnc`

## Performance Features

### Frame Rate Optimization

The script configures frame rates for optimal performance.

**Set frame rate during installation:**
```bash
./enhance-vnc.sh --fps 60
```

**Adjust after installation:**
```bash
wayvnc-tune.sh fps 60
systemctl restart waydroid
```

**Recommendations:**
- **LAN connections:** 60 FPS (default)
- **WAN/slow connections:** 30 FPS
- **Low bandwidth:** 15 FPS
- **Gaming/low latency:** 60-120 FPS

**Technical note:** WayVNC's `max_rate` is set to 2x the target FPS to prevent frame rate interference.

### Quality Presets

Use predefined performance profiles:

```bash
# Low bandwidth (15 FPS)
wayvnc-tune.sh preset low-bandwidth

# Balanced (30 FPS)
wayvnc-tune.sh preset balanced

# High quality LAN (60 FPS)
wayvnc-tune.sh preset high-quality

# Gaming optimized (60 FPS, low latency)
wayvnc-tune.sh preset gaming
```

### Clipboard Support

Clipboard sharing between host and Android is enabled automatically.

**Requirements:**
- `wl-clipboard` package (installed automatically)
- VNC client with clipboard support

**Test clipboard:**
```bash
# On host - copy text
echo "test" | wl-copy

# Paste in Android app
# (Use VNC client's clipboard paste function)
```

### Current Settings

View current performance configuration:

```bash
wayvnc-tune.sh show
```

## noVNC Web Interface

Browser-based VNC access without requiring a VNC client.

### Installation

```bash
./enhance-vnc.sh --install-novnc --enable-tls
```

### Access

After installation:
- **Via nginx:** `http://<container-ip>/`
- **Direct websockify:** `http://<container-ip>:6080/`
- **Secure (if TLS enabled):** `https://<container-ip>:6080/`

### Components

1. **noVNC** - HTML5 VNC client
   - Location: `/opt/noVNC`
   - Repository: https://github.com/novnc/noVNC

2. **websockify** - WebSocket to TCP proxy
   - Port: 6080 (default)
   - Service: `websockify.service`

3. **nginx** - Reverse proxy
   - Configuration: `/etc/nginx/sites-available/novnc`

### Service Management

```bash
# Status
systemctl status websockify
systemctl status nginx

# Restart
systemctl restart websockify
systemctl restart nginx

# Logs
journalctl -u websockify -f
```

### Troubleshooting noVNC

**Cannot connect:**
```bash
# Check if services are running
systemctl status websockify nginx

# Check if VNC is listening
netstat -tlnp | grep 5900

# Check firewall
iptables -L -n | grep 6080
```

**Blank screen:**
```bash
# Restart entire stack
systemctl restart waydroid websockify nginx
```

**Performance issues:**
```bash
# Lower frame rate
wayvnc-tune.sh fps 30

# Use direct websockify (bypass nginx)
# Connect to http://<ip>:6080/
```

## Connection Monitoring

### Enable Monitoring

```bash
./enhance-vnc.sh --enable-monitoring
```

### View Status Dashboard

```bash
wayvnc-status.sh
```

**Output includes:**
- Service status (WayVNC, websockify, monitor)
- Active connection count and client IPs
- Recent connections from logs
- Rate limiting statistics
- Current configuration summary

### Real-time Monitoring

```bash
# Watch connection log
tail -f /var/log/wayvnc/connections.log

# Monitor all services
watch -n 2 'systemctl status waydroid websockify wayvnc-monitor | head -30'

# Active connections
watch -n 1 'netstat -tn | grep :5900'
```

### Monitoring Service

The monitoring daemon runs continuously:
- **Service:** `wayvnc-monitor.service`
- **Script:** `/usr/local/bin/wayvnc-monitor.sh`
- **Logs:** `/var/log/wayvnc/connections.log`

```bash
# Control monitoring service
systemctl status wayvnc-monitor
systemctl start wayvnc-monitor
systemctl stop wayvnc-monitor
```

## Command Reference

### enhance-vnc.sh

Main enhancement script with multiple options.

```bash
# Full help
./enhance-vnc.sh --help

# Common usage patterns
./enhance-vnc.sh --enable-tls --fps 60
./enhance-vnc.sh --security-only --enable-rsa-aes
./enhance-vnc.sh --performance-only --fps 30
./enhance-vnc.sh --install-novnc --enable-monitoring
```

**Options:**
- `--security-only` - Apply only security enhancements
- `--performance-only` - Apply only performance enhancements
- `--install-novnc` - Install web interface
- `--enable-tls` - Enable TLS encryption
- `--enable-rsa-aes` - Enable RSA-AES encryption
- `--fps <rate>` - Set frame rate (15-120)
- `--quality <level>` - Set JPEG quality (1-9)
- `--enable-monitoring` - Enable connection monitoring

### wayvnc-tune.sh

Performance tuning utility.

```bash
# Show current settings
wayvnc-tune.sh show

# Set frame rate
wayvnc-tune.sh fps 60

# Apply preset
wayvnc-tune.sh preset high-quality
```

**Presets:**
- `low-bandwidth` - 15 FPS
- `balanced` - 30 FPS
- `high-quality` - 60 FPS
- `gaming` - 60 FPS optimized

### wayvnc-status.sh

Connection status and monitoring dashboard.

```bash
# View full status
wayvnc-status.sh

# Pipe to less for scrolling
wayvnc-status.sh | less
```

## Configuration Files

### Main Config

**Location:** `/root/.config/wayvnc/config`

**Example with all features:**
```ini
# Network Settings
address=0.0.0.0
port=5900

# Authentication
enable_auth=true
username=waydroid
password_file=/root/.config/wayvnc/password

# Performance Settings
max_rate=120

# TLS Encryption
use_relative_paths=true
private_key_file=tls-key.pem
certificate_file=tls-cert.pem

# RSA-AES Encryption
rsa_private_key_file=rsa-key.pem
```

### Security Files

```
/root/.config/wayvnc/
├── config                # Main configuration
├── password             # VNC password
├── tls-key.pem         # TLS private key (if enabled)
├── tls-cert.pem        # TLS certificate (if enabled)
└── rsa-key.pem         # RSA private key (if enabled)

/etc/credstore/
└── wayvnc.password     # Systemd credential copy
```

### Log Files

```
/var/log/
├── wayvnc.log                    # Main WayVNC log
└── wayvnc/
    └── connections.log           # Connection monitoring log
```

## Client Connection Examples

### TigerVNC (Recommended)

```bash
# Basic connection
vncviewer <host>:5900

# With TLS
vncviewer -SecurityTypes VeNCrypt,TLSVnc <host>:5900

# Specify quality
vncviewer -QualityLevel 9 <host>:5900
```

### RealVNC

```bash
vncviewer <host>:5900 -EncPreferredEncoding Tight
```

### noVNC (Browser)

Simply navigate to:
```
http://<container-ip>/
```

### SSH Tunnel (Most Secure)

```bash
# Create tunnel
ssh -L 5900:localhost:5900 root@<container-ip>

# Connect via tunnel
vncviewer localhost:5900
```

## Advanced Configuration

### Custom TLS Certificate

Replace self-signed certificate with your own:

```bash
# Copy your certificate and key
cp /path/to/your/cert.pem /root/.config/wayvnc/tls-cert.pem
cp /path/to/your/key.pem /root/.config/wayvnc/tls-key.pem

# Set permissions
chmod 644 /root/.config/wayvnc/tls-cert.pem
chmod 600 /root/.config/wayvnc/tls-key.pem

# Restart service
systemctl restart waydroid
```

### Multi-Monitor Support

WayVNC supports multiple outputs if configured in Sway:

**Edit Sway config:** `/root/.config/sway/config`

```bash
# Add virtual outputs
output HEADLESS-1 mode 1920x1080
output HEADLESS-2 mode 1920x1080
```

**Note:** Most VNC clients show only one output. Use separate VNC sessions or a multi-head aware client.

### Custom Logging

Enhanced logging configuration:

```bash
# Edit systemd service
systemctl edit waydroid

# Add:
[Service]
Environment="WAYVNC_DEBUG=1"
StandardOutput=append:/var/log/wayvnc-debug.log
StandardError=append:/var/log/wayvnc-debug.log
```

### Firewall Configuration

If using external firewall (UFW, firewalld):

```bash
# UFW
ufw allow 5900/tcp comment "VNC"
ufw allow 6080/tcp comment "noVNC"

# firewalld
firewall-cmd --permanent --add-port=5900/tcp
firewall-cmd --permanent --add-port=6080/tcp
firewall-cmd --reload
```

## Security Best Practices

1. **Always enable authentication:**
   - Use strong passwords (24+ characters)
   - Rotate passwords regularly

2. **Use encryption:**
   - Enable TLS for all connections
   - Consider RSA-AES for additional security

3. **Limit access:**
   - Bind to specific interfaces when possible
   - Use SSH tunneling for internet access
   - Enable rate limiting

4. **Monitor connections:**
   - Enable connection monitoring
   - Review logs regularly
   - Watch for suspicious activity

5. **Keep updated:**
   - Update WayVNC regularly
   - Keep TLS certificates current
   - Update system packages

## Performance Optimization

### Network Optimization

For different network scenarios:

**Local LAN (>100 Mbps):**
```bash
wayvnc-tune.sh preset high-quality
```

**WAN/Remote (<10 Mbps):**
```bash
wayvnc-tune.sh preset low-bandwidth
```

**Balanced (10-100 Mbps):**
```bash
wayvnc-tune.sh preset balanced
```

### Client Optimization

**TigerVNC client settings:**
- Encoding: Tight or ZRLE
- Compression level: 6-9
- JPEG quality: 6-8

**noVNC browser settings:**
- Use Chrome/Chromium for best performance
- Enable hardware acceleration
- Close unnecessary browser tabs

### System Optimization

```bash
# Reduce compositor latency (edit sway config)
echo "max_render_time 1" >> /root/.config/sway/config

# Optimize kernel parameters
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
```

## Troubleshooting

### Cannot Connect

**Check service status:**
```bash
systemctl status waydroid
pgrep -af wayvnc
```

**Check port binding:**
```bash
netstat -tlnp | grep 5900
```

**Check firewall:**
```bash
iptables -L -n | grep 5900
```

### Authentication Fails

**Verify password:**
```bash
cat /root/.config/wayvnc/password
```

**Check config:**
```bash
grep -E 'enable_auth|password_file' /root/.config/wayvnc/config
```

**Reset password:**
```bash
tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c 24 > /root/.config/wayvnc/password
echo "" >> /root/.config/wayvnc/password
chmod 600 /root/.config/wayvnc/password
systemctl restart waydroid
cat /root/.config/wayvnc/password
```

### TLS Connection Issues

**Verify certificates:**
```bash
ls -la /root/.config/wayvnc/tls-*.pem
openssl x509 -in /root/.config/wayvnc/tls-cert.pem -noout -dates
```

**Regenerate certificates:**
```bash
cd /root/.config/wayvnc
openssl ecparam -genkey -name secp384r1 -out tls-key.pem
openssl req -new -x509 -key tls-key.pem -out tls-cert.pem -days 365 \
    -subj "/C=US/ST=State/L=City/O=Waydroid/CN=wayvnc-server"
chmod 600 tls-key.pem
chmod 644 tls-cert.pem
systemctl restart waydroid
```

### Poor Performance

**Check CPU usage:**
```bash
top -p $(pgrep wayvnc)
```

**Lower frame rate:**
```bash
wayvnc-tune.sh fps 30
systemctl restart waydroid
```

**Check network:**
```bash
# On client
ping <container-ip>
iperf3 -c <container-ip>
```

### noVNC Not Working

**Check services:**
```bash
systemctl status websockify nginx
```

**Check ports:**
```bash
netstat -tlnp | grep -E '(5900|6080|80)'
```

**Test direct connection:**
```bash
# Bypass nginx
curl http://localhost:6080
```

**Check websockify logs:**
```bash
journalctl -u websockify -n 50
```

## Useful Resources

- **WayVNC GitHub:** https://github.com/any1/wayvnc
- **noVNC Project:** https://github.com/novnc/noVNC
- **Wayland Protocols:** https://wayland.freedesktop.org/
- **TigerVNC Client:** https://tigervnc.org/

## Support and Feedback

For issues related to:
- **WayVNC:** Open issue at https://github.com/any1/wayvnc/issues
- **This script:** Create issue in the Waydroid-Proxmox repository
- **Waydroid:** Visit https://github.com/waydroid/waydroid

## License

This enhancement script is part of the Waydroid-Proxmox project and inherits its license.
