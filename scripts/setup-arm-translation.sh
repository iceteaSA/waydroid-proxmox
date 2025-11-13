#!/usr/bin/env bash

# Waydroid ARM Translation Layer Setup Script
# Implements ARM translation for running ARM-only Android apps on x86_64
# Supports both libhoudini (Intel) and libndk (AMD) translation layers
# Version: 1.0.0

set -euo pipefail

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

# ============================================================================
# Configuration
# ============================================================================

WAYDROID_DIR="/var/lib/waydroid"
WAYDROID_CFG="${WAYDROID_DIR}/waydroid.cfg"
WAYDROID_PROP="${WAYDROID_DIR}/waydroid.prop"
ROOTFS_DIR="${WAYDROID_DIR}/rootfs"
SYSTEM_DIR="${ROOTFS_DIR}/system"
VENDOR_DIR="${ROOTFS_DIR}/vendor"
CACHE_DIR="/var/cache/waydroid-arm"
LOG_DIR="/var/log/waydroid-arm"
BACKUP_DIR="${CACHE_DIR}/backup"

# Create directories
mkdir -p "$CACHE_DIR" "$LOG_DIR" "$BACKUP_DIR"

# Logging
LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Translation layer URLs (using waydroid_script method)
WAYDROID_SCRIPT_REPO="https://github.com/casualsnek/waydroid_script.git"
WAYDROID_SCRIPT_DIR="${CACHE_DIR}/waydroid_script"

# ============================================================================
# System Detection Functions
# ============================================================================

detect_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            return 0
            ;;
        aarch64|arm64)
            msg_warn "ARM translation not needed on ARM64 systems"
            echo "arm64"
            return 1
            ;;
        *)
            msg_error "Unsupported architecture: $arch"
            echo "unknown"
            return 1
            ;;
    esac
}

detect_cpu_vendor() {
    if [ -f /proc/cpuinfo ]; then
        local vendor
        vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | cut -d: -f2 | tr -d ' ')

        case "$vendor" in
            GenuineIntel)
                echo "intel"
                ;;
            AuthenticAMD)
                echo "amd"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
}

get_cpu_info() {
    echo -e "\n${BL}=== CPU Information ===${CL}"
    if [ -f /proc/cpuinfo ]; then
        echo "Model: $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')"
        echo "Vendor: $(detect_cpu_vendor)"
        echo "Architecture: $(detect_architecture)"
        echo "Cores: $(nproc)"
    fi
}

recommend_translation_layer() {
    local vendor
    vendor=$(detect_cpu_vendor)

    case "$vendor" in
        intel)
            echo "libhoudini"
            msg_info "Detected Intel CPU - libhoudini is recommended for better compatibility"
            ;;
        amd)
            echo "libndk"
            msg_info "Detected AMD CPU - libndk is recommended for better performance"
            ;;
        *)
            echo "libhoudini"
            msg_info "Unknown CPU vendor - defaulting to libhoudini (broader compatibility)"
            ;;
    esac
}

# ============================================================================
# Waydroid State Management
# ============================================================================

check_waydroid_installed() {
    if ! command -v waydroid &> /dev/null; then
        msg_error "Waydroid is not installed"
        msg_info "Please install Waydroid first: https://docs.waydro.id/"
        return 1
    fi

    if [ ! -d "$WAYDROID_DIR" ]; then
        msg_error "Waydroid directory not found at $WAYDROID_DIR"
        msg_info "Please initialize Waydroid first: waydroid init"
        return 1
    fi

    msg_ok "Waydroid installation verified"
    return 0
}

check_waydroid_running() {
    if waydroid status 2>&1 | grep -q "RUNNING"; then
        return 0
    else
        return 1
    fi
}

stop_waydroid() {
    if check_waydroid_running; then
        msg_info "Stopping Waydroid container..."
        waydroid container stop 2>/dev/null || true
        sleep 2

        # Force stop if still running
        if check_waydroid_running; then
            msg_warn "Force stopping Waydroid..."
            pkill -9 waydroid 2>/dev/null || true
            sleep 1
        fi

        msg_ok "Waydroid stopped"
    fi
}

