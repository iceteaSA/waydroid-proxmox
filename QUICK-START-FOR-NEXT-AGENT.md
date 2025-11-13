# QUICK START - Fix WayVNC Now

**READ HANDOVER.MD FOR FULL DETAILS**

## The Problem in 3 Lines
1. WayVNC works manually but exits when started by systemd service
2. Issue: `su -c "wayvnc ..." waydroid &` sends SIGHUP when su exits
3. Fix: Use `setsid` or `nohup` to prevent SIGHUP

## Test First - This WORKS
```bash
pct exec 103 -- bash -c '
pkill -9 sway wayvnc
sleep 2
DISPLAY_UID=$(id -u waydroid)
su -c "XDG_RUNTIME_DIR=/run/user/$DISPLAY_UID WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 LIBGL_ALWAYS_SOFTWARE=1 sway" waydroid &
sleep 5
WAYLAND_DISPLAY=$(ls /run/user/$DISPLAY_UID/wayland-* | head -1 | xargs -r basename)
nohup su -c "XDG_RUNTIME_DIR=/run/user/$DISPLAY_UID WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc 0.0.0.0 5900" waydroid > /dev/null 2>&1 &
sleep 3
ss -tlnp | grep 5900
'
```

If this shows port 5900 listening, user can connect: `vncviewer 10.1.3.136:5900`

## The Fix - Apply This
```bash
pct exec 103 -- sed -i 's|su -c "$WAYVNC_ENV wayvnc 0.0.0.0 5900" $DISPLAY_USER &|su -c "$WAYVNC_ENV nohup wayvnc 0.0.0.0 5900 > /dev/null 2\>\&1 \& disown" $DISPLAY_USER|' /usr/local/bin/start-waydroid.sh

pct exec 103 -- systemctl restart waydroid-vnc.service
sleep 10
pct exec 103 -- systemctl status waydroid-vnc.service
pct exec 103 -- ss -tlnp | grep 5900
```

## If That Doesn't Work

Read line 269 of `/usr/local/bin/start-waydroid.sh` in container 103 and try:
- Replace with `setsid wayvnc`
- Or use systemd User= instead of su
- Or check install/waydroid-install.sh for reference implementation

## Critical Files
- `/usr/local/bin/start-waydroid.sh` - startup script in container
- `/etc/systemd/system/waydroid-vnc.service` - systemd service
- `/home/waydroid/.config/wayvnc/config` - simplified config (WORKING)

## Container Info
- Container: 103
- IP: 10.1.3.136
- User: waydroid (UID 995)
- WayVNC version: 0.5.0 (old version, limited config options)

## User Status
- Patience: ZERO
- Needs: Working VNC connection NOW
- All commands must use: `pct exec 103 -- ...`

**GO FIX IT!**
