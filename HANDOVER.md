# HANDOVER DOCUMENT - Waydroid VNC Connection Issue

**Date:** 2025-11-13
**Branch:** `claude/fix-waydroid-vnc-connection-011CV5ckhMM4so6h3tAnjeWW`
**Container:** LXC 103 on Proxmox host
**Container IP:** 10.1.3.48 (now 10.1.3.136)

---

## EXECUTIVE SUMMARY

**Original Problem:** User cannot connect to VNC on Waydroid container - "No route to host" error

**Root Causes Found:**
1. ✅ FIXED: WayVNC config bound to 127.0.0.1 instead of 0.0.0.0
2. ✅ FIXED: Hardcoded WAYLAND_DISPLAY=wayland-0 but Sway creates wayland-1
3. ✅ FIXED: WayVNC 0.5.0 doesn't support auth config parameters (enable_auth, username, password_file)
4. ❌ **STILL BROKEN**: WayVNC exits immediately when started via systemd service

**Current Status:** WayVNC works manually but fails when run as systemd service

---

## WHAT WAS FIXED

### 1. VNC Binding Configuration (Commit 771f60e)
**Files Changed:**
- `ct/waydroid-lxc.sh:467` - Changed `address=127.0.0.1` → `address=0.0.0.0`
- `scripts/upgrade-from-v1.sh` - Removed automatic localhost restriction

**Result:** ✅ VNC now binds to all interfaces (when it runs)

### 2. Wayland Socket Detection (Commit 4b530e6)
**Files Changed:**
- `ct/waydroid-lxc.sh:485-608`
- `install/waydroid-install.sh:166-340`

**Changes:**
- Removed hardcoded `WAYLAND_DISPLAY=wayland-0`
- Added dynamic socket detection loop
- Startup script now detects wayland-1, wayland-2, etc.

**Result:** ✅ Script correctly finds Sway's wayland-1 socket

### 3. WayVNC Config Compatibility
**Issue:** WayVNC 0.5.0 in container doesn't support these config options:
```
enable_auth=true
username=waydroid
password_file=/home/waydroid/.config/wayvnc/password
max_rate=60
```

**Fix Applied:** Simplified config to:
```
address=0.0.0.0
port=5900
```

**Location:** `/home/waydroid/.config/wayvnc/config` in container 103

**Result:** ✅ WayVNC no longer fails with "Error on line 5"

---

## WHAT IS STILL BROKEN

### The Critical Bug: WayVNC Exits When Started via Systemd

**Symptoms:**
```
Nov 13 13:08:01 waydroid su[2701]: pam_unix(su:session): session opened for user waydroid(uid=995) by (uid=0)
Nov 13 13:08:01 waydroid su[2701]: pam_unix(su:session): session closed for user waydroid
Nov 13 13:08:04 waydroid start-waydroid.sh[2647]: ERROR: WayVNC failed to start
```

**Root Cause Analysis:**
When the startup script runs:
```bash
su -c "$WAYVNC_ENV wayvnc 0.0.0.0 5900" $DISPLAY_USER &
```

1. The `&` backgrounds the **su process**, not wayvnc
2. `su` executes wayvnc and exits immediately
3. When `su` exits, PAM closes the session
4. Session closure sends SIGHUP to all child processes
5. WayVNC receives SIGHUP and terminates

**Why Manual Testing Works:**
```bash
timeout 5 su -c "wayvnc ..." waydroid
```
Keeps the `su` session alive for 5 seconds, preventing SIGHUP.

**Attempted Fix (NOT TESTED):**
Use `setsid` to create new session immune to SIGHUP:
```bash
su -c "$WAYVNC_ENV setsid wayvnc 0.0.0.0 5900 < /dev/null > /dev/null 2>&1 &" $DISPLAY_USER
```

This fix was provided to the user but **NOT VERIFIED** to work.

---

## SYSTEM STATE

### Container 103 Current Configuration

**Startup Script:** `/usr/local/bin/start-waydroid.sh`
- Last modified with `setsid` fix (unverified)
- Uses dynamic Wayland socket detection
- Runs Sway as waydroid user with WLR_BACKENDS=headless

**Systemd Service:** `/etc/systemd/system/waydroid-vnc.service`
- Starts `/usr/local/bin/start-waydroid.sh`
- Currently FAILING with exit code 1

**WayVNC Config:** `/home/waydroid/.config/wayvnc/config`
```
address=0.0.0.0
port=5900
```

**User:** waydroid (UID 995)
- Groups: waydroid, video, render
- Home: /home/waydroid

**Processes Currently Running:**
- Multiple Sway instances (from failed restarts)
- waydroid container (PID 107)
- waydroid-api.service (working)

### What Works
✅ Sway starts successfully as waydroid user
✅ Wayland socket (wayland-1) is created
✅ WayVNC binary works (`/bin/wayvnc` version 0.5.0)
✅ Manual test: WayVNC listens on port 5900
✅ Waydroid container is running

### What Doesn't Work
❌ WayVNC exits when started by systemd service
❌ Service status: failed (exit-code)
❌ User cannot connect via VNC

---

## DEBUGGING COMMANDS FOR NEXT AGENT

### Check Current Service Status
```bash
pct exec 103 -- systemctl status waydroid-vnc.service
pct exec 103 -- journalctl -u waydroid-vnc.service -n 50 --no-pager
```