start_waydroid() {
    msg_info "Starting Waydroid container..."
    if waydroid container start; then
        msg_ok "Waydroid container started"
        sleep 3
        return 0
    else
        msg_error "Failed to start Waydroid container"
        return 1
    fi
}

# ============================================================================
# Translation Layer Detection
# ============================================================================

get_current_translation_layer() {
    if [ -f "$WAYDROID_CFG" ]; then
        local bridge
        bridge=$(grep "ro.dalvik.vm.native.bridge" "$WAYDROID_CFG" 2>/dev/null | cut -d= -f2 | tr -d ' ')

        case "$bridge" in
            *libhoudini*)
                echo "libhoudini"
                return 0
                ;;
            *libndk*)
                echo "libndk"
                return 0
                ;;
            *)
                echo "none"
                return 1
                ;;
        esac
    fi

    echo "none"
    return 1
}

check_translation_installed() {
    local layer=$1
    local lib_file=""

    case "$layer" in
        libhoudini)
            lib_file="${SYSTEM_DIR}/lib64/libhoudini.so"
            ;;
        libndk)
            lib_file="${SYSTEM_DIR}/lib64/libndk_translation.so"
            ;;
        *)
            return 1
            ;;
    esac

    if [ -f "$lib_file" ]; then
        return 0
    else
        return 1
    fi
}

show_translation_status() {
    echo -e "\n${BL}=== ARM Translation Status ===${CL}"

    local current
    current=$(get_current_translation_layer)

    if [ "$current" = "none" ]; then
        msg_warn "No ARM translation layer installed"
    else
        msg_ok "Current translation layer: $current"

        # Check if library files exist
        if check_translation_installed "$current"; then
            msg_ok "Translation library files present"
        else
            msg_error "Translation library files missing!"
        fi

        # Show configured properties
        if [ -f "$WAYDROID_CFG" ]; then
            echo -e "\nConfigured properties:"
            grep "native.bridge\|cpu.abi\|dalvik.vm.isa" "$WAYDROID_CFG" | sed 's/^/  /'
        fi
    fi
}

# ============================================================================
# Backup and Restore
# ============================================================================

create_backup() {
    local backup_name="backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    msg_info "Creating backup at ${backup_path}..."
    mkdir -p "$backup_path"

    # Backup configuration files
    if [ -f "$WAYDROID_CFG" ]; then
        cp "$WAYDROID_CFG" "${backup_path}/waydroid.cfg"
    fi

    if [ -f "$WAYDROID_PROP" ]; then
        cp "$WAYDROID_PROP" "${backup_path}/waydroid.prop"
    fi

    # Save current state
    cat > "${backup_path}/state.txt" << EOF
Backup created: $(date)
Translation layer: $(get_current_translation_layer)
Architecture: $(detect_architecture)
CPU vendor: $(detect_cpu_vendor)
EOF

    echo "$backup_path" > "${BACKUP_DIR}/latest"
    msg_ok "Backup created at ${backup_path}"
}

restore_backup() {
    local latest_backup

    if [ ! -f "${BACKUP_DIR}/latest" ]; then
        msg_error "No backup found"
        return 1
    fi

    latest_backup=$(cat "${BACKUP_DIR}/latest")

    if [ ! -d "$latest_backup" ]; then
        msg_error "Backup directory not found: $latest_backup"
        return 1
    fi

    msg_info "Restoring from backup: $latest_backup"

    stop_waydroid

    # Restore configuration files
    if [ -f "${latest_backup}/waydroid.cfg" ]; then
        cp "${latest_backup}/waydroid.cfg" "$WAYDROID_CFG"
        msg_ok "Restored waydroid.cfg"
    fi

    if [ -f "${latest_backup}/waydroid.prop" ]; then
        cp "${latest_backup}/waydroid.prop" "$WAYDROID_PROP"
        msg_ok "Restored waydroid.prop"
    fi

    msg_ok "Backup restored successfully"
}

# ============================================================================
# Python Environment Setup
# ============================================================================

setup_python_environment() {
    msg_info "Setting up Python environment for waydroid_script..."

    # Install required packages
    local packages="python3 python3-venv python3-pip git curl"

    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y $packages
    elif command -v dnf &> /dev/null; then
        dnf install -y $packages
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm $packages
    else
        msg_error "Unsupported package manager"
        return 1
    fi

    msg_ok "Python environment ready"
}

