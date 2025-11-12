# WayVNC Quick Reference

Quick reference for common WayVNC tasks and commands.

## Installation & Setup

### Quick Setup (Recommended)
```bash
cd /home/user/waydroid-proxmox/scripts
./enhance-vnc.sh --enable-tls --enable-monitoring --fps 60
systemctl restart waydroid
```

### With noVNC Web Interface
```bash
./enhance-vnc.sh --enable-tls --install-novnc --enable-monitoring
systemctl restart waydroid
```

## Common Commands

### Service Management
```bash
# Restart WayVNC
systemctl restart waydroid

# Check status
systemctl status waydroid

# View logs
journalctl -u waydroid -f
```

### Performance Tuning
```bash
# Show current settings
wayvnc-tune.sh show

# Change FPS
wayvnc-tune.sh fps 60

# Apply presets
wayvnc-tune.sh preset high-quality    # 60 FPS
wayvnc-tune.sh preset balanced        # 30 FPS
wayvnc-tune.sh preset low-bandwidth   # 15 FPS
```

### Monitoring
```bash
# Status dashboard
wayvnc-status.sh

# Watch connections
tail -f /var/log/wayvnc/connections.log

# Active connections
netstat -tn | grep :5900
```

### Password Management
```bash
# View password
cat /root/.config/wayvnc/password

# Change password
tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c 24 > /root/.config/wayvnc/password
echo "" >> /root/.config/wayvnc/password
chmod 600 /root/.config/wayvnc/password
systemctl restart waydroid
```

## Connection Methods

### VNC Client (TigerVNC)
```bash
vncviewer <container-ip>:5900
```

### With TLS
```bash
vncviewer -SecurityTypes VeNCrypt,TLSVnc <container-ip>:5900
```

### SSH Tunnel (Most Secure)
```bash
ssh -L 5900:localhost:5900 root@<container-ip>
vncviewer localhost:5900
```

### Browser (noVNC)
```
http://<container-ip>/
```

## Configuration Files

| File | Purpose |
|------|---------|
| `/root/.config/wayvnc/config` | Main configuration |
| `/root/.config/wayvnc/password` | VNC password |
| `/root/.config/wayvnc/tls-cert.pem` | TLS certificate |
| `/root/.config/wayvnc/tls-key.pem` | TLS private key |
| `/var/log/wayvnc.log` | Main log |
| `/var/log/wayvnc/connections.log` | Connection log |

## Troubleshooting

### Cannot Connect
```bash
# Check if running
systemctl status waydroid
pgrep -af wayvnc

# Check port
netstat -tlnp | grep 5900

# Check firewall
iptables -L -n | grep 5900
```

### Authentication Issues
```bash
# Verify password
cat /root/.config/wayvnc/password

# Check auth config
grep enable_auth /root/.config/wayvnc/config
```

### Poor Performance
```bash
# Lower FPS
wayvnc-tune.sh fps 30
systemctl restart waydroid

# Check CPU usage
top -p $(pgrep wayvnc)
```

### noVNC Not Working
```bash
# Check services
systemctl status websockify nginx

# Restart services
systemctl restart websockify nginx waydroid
```

## Performance Presets

| Preset | FPS | Use Case |
|--------|-----|----------|
| `low-bandwidth` | 15 | Slow connections (<5 Mbps) |
| `balanced` | 30 | Normal usage (5-50 Mbps) |
| `high-quality` | 60 | Fast LAN (>50 Mbps) |
| `gaming` | 60 | Low latency gaming |

## Security Checklist

- [ ] Enable TLS encryption (`--enable-tls`)
- [ ] Use strong password (24+ chars)
- [ ] Enable connection monitoring
- [ ] Review logs regularly
- [ ] Use SSH tunneling for internet access
- [ ] Keep system updated

## Client Settings (TigerVNC)

**Best Performance:**
- Encoding: Tight
- Compression: 9
- JPEG Quality: 6-8

**Best Quality:**
- Encoding: Tight
- Compression: 0-1
- JPEG Quality: 9

## Port Reference

| Port | Service | Purpose |
|------|---------|---------|
| 5900 | WayVNC | VNC server |
| 6080 | websockify | WebSocket proxy |
| 80 | nginx | HTTP access to noVNC |

## Useful Commands Cheat Sheet

```bash
# Enhancement
./enhance-vnc.sh --enable-tls --fps 60

# Status check
wayvnc-status.sh

# Performance tuning
wayvnc-tune.sh fps 60
wayvnc-tune.sh preset balanced

# Service control
systemctl restart waydroid
systemctl status waydroid
journalctl -u waydroid -f

# Connection monitoring
tail -f /var/log/wayvnc/connections.log
netstat -tn | grep :5900

# Password operations
cat /root/.config/wayvnc/password
```

## Emergency Recovery

### Reset Configuration
```bash
cd /root/.config/wayvnc
cp config config.broken
cat > config <<EOF
address=0.0.0.0
port=5900
enable_auth=true
username=waydroid
password_file=/root/.config/wayvnc/password
max_rate=120
EOF
systemctl restart waydroid
```

### Regenerate Certificates
```bash
cd /root/.config/wayvnc
openssl ecparam -genkey -name secp384r1 -out tls-key.pem
openssl req -new -x509 -key tls-key.pem -out tls-cert.pem -days 365 \
    -subj "/C=US/ST=State/L=City/O=Waydroid/CN=wayvnc"
chmod 600 tls-key.pem
chmod 644 tls-cert.pem
systemctl restart waydroid
```

## Support

For detailed information, see [VNC-ENHANCEMENTS.md](VNC-ENHANCEMENTS.md)