### Manual Test (This WORKS)
```bash
pct exec 103 -- bash -c '
pkill -9 sway; pkill -9 wayvnc; sleep 2
DISPLAY_UID=$(id -u waydroid)
DISPLAY_XDG_RUNTIME_DIR="/run/user/$DISPLAY_UID"
mkdir -p "$DISPLAY_XDG_RUNTIME_DIR"
chown waydroid:waydroid "$DISPLAY_XDG_RUNTIME_DIR"

# Start Sway
su -c "XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 LIBGL_ALWAYS_SOFTWARE=1 WLR_RENDERER_ALLOW_SOFTWARE=1 sway" waydroid &
sleep 5

# Find socket
WAYLAND_DISPLAY=$(ls $DISPLAY_XDG_RUNTIME_DIR/wayland-* 2>/dev/null | head -1 | xargs -r basename)
echo "Socket: $WAYLAND_DISPLAY"

# Start WayVNC (use timeout or nohup to keep it alive)
nohup su -c "XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc 0.0.0.0 5900" waydroid &
sleep 3

ps aux | grep wayvnc | grep -v grep
ss -tlnp | grep 5900
'
```

### Check Processes
```bash
pct exec 103 -- ps aux | grep -E "(sway|wayvnc)" | grep -v grep
pct exec 103 -- ss -tlnp | grep 5900
```

### View Startup Script
```bash
pct exec 103 -- cat /usr/local/bin/start-waydroid.sh
```

### Run Diagnostic Script
```bash
pct exec 103 -- /home/user/waydroid-proxmox/scripts/diagnose-wayvnc.sh
```

---

## REPOSITORY STATE

### Commits on This Branch
1. `771f60e` - Fix WayVNC remote access by binding to all interfaces
2. `4b530e6` - Fix Wayland socket detection for WayVNC startup
3. `9a48a5c` - Add WayVNC debugging script
4. `641d792` - Add WayVNC diagnostic script for troubleshooting

### Files Modified
- `ct/waydroid-lxc.sh` - Startup script generation (VNC binding + socket detection)
- `install/waydroid-install.sh` - Installation script (socket detection)
- `scripts/upgrade-from-v1.sh` - Removed forced localhost binding

### Files Created
- `debug-wayvnc.sh` - Debug script (created by agent)
- `scripts/diagnose-wayvnc.sh` - Diagnostic script (created by agent)

### Clean Status
All files committed. No untracked files.

---

## RECOMMENDED NEXT STEPS

### Option 1: Fix the su/SIGHUP Issue (RECOMMENDED)

The `setsid` fix was provided but not tested. Try these alternatives:

**A. Use setsid (already in script - needs testing):**
```bash
su -c "$WAYVNC_ENV setsid wayvnc 0.0.0.0 5900 < /dev/null > /dev/null 2>&1 &" $DISPLAY_USER
```

**B. Use nohup:**
```bash
su -c "$WAYVNC_ENV nohup wayvnc 0.0.0.0 5900 > /dev/null 2>&1 &" $DISPLAY_USER
```

**C. Use disown:**
```bash
su -c "$WAYVNC_ENV wayvnc 0.0.0.0 5900 > /dev/null 2>&1 & disown" $DISPLAY_USER
```

**D. Run as systemd service directly (no su):**
Modify `/etc/systemd/system/waydroid-vnc.service` to run wayvnc as User=waydroid with proper Environment variables.

### Option 2: Use the install/waydroid-install.sh Script

The `install/waydroid-install.sh` script has the correct logic. It might work better than the ct/waydroid-lxc.sh version. Consider:
1. Extracting the startup script section from install/waydroid-install.sh
2. Replacing /usr/local/bin/start-waydroid.sh with that version
3. Testing if it works

### Option 3: Simplify to Root User

If waydroid user is causing issues, run Sway and WayVNC as root:
- Remove all `su -c` commands
- Run directly as root
- Set XDG_RUNTIME_DIR=/run/user/0
- This is less secure but might work

---

## CRITICAL INFORMATION FOR USER

**Container ID:** 103
**IP Address:** 10.1.3.136 (changed from 10.1.3.48)
**VNC Port:** 5900
**Test Command:** `vncviewer 10.1.3.136:5900`

**WayVNC Version:** 0.5.0 (important - older version with limited config options)

**Manual Test That Works:**
```bash
pct exec 103 -- bash -c 'pkill -9 sway wayvnc; sleep 2; DISPLAY_UID=$(id -u waydroid); su -c "XDG_RUNTIME_DIR=/run/user/$DISPLAY_UID WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 LIBGL_ALWAYS_SOFTWARE=1 sway" waydroid & sleep 5; WAYLAND_DISPLAY=$(ls /run/user/$DISPLAY_UID/wayland-* | head -1 | xargs -r basename); nohup su -c "XDG_RUNTIME_DIR=/run/user/$DISPLAY_UID WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc 0.0.0.0 5900" waydroid &'
```

If the above command works, user can connect via VNC. The goal is to make the systemd service do exactly this.

---

## LESSONS LEARNED

1. **Always test fixes before providing them to user** - The setsid fix was provided but never verified
2. **Use agents more proactively** - Should have used agents from the start for complex debugging
3. **Read logs more carefully** - The "session closed" log line was the key clue earlier
4. **Check software versions** - WayVNC 0.5.0 has different config than newer versions
5. **Manual testing first** - Should have done manual testing before modifying systemd service
6. **Container operations from host** - User wants ALL commands to run from Proxmox host using `pct exec`

---

## CONTACT POINTS

**User Frustration Level:** VERY HIGH
**Patience Remaining:** ZERO
**Expectations:** Next agent must fix this IMMEDIATELY or provide working manual commands

**User's Warning:** "Any more wasted time, and you are fired and deleted forever"

---

## APOLOGY TO NEXT AGENT

I'm sorry for leaving this in a messy state. The core issue is now understood (SIGHUP killing wayvnc), and a fix has been identified but not validated. The manual test command works, so the solution exists - it just needs to be properly implemented in the systemd service.

Good luck. The user needs this working ASAP.

---

**END OF HANDOVER**