# ============================================================================
# waydroid_script Installation
# ============================================================================

install_waydroid_script() {
    msg_info "Installing waydroid_script tool..."

    # Remove old installation
    if [ -d "$WAYDROID_SCRIPT_DIR" ]; then
        msg_info "Removing old waydroid_script installation..."
        rm -rf "$WAYDROID_SCRIPT_DIR"
    fi

    # Clone repository
    msg_info "Cloning waydroid_script repository..."
    if ! git clone --depth 1 "$WAYDROID_SCRIPT_REPO" "$WAYDROID_SCRIPT_DIR"; then
        msg_error "Failed to clone waydroid_script repository"
        return 1
    fi

    # Create virtual environment
    msg_info "Creating Python virtual environment..."
    cd "$WAYDROID_SCRIPT_DIR"
    python3 -m venv venv

    # Install dependencies
    msg_info "Installing Python dependencies..."
    if ! venv/bin/pip install --quiet -r requirements.txt; then
        msg_error "Failed to install Python dependencies"
        return 1
    fi

    msg_ok "waydroid_script installed successfully"
}

# ============================================================================
# Translation Layer Installation
# ============================================================================

install_translation_layer() {
    local layer=$1

    if [ "$layer" != "libhoudini" ] && [ "$layer" != "libndk" ]; then
        msg_error "Invalid translation layer: $layer"
        msg_info "Valid options: libhoudini, libndk"
        return 1
    fi

    msg_info "Installing $layer translation layer..."

    # Check if already installed
    local current
    current=$(get_current_translation_layer)

    if [ "$current" = "$layer" ]; then
        msg_warn "$layer is already installed"
        read -p "Reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    elif [ "$current" != "none" ]; then
        msg_warn "Another translation layer ($current) is already installed"
        msg_warn "Only one translation layer should be installed at a time"
        read -p "Remove $current and install $layer? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            uninstall_translation_layer "$current"
        else
            return 1
        fi
    fi

    # Create backup before installation
    create_backup

    # Stop Waydroid
    stop_waydroid

    # Setup environment if needed
    if [ ! -d "$WAYDROID_SCRIPT_DIR" ]; then
        setup_python_environment
        install_waydroid_script
    fi

    # Run waydroid_script to install translation layer
    msg_info "Running waydroid_script to install $layer..."
    msg_warn "This may take several minutes..."

    cd "$WAYDROID_SCRIPT_DIR"
    if ! venv/bin/python3 main.py install "$layer"; then
        msg_error "Failed to install $layer"
        msg_info "Attempting to restore from backup..."
        restore_backup
        return 1
    fi

    msg_ok "$layer installed successfully"

    # Verify installation
    verify_translation_installation "$layer"
}

uninstall_translation_layer() {
    local layer=${1:-$(get_current_translation_layer)}

    if [ "$layer" = "none" ]; then
        msg_warn "No translation layer installed"
        return 0
    fi

    msg_info "Uninstalling $layer translation layer..."

    # Create backup before uninstallation
    create_backup

    # Stop Waydroid
    stop_waydroid

    # Run waydroid_script to uninstall
    if [ -d "$WAYDROID_SCRIPT_DIR" ]; then
        cd "$WAYDROID_SCRIPT_DIR"
        venv/bin/python3 main.py uninstall "$layer" 2>/dev/null || true
    fi

    msg_ok "$layer uninstalled"
}

# ============================================================================
# Verification and Testing
# ============================================================================

