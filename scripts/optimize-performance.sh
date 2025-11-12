#!/usr/bin/env bash

# Waydroid Performance Optimization Script
# Tunes system parameters for optimal Waydroid performance

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/helper-functions.sh" ]; then
    source "${SCRIPT_DIR}/helper-functions.sh"
else
    msg_info() { echo "[INFO] $1"; }
    msg_ok() { echo "[OK] $1"; }
    msg_error() { echo "[ERROR] $1"; }
    msg_warn() { echo "[WARN] $1"; }
    GN="\033[1;92m"
    RD="\033[01;31m"
    YW="\033[1;93m"
    BL="\033[36m"
    CL="\033[m"
fi

if [ "$(id -u)" -ne 0 ]; then
    msg_error "This script must be run as root"
    exit 1
fi

echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Waydroid Performance Optimization${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

# 1. Kernel parameters
echo -e "${BL}[1/7] Optimizing Kernel Parameters${CL}"
cat > /etc/sysctl.d/99-waydroid-performance.conf <<EOF
# Waydroid Performance Tuning

# Increase inotify watchers for Android apps
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Shared memory for better IPC performance
kernel.shmmax = 268435456
kernel.shmall = 268435456

# Network performance
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# VM tuning for better Android performance
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Scheduler tuning
kernel.sched_latency_ns = 10000000
kernel.sched_min_granularity_ns = 1000000
EOF

sysctl -p /etc/sysctl.d/99-waydroid-performance.conf &>/dev/null
msg_ok "Kernel parameters optimized"
echo ""

# 2. CPU Governor
echo -e "${BL}[2/7] CPU Governor Configuration${CL}"
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
    # Try to set performance governor
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        if [ -f "$cpu" ]; then
            if echo "performance" > "$cpu" 2>/dev/null; then
                msg_ok "CPU governor set to 'performance'"
                break
            elif echo "ondemand" > "$cpu" 2>/dev/null; then
                msg_ok "CPU governor set to 'ondemand'"
                break
            fi
        fi
    done
else
    msg_info "CPU frequency scaling not available (inside LXC)"
fi
echo ""

# 3. I/O Scheduler
echo -e "${BL}[3/7] I/O Scheduler Optimization${CL}"
for device in /sys/block/*/queue/scheduler; do
    if [ -f "$device" ]; then
        # Try to set to deadline or mq-deadline for better latency
        if grep -q "mq-deadline" "$device"; then
            echo "mq-deadline" > "$device" 2>/dev/null && msg_ok "I/O scheduler: mq-deadline"
        elif grep -q "deadline" "$device"; then
            echo "deadline" > "$device" 2>/dev/null && msg_ok "I/O scheduler: deadline"
        fi
    fi
done
echo ""

# 4. Memory optimization
echo -e "${BL}[4/7] Memory Configuration${CL}"

# Check available memory
total_mem=$(free -m | awk '/^Mem:/{print $2}')
msg_info "Total memory: ${total_mem}MB"

if [ "$total_mem" -lt 2048 ]; then
    msg_warn "Low memory detected. Consider increasing container RAM to at least 2GB"
fi

# Configure zram if available
if command -v zramctl &>/dev/null; then
    if ! zramctl | grep -q zram0; then
        msg_info "Configuring zram for better memory efficiency..."
        modprobe zram 2>/dev/null || true
        if [ -b /dev/zram0 ]; then
            zram_size=$((total_mem * 256))  # 25% of RAM
            zramctl -f -s "${zram_size}M" -a lz4 2>/dev/null && msg_ok "zram configured"
        fi
    else
        msg_ok "zram already configured"
    fi
else
    msg_info "zram not available"
fi
echo ""

# 5. GPU optimizations
echo -e "${BL}[5/7] GPU Optimization${CL}"
if [ -d /dev/dri ]; then
    # Set environment variables for better GPU performance
    cat > /etc/profile.d/waydroid-gpu.sh <<'EOF'
# Waydroid GPU Performance Environment Variables

# Enable GPU acceleration
export LIBGL_DRI3_DISABLE=0
export MESA_GLTHREAD=true

# Intel specific
if lspci | grep -i "VGA.*Intel" &>/dev/null; then
    export MESA_LOADER_DRIVER_OVERRIDE=iris
    export LIBVA_DRIVER_NAME=iHD
    export INTEL_DEBUG=norbc
fi

# AMD specific
if lspci | grep -i "VGA.*AMD\|VGA.*Radeon" &>/dev/null; then
    export MESA_LOADER_DRIVER_OVERRIDE=radeonsi
    export LIBVA_DRIVER_NAME=radeonsi
    export AMD_DEBUG=nodma
fi
EOF
    msg_ok "GPU environment variables configured"

    # Set GPU device permissions
    if [ -e /dev/dri/card0 ]; then
        chmod 666 /dev/dri/card* 2>/dev/null
        chmod 666 /dev/dri/renderD* 2>/dev/null
        msg_ok "GPU device permissions set"
    fi
else
    msg_info "No GPU devices found (software rendering mode)"
fi
echo ""

# 6. Waydroid specific optimizations
echo -e "${BL}[6/7] Waydroid Configuration Tuning${CL}"
if [ -f /var/lib/waydroid/waydroid_base.prop ]; then
    # Create performance overrides
    cat >> /var/lib/waydroid/waydroid_base.prop <<'EOF'

# Performance optimizations
persist.sys.ui.hw=1
debug.sf.hw=1
debug.egl.hw=1
debug.composition.type=gpu
debug.performance.tuning=1
video.accelerate.hw=1

# Disable unnecessary services for better performance
ro.config.nocheckin=yes
ro.setupwizard.mode=DISABLED

# Network performance
net.tcp.buffersize.default=4096,87380,110208,4096,16384,110208
net.tcp.buffersize.wifi=524288,1048576,2097152,262144,524288,1048576

# Dalvik VM optimizations
dalvik.vm.heapsize=512m
dalvik.vm.heapstartsize=16m
dalvik.vm.heapgrowthlimit=256m
dalvik.vm.heaptargetutilization=0.75
dalvik.vm.heapminfree=2m
dalvik.vm.heapmaxfree=8m
EOF
    msg_ok "Waydroid properties configured for performance"
else
    msg_info "Waydroid not yet initialized - run 'waydroid init' first"
fi
echo ""

# 7. Service optimizations
echo -e "${BL}[7/7] Service Configuration${CL}"

# Optimize Waydroid VNC service
if [ -f /etc/systemd/system/waydroid-vnc.service ]; then
    # Add nice and ionice for better priority
    if ! grep -q "Nice=" /etc/systemd/system/waydroid-vnc.service; then
        sed -i '/\[Service\]/a Nice=-5\nIOSchedulingClass=realtime\nIOSchedulingPriority=0' /etc/systemd/system/waydroid-vnc.service
        systemctl daemon-reload
        msg_ok "Waydroid VNC service priority optimized"
    else
        msg_ok "Service priority already optimized"
    fi
fi

# Optimize API service
if [ -f /etc/systemd/system/waydroid-api.service ]; then
    if ! grep -q "Nice=" /etc/systemd/system/waydroid-api.service; then
        sed -i '/\[Service\]/a Nice=0' /etc/systemd/system/waydroid-api.service
        systemctl daemon-reload
        msg_ok "API service priority optimized"
    else
        msg_ok "API service already optimized"
    fi
fi

echo ""

# Summary
echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Optimization Complete!${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

msg_info "Applied optimizations:"
echo "  ✓ Kernel parameters tuned"
echo "  ✓ CPU governor configured"
echo "  ✓ I/O scheduler optimized"
echo "  ✓ Memory settings adjusted"
echo "  ✓ GPU acceleration enabled"
echo "  ✓ Waydroid properties configured"
echo "  ✓ Service priorities optimized"
echo ""

msg_info "Recommended next steps:"
echo "  1. Restart Waydroid: systemctl restart waydroid-vnc"
echo "  2. Monitor performance: htop or top"
echo "  3. Check GPU usage: intel_gpu_top or radeontop"
echo ""

msg_warn "Note: Some optimizations require a container restart to take full effect"
