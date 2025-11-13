# Quick Diagnostic Commands - WayVNC Auth Issue

Run these commands from the Proxmox host to quickly diagnose the issue.

## 1. Check if Config File Exists and Its Content

```bash
pct exec 103 -- cat /home/waydroid/.config/wayvnc/config
```

**Expected:** Should show:
```
address=0.0.0.0
port=5900
enable_auth=false
```

**If different:** Config wasn't created properly by fix script.

---

## 2. Check WayVNC Version and Help

```bash
pct exec 103 -- wayvnc --version
```

```bash
pct exec 103 -- wayvnc --help 2>&1 | head -40
```

**Look for:**
- [ ] Is `-C` or `--config` flag listed? (If NO, config file approach won't work)
- [ ] Are any auth-related flags listed? (`--enable-auth`, `--disable-auth`, etc.)
- [ ] What options ARE available?

---

## 3. Check Current WayVNC Process

```bash
pct exec 103 -- ps aux | grep wayvnc
```

**Look for:** Is wayvnc actually running?

```bash
pct exec 103 -- bash -c 'pgrep wayvnc && cat /proc/$(pgrep wayvnc)/cmdline | tr "\0" " "'
```

**Expected:** Should show: `wayvnc -C /home/waydroid/.config/wayvnc/config` (or similar)
**If shows:** `wayvnc 0.0.0.0 5900` - Script wasn't updated properly

---

## 4. Check Port 5900

```bash
pct exec 103 -- ss -tlnp | grep 5900
```

**Expected:** Should show WayVNC listening on 0.0.0.0:5900
**If not listening:** WayVNC crashed or not running

---

## 5. Check Log File

```bash
pct exec 103 -- ls -lh /var/log/waydroid-wayvnc.log
```

```bash
pct exec 103 -- cat /var/log/waydroid-wayvnc.log
```

**If empty:** Either no output being produced, or output not redirected properly

---

## 6. Check Startup Script

```bash
pct exec 103 -- grep wayvnc /usr/local/bin/start-waydroid.sh
```

**Look for:** Should contain `wayvnc -C /home/waydroid/.config/wayvnc/config`
**If shows:** `wayvnc 0.0.0.0 5900` without `-C` - Config not being used!

---

## 7. Test WayVNC Manually (Critical Test!)

Stop the service and test manually:

```bash
# Stop service
pct exec 103 -- systemctl stop waydroid-vnc.service
pct exec 103 -- pkill -9 wayvnc

# Run manually with verbose output
pct exec 103 -- bash <<'EOF'
DISPLAY_UID=$(id -u waydroid)
WAYLAND_DISPLAY=$(ls /run/user/$DISPLAY_UID/wayland-* 2>/dev/null | head -1 | xargs -r basename)

echo "Using: XDG_RUNTIME_DIR=/run/user/$DISPLAY_UID WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo ""
echo "Starting WayVNC with verbose output..."
echo ""

timeout 10 su - waydroid -c "XDG_RUNTIME_DIR=/run/user/$DISPLAY_UID WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc -C /home/waydroid/.config/wayvnc/config -v 2>&1" || true
EOF
```

**Look for in output:**
- [ ] Does it show "Loading config from /home/waydroid/.config/wayvnc/config"?
- [ ] Does it show "enable_auth" being parsed?
- [ ] Does it show "Unknown option: enable_auth" or similar error?
- [ ] Does it show what security types are enabled?
- [ ] Any error messages?

---

## 8. Test WITHOUT Config File

```bash
pct exec 103 -- bash <<'EOF'
DISPLAY_UID=$(id -u waydroid)
WAYLAND_DISPLAY=$(ls /run/user/$DISPLAY_UID/wayland-* 2>/dev/null | head -1 | xargs -r basename)

echo "Starting WayVNC WITHOUT config file..."
echo ""

timeout 10 su - waydroid -c "XDG_RUNTIME_DIR=/run/user/$DISPLAY_UID WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc 0.0.0.0 5900 -v 2>&1" || true
EOF
```

**Compare:** Does behavior differ from test #7?
**If same error:** Config file has no effect (not supported or being ignored)

---

## 9. Check Binary for Auth Support

```bash
pct exec 103 -- strings /bin/wayvnc | grep -i "enable_auth"
```

**If no output:** The `enable_auth` option doesn't exist in this binary!
**This is the smoking gun!**

```bash
pct exec 103 -- strings /bin/wayvnc | grep -i "auth" | head -20
```

**Look for:** What auth-related strings ARE in the binary?

---

## 10. Test Connection Now

With WayVNC running (from test #7 or #8), try connecting from another terminal:

```bash
# Get container IP
pct exec 103 -- hostname -I

# Try connecting (replace IP)
vncviewer 10.1.3.136:5900
```

**Observe error message:**
- "No matching security types" = Server requires auth, client doesn't support the auth type offered
- "Connection refused" = Port not listening
- Password prompt = Auth is enabled but accepting connections!

---

## Quick Interpretation Guide

### Scenario A: `-C` flag not in `--help` output
**Problem:** WayVNC 0.5.0 doesn't support config files
**Solution:** Use command-line args only: `wayvnc 0.0.0.0 5900`

### Scenario B: `enable_auth` not in binary strings
**Problem:** This option doesn't exist in WayVNC 0.5.0
**Solution:** Either upgrade WayVNC or use password authentication

### Scenario C: Config file being read but auth still required
**Problem:** WayVNC 0.5.0 ignores `enable_auth=false` or always requires auth
**Solution:** Upgrade WayVNC to 0.8.0+

### Scenario D: WayVNC not running at all
**Problem:** Crashes on startup
**Solution:** Check manual run output (test #7) for error messages

### Scenario E: Same behavior with and without config
**Problem:** Config file is being ignored (bad path, bad syntax, not supported)
**Solution:** Verify `-C` flag support, check file permissions

---

## One-Line Checks

### Is WayVNC running?
```bash
pct exec 103 -- pgrep wayvnc >/dev/null && echo "YES" || echo "NO"
```

### Is port listening?
```bash
pct exec 103 -- ss -tlnp | grep -q 5900 && echo "YES" || echo "NO"
```

### Does config exist?
```bash
pct exec 103 -- test -f /home/waydroid/.config/wayvnc/config && echo "YES" || echo "NO"
```

### Can waydroid user read config?
```bash
pct exec 103 -- su - waydroid -c "test -r /home/waydroid/.config/wayvnc/config && echo YES || echo NO"
```

### What command is WayVNC using?
```bash
pct exec 103 -- bash -c 'pgrep wayvnc >/dev/null && cat /proc/$(pgrep wayvnc)/cmdline | tr "\0" " " || echo "Not running"'
```

---

## The Definitive Test

This will tell you EXACTLY what's happening:

```bash
pct exec 103 -- systemctl stop waydroid-vnc.service
pct exec 103 -- pkill -9 wayvnc
sleep 2

pct exec 103 -- bash <<'EOF'
set -x  # Show commands as they execute

DISPLAY_UID=$(id -u waydroid)
WAYLAND_DISPLAY=$(ls /run/user/$DISPLAY_UID/wayland-* 2>/dev/null | head -1 | xargs -r basename)

echo "=== Environment ==="
echo "DISPLAY_UID: $DISPLAY_UID"
echo "WAYLAND_DISPLAY: $WAYLAND_DISPLAY"
echo ""

echo "=== Config File ==="
cat /home/waydroid/.config/wayvnc/config
echo ""

echo "=== WayVNC Help ==="
wayvnc --help 2>&1 | grep -E "config|auth|enable" || echo "No matching flags"
echo ""

echo "=== Running WayVNC ==="
su - waydroid -c "XDG_RUNTIME_DIR=/run/user/$DISPLAY_UID WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc -C /home/waydroid/.config/wayvnc/config -v 2>&1" &

sleep 5
echo ""
echo "=== Port Status ==="
ss -tlnp | grep 5900 || echo "NOT LISTENING"
echo ""

echo "=== Process Status ==="
ps aux | grep wayvnc | grep -v grep || echo "NOT RUNNING"
echo ""

pkill -9 wayvnc
EOF

pct exec 103 -- systemctl start waydroid-vnc.service
```

This single command will show you:
1. What environment variables are set
2. What's in the config file
3. What WayVNC supports
4. What WayVNC outputs when started
5. Whether it successfully starts
6. Whether it listens on the port

**Save this output and analyze it line by line.**

---

## Automated Investigation

Or just run the comprehensive script:

```bash
cd /home/user/waydroid-proxmox
./investigate-wayvnc-auth.sh | tee investigation-results.txt
```

Then read `investigation-results.txt` to see all diagnostic information in one place.

---

**Created:** 2025-11-13
**Purpose:** Quick reference for diagnosing WayVNC authentication issues