verify_translation_installation() {
    local layer=$1

    msg_info "Verifying $layer installation..."

    # Check configuration file
    if [ ! -f "$WAYDROID_CFG" ]; then
        msg_error "Configuration file not found: $WAYDROID_CFG"
        return 1
    fi

    # Check native bridge property
    local bridge
    bridge=$(grep "ro.dalvik.vm.native.bridge" "$WAYDROID_CFG" 2>/dev/null | cut -d= -f2 | tr -d ' ')

    case "$layer" in
        libhoudini)
            if [[ "$bridge" != *"libhoudini.so" ]]; then
                msg_error "Native bridge property not set correctly"
                msg_info "Expected: libhoudini.so, Got: $bridge"
                return 1
            fi
            ;;
        libndk)
            if [[ "$bridge" != *"libndk_translation.so" ]]; then
                msg_error "Native bridge property not set correctly"
                msg_info "Expected: libndk_translation.so, Got: $bridge"
                return 1
            fi
            ;;
    esac

    msg_ok "Native bridge configuration verified"

    # Check CPU ABI list
    local abilist
    abilist=$(grep "ro.product.cpu.abilist" "$WAYDROID_CFG" 2>/dev/null | cut -d= -f2 | tr -d ' ')

    if [[ "$abilist" == *"arm64-v8a"* ]] && [[ "$abilist" == *"armeabi-v7a"* ]]; then
        msg_ok "CPU ABI list includes ARM architectures"
    else
        msg_warn "CPU ABI list may not be configured correctly: $abilist"
    fi

    # Check library files
    local lib_paths=()
    case "$layer" in
        libhoudini)
            lib_paths=(
                "${SYSTEM_DIR}/lib/libhoudini.so"
                "${SYSTEM_DIR}/lib64/libhoudini.so"
                "${SYSTEM_DIR}/lib/arm/libhoudini.so"
                "${SYSTEM_DIR}/lib64/arm64/libhoudini.so"
            )
            ;;
        libndk)
            lib_paths=(
                "${SYSTEM_DIR}/lib/libndk_translation.so"
                "${SYSTEM_DIR}/lib64/libndk_translation.so"
            )
            ;;
    esac

    local found_libs=0
    for lib_path in "${lib_paths[@]}"; do
        if [ -f "$lib_path" ]; then
            msg_ok "Found library: $lib_path"
            ((found_libs++))
        fi
    done

    if [ $found_libs -eq 0 ]; then
        msg_error "No translation library files found!"
        return 1
    fi

    msg_ok "Verification complete - $layer appears to be installed correctly"
    return 0
}

test_arm_translation() {
    msg_info "Testing ARM translation functionality..."

    if ! check_waydroid_running; then
        msg_info "Starting Waydroid for testing..."
        if ! start_waydroid; then
            msg_error "Cannot test - Waydroid failed to start"
            return 1
        fi
    fi

    echo -e "\n${BL}=== Translation Layer Test ===${CL}"

    # Show current configuration
    msg_info "Checking system properties..."

    # Use waydroid prop to check native bridge settings
    local bridge_prop
    bridge_prop=$(waydroid prop get ro.dalvik.vm.native.bridge 2>/dev/null || echo "unknown")
    echo "Native bridge: $bridge_prop"

    local abi_list
    abi_list=$(waydroid prop get ro.product.cpu.abilist 2>/dev/null || echo "unknown")
    echo "Supported ABIs: $abi_list"

    # Check if ARM ABIs are present
    if [[ "$abi_list" == *"arm"* ]]; then
        msg_ok "ARM architecture support detected"
    else
        msg_error "ARM architecture not in supported ABI list"
        return 1
    fi

    echo -e "\n${YW}=== Installation Complete ===${CL}"
    echo "To test ARM app installation, try installing an ARM-only app:"
    echo "  1. Download an ARM APK file"
    echo "  2. Install with: waydroid app install /path/to/app.apk"
    echo "  3. Launch the app through Waydroid UI"
    echo ""
    echo "Note: Not all ARM apps will work perfectly due to translation overhead"
    echo "      and potential compatibility issues."
}

check_app_architecture() {
    local apk_path=$1

    if [ ! -f "$apk_path" ]; then
        msg_error "APK file not found: $apk_path"
        return 1
    fi

    msg_info "Analyzing APK architecture: $apk_path"

    # Check if aapt is available
    if ! command -v aapt &> /dev/null; then
        msg_warn "aapt not installed - installing android-sdk build-tools..."
        if command -v apt-get &> /dev/null; then
            apt-get install -y aapt
        else
            msg_warn "Cannot install aapt - architecture detection unavailable"
            return 1
        fi
    fi

    # Extract native platform info
    local platforms
    platforms=$(aapt dump badging "$apk_path" 2>/dev/null | grep "native-code" || echo "none")

    if [ "$platforms" = "none" ]; then
        msg_info "APK appears to be architecture-independent (Java/Kotlin only)"
        echo "Translation layer: NOT REQUIRED"
    else
        echo "$platforms"

        if [[ "$platforms" == *"armeabi"* ]] || [[ "$platforms" == *"arm64"* ]]; then
            msg_warn "APK contains ARM native libraries"
            echo "Translation layer: REQUIRED for x86_64 systems"
        elif [[ "$platforms" == *"x86"* ]]; then
            msg_ok "APK contains x86 native libraries"
            echo "Translation layer: NOT REQUIRED"
        fi
    fi
}

# ============================================================================
# Performance and Troubleshooting
# ============================================================================

show_performance_warnings() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════╗
║                       PERFORMANCE IMPACT WARNING                         ║
╚══════════════════════════════════════════════════════════════════════════╝

ARM translation allows x86_64 systems to run ARM-only Android apps through
binary translation. However, this comes with important trade-offs:

PERFORMANCE IMPACT:
  • Translation overhead: 20-40% performance reduction typical
  • Higher CPU usage and power consumption
  • Increased memory usage for translation cache
  • Some apps may experience lag or stuttering
  • Gaming performance significantly impacted

COMPATIBILITY LIMITATIONS:
  • Not all ARM apps will work correctly
  • Some apps may crash or behave unexpectedly
  • Hardware-specific ARM code may fail
  • JNI calls may have issues
  • DRM/license verification may fail

RECOMMENDATIONS:
  • Use native x86_64 apps when available
  • Test thoroughly before relying on ARM apps
  • Monitor system resources during usage
  • libhoudini: Better compatibility (Intel CPUs)
  • libndk: Better performance (AMD CPUs)
  • Only install ONE translation layer at a time

KNOWN ISSUES:
  • Cannot install both libhoudini and libndk simultaneously
  • Some games with anti-cheat may not work
  • Apps using SafetyNet may fail verification
  • Hardware acceleration may be limited

For best results, prefer native x86_64 Android apps when available.

EOF
}

show_troubleshooting_guide() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════╗
║                         TROUBLESHOOTING GUIDE                            ║
╚══════════════════════════════════════════════════════════════════════════╝

ISSUE: ARM apps won't install
SOLUTION:
  1. Verify translation layer is installed:
     $ sudo ./setup-arm-translation.sh status
  2. Check Waydroid is running:
     $ waydroid status
  3. Restart Waydroid after installing translation:
     $ waydroid container stop && waydroid container start

ISSUE: ARM apps crash on launch
SOLUTION:
  1. Check app architecture matches translation layer
  2. Try different translation layer (switch libhoudini ↔ libndk)
  3. Check logcat for errors:
     $ waydroid logcat
  4. Clear app data and restart

ISSUE: Poor performance with ARM apps
SOLUTION:
  1. Ensure only one translation layer installed
  2. Use recommended layer for your CPU (Intel→libhoudini, AMD→libndk)
  3. Close other apps to free up resources
  4. Consider using native x86_64 version if available

ISSUE: Translation layer installation fails
SOLUTION:
  1. Ensure Waydroid is initialized:
     $ waydroid init
  2. Stop Waydroid before installation:
     $ waydroid container stop
  3. Check disk space: at least 2GB free required
  4. Restore from backup if needed:
     $ sudo ./setup-arm-translation.sh restore

ISSUE: "Native bridge not enabled" error
SOLUTION:
  1. Verify configuration:
     $ grep native.bridge /var/lib/waydroid/waydroid.cfg
  2. Reinstall translation layer:
     $ sudo ./setup-arm-translation.sh install [libhoudini|libndk]

CHECKING LOGS:
  • Installation log: /var/log/waydroid-arm/
  • Waydroid logs: $ waydroid logcat
  • System logs: $ journalctl -u waydroid-container

GETTING HELP:
  • Waydroid docs: https://docs.waydro.id/
  • GitHub issues: https://github.com/waydroid/waydroid/issues
  • waydroid_script: https://github.com/casualsnek/waydroid_script

EOF
}

show_known_limitations() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════╗
║                          KNOWN LIMITATIONS                               ║
╚══════════════════════════════════════════════════════════════════════════╝

ARCHITECTURE LIMITATIONS:
  ✗ Cannot install both libhoudini and libndk simultaneously
  ✗ ARM apps will run slower than native x86_64 apps
  ✗ Some ARM-specific optimizations will not work
  ✗ Mixed-architecture APKs may have issues

APP COMPATIBILITY:
  ✗ Apps with SafetyNet checks may fail
  ✗ Banking apps with strong security may not work
  ✗ Games with anti-cheat systems may be blocked
  ✗ DRM-protected content may not play
  ✗ Apps using ARM-specific hardware features will fail

PERFORMANCE CHARACTERISTICS:
  ✗ 20-40% performance overhead from translation
  ✗ Higher battery/power consumption
  ✗ Increased memory usage
  ✗ Cache generation causes initial slowdown
  ✗ Some JIT compilation benefits lost

GAMING LIMITATIONS:
  ✗ Reduced FPS in demanding games
  ✗ Graphics may lag or stutter
  ✗ Online games may have latency issues
  ✗ Shader compilation may be slower
  ✗ Some games may crash or freeze

TECHNICAL LIMITATIONS:
  ✗ JNI calls have overhead
  ✗ Native debugging is complex
  ✗ Some system calls may fail
  ✗ Hardware sensors may not work correctly
  ✗ OpenGL/Vulkan translation limitations

RECOMMENDED ALTERNATIVES:
  ✓ Use native x86_64 APKs when available
  ✓ Check F-Droid for x86_64 builds
  ✓ Use web apps as alternative
  ✓ Run on actual ARM device for best performance
  ✓ Use Progressive Web Apps (PWAs) instead

TRANSLATION LAYER COMPARISON:
  libhoudini:
    + Better app compatibility
    + More stable and tested
    + Recommended for Intel CPUs
    - Slightly slower on AMD
    - Larger installation size

  libndk:
    + Better performance on AMD CPUs
    + Smaller installation size
    + Active development
    - Less app compatibility
    - May have stability issues

For production use, always prefer native x86_64 applications.

EOF
}

# ============================================================================
# Interactive Menu
# ============================================================================

show_menu() {
    cat << EOF

${GN}╔══════════════════════════════════════════════════════════════════════════╗
║            Waydroid ARM Translation Layer Setup Script                  ║
║                                                                          ║
║  Run ARM-only Android apps on x86_64 systems using binary translation   ║
╚══════════════════════════════════════════════════════════════════════════╝${CL}

${BL}System Information:${CL}
  Architecture: $(detect_architecture)
  CPU Vendor: $(detect_cpu_vendor)
  Recommended: $(recommend_translation_layer)
  Current Layer: $(get_current_translation_layer)

${BL}Available Commands:${CL}
  1) install libhoudini  - Install libhoudini (recommended for Intel CPUs)
  2) install libndk      - Install libndk (recommended for AMD CPUs)
  3) uninstall           - Remove current translation layer
  4) status              - Show translation layer status
  5) test                - Test ARM translation functionality
  6) verify <apk>        - Check if APK requires ARM translation
  7) restore             - Restore from backup
  8) warnings            - Show performance impact warnings
  9) troubleshoot        - Show troubleshooting guide
  10) limitations        - Show known limitations
  11) help               - Show detailed help

${YW}Examples:${CL}
  Install libhoudini:     $0 install libhoudini
  Install libndk:         $0 install libndk
  Check status:           $0 status
  Test translation:       $0 test
  Check APK architecture: $0 verify /path/to/app.apk
  Show warnings:          $0 warnings

${RD}Important:${CL} Only install ONE translation layer at a time!

EOF
}

show_detailed_help() {
    cat << EOF
${GN}Waydroid ARM Translation Layer Setup Script${CL}
${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}

DESCRIPTION:
  This script automates the installation and configuration of ARM translation
  layers for Waydroid, enabling x86_64 systems to run ARM-only Android apps.

SUPPORTED TRANSLATION LAYERS:
  • libhoudini  - Intel's translation layer (from Windows Subsystem for Android)
                  Best compatibility, recommended for Intel CPUs

  • libndk      - Google's translation layer (from ChromeOS firmware)
                  Better performance on AMD CPUs

COMMANDS:
  install <layer>    Install translation layer (libhoudini or libndk)
  uninstall [layer]  Remove translation layer
  status             Show current installation status
  test               Test ARM translation functionality
  verify <apk>       Check if APK requires ARM translation
  restore            Restore configuration from backup
  warnings           Display performance impact warnings
  troubleshoot       Show troubleshooting guide
  limitations        Show known limitations
  help               Display this help message

OPTIONS:
  --force            Skip confirmation prompts
  --no-backup        Don't create backup before changes
  --quiet            Minimal output

USAGE EXAMPLES:
  # Check system and current status
  $0 status

  # Install recommended translation layer
  $0 install \$(recommend_translation_layer)

  # Install specific translation layer
  $0 install libhoudini
  $0 install libndk

  # Switch translation layers
  $0 uninstall
  $0 install libndk

  # Test after installation
  $0 test

  # Check if an APK needs translation
  $0 verify /path/to/app.apk

  # Restore from backup if something went wrong
  $0 restore

REQUIREMENTS:
  • Waydroid must be installed and initialized
  • At least 2GB free disk space
  • Python 3.6+ with pip and venv
  • Git for downloading waydroid_script
  • Root/sudo access

CONFIGURATION FILES:
  • Main config: /var/lib/waydroid/waydroid.cfg
  • Properties: /var/lib/waydroid/waydroid.prop
  • Backups: /var/cache/waydroid-arm/backup/
  • Logs: /var/log/waydroid-arm/

HOW IT WORKS:
  1. Detects system architecture and CPU vendor
  2. Recommends optimal translation layer
  3. Downloads casualsnek's waydroid_script tool
  4. Creates backup of current configuration
  5. Stops Waydroid container
  6. Installs translation layer libraries
  7. Configures native bridge in Waydroid
  8. Updates CPU ABI list to include ARM
  9. Verifies installation
  10. Tests ARM app support

PERFORMANCE CONSIDERATIONS:
  • Expect 20-40% performance overhead
  • Higher CPU and memory usage
  • Gaming may have reduced FPS
  • Battery life impact on laptops
  • Initial slowdown during cache generation

TROUBLESHOOTING:
  • Check logs: /var/log/waydroid-arm/
  • Waydroid logs: waydroid logcat
  • Restart after installation
  • Try other translation layer
  • Restore from backup if issues occur

RESOURCES:
  • Waydroid docs: https://docs.waydro.id/
  • waydroid_script: https://github.com/casualsnek/waydroid_script
  • This script's log: $LOG_FILE

EOF
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    local command="${1:-}"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        msg_error "This script must be run as root"
        msg_info "Please run: sudo $0 $*"
        exit 1
    fi

    # Parse command
    case "$command" in
        install)
            local layer="${2:-}"
            if [ -z "$layer" ]; then
                msg_error "Please specify translation layer: libhoudini or libndk"
                msg_info "Recommended for your system: $(recommend_translation_layer)"
                exit 1
            fi

            check_waydroid_installed || exit 1
            get_cpu_info
            show_performance_warnings

            read -p "Continue with installation? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                install_translation_layer "$layer"
                echo ""
                msg_info "Installation complete! Testing translation layer..."
                test_arm_translation
            fi
            ;;

        uninstall)
            local layer="${2:-}"
            check_waydroid_installed || exit 1

            if [ -z "$layer" ]; then
                layer=$(get_current_translation_layer)
            fi

            if [ "$layer" = "none" ]; then
                msg_warn "No translation layer installed"
                exit 0
            fi

            read -p "Uninstall $layer? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                uninstall_translation_layer "$layer"
            fi
            ;;

        status)
            check_waydroid_installed || exit 1
            get_cpu_info
            show_translation_status
            ;;

        test)
            check_waydroid_installed || exit 1
            test_arm_translation
            ;;

        verify)
            local apk_path="${2:-}"
            if [ -z "$apk_path" ]; then
                msg_error "Please specify APK file path"
                exit 1
            fi
            check_app_architecture "$apk_path"
            ;;

        restore)
            check_waydroid_installed || exit 1
            restore_backup
            ;;

        warnings)
            show_performance_warnings
            ;;

        troubleshoot)
            show_troubleshooting_guide
            ;;

        limitations)
            show_known_limitations
            ;;

        help|--help|-h)
            show_detailed_help
            ;;

        "")
            show_menu
            ;;

        *)
            msg_error "Unknown command: $command"
            echo ""
            show_menu
            exit 1
            ;;
    esac
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
