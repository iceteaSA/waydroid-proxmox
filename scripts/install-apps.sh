#!/usr/bin/env bash

# Waydroid Android App Installation Script
# Automates app installation from local files, URLs, F-Droid, and batch configs
# Features: verification, rollback, update checking, comprehensive logging

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

# Configuration
APP_CACHE_DIR="${APP_CACHE_DIR:-/var/cache/waydroid-apps}"
APP_LOG_DIR="${APP_LOG_DIR:-/var/log/waydroid-apps}"
ROLLBACK_DIR="${APP_CACHE_DIR}/rollback"
FDROID_REPO="${FDROID_REPO:-https://f-droid.org/repo}"
FDROID_INDEX_URL="${FDROID_REPO}/index-v1.jar"
MAX_DOWNLOAD_RETRIES=3
DOWNLOAD_TIMEOUT=300

# Create necessary directories
mkdir -p "$APP_CACHE_DIR" "$APP_LOG_DIR" "$ROLLBACK_DIR"

# Logging setup
LOG_FILE="${APP_LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Track installed apps for rollback
ROLLBACK_STATE_FILE="${ROLLBACK_DIR}/state-$(date +%Y%m%d-%H%M%S).json"
declare -a INSTALLED_APPS=()
declare -a FAILED_APPS=()

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

show_help() {
    cat << EOF
${GN}Waydroid Android App Installation Tool${CL}

Usage: $0 <command> [options]

Commands:
    install-apk <file|url>      Install APK from local file or URL
    install-fdroid <package>    Install app from F-Droid repository
    install-batch <config>      Install apps from YAML/JSON config file
    list-installed              List all installed Android apps
    check-updates               Check for updates of installed apps
    rollback                    Rollback last batch installation
    verify <apk>                Verify APK signature and integrity
    search-fdroid <query>       Search F-Droid repository

Options:
    --skip-verify              Skip signature verification
    --force                    Force installation over existing app
    --no-rollback              Don't create rollback point
    --help                     Show this help message

Examples:
    $0 install-apk /path/to/app.apk
    $0 install-apk https://example.com/app.apk
    $0 install-fdroid org.fdroid.fdroid
    $0 install-batch /etc/waydroid/apps.yaml
    $0 check-updates
    $0 rollback

Config file location: ${SCRIPT_DIR}/../config/apps-example.yaml
Log file: $LOG_FILE
EOF
}

# Check if Waydroid is ready
check_waydroid_ready() {
    if ! command -v waydroid &> /dev/null; then
        msg_error "Waydroid is not installed"
        return 1
    fi

    if ! waydroid status 2>&1 | grep -q "RUNNING"; then
        msg_warn "Waydroid container is not running. Starting..."
        if ! waydroid container start; then
            msg_error "Failed to start Waydroid container"
            return 1
        fi
        sleep 5
    fi

    # Wait for Android to be ready
    local max_wait=30
    local wait_count=0
    while [ $wait_count -lt $max_wait ]; do
        if waydroid app list &> /dev/null; then
            msg_ok "Waydroid is ready"
            return 0
        fi
        sleep 1
        ((wait_count++))
    done

    msg_error "Waydroid did not become ready in time"
    return 1
}

# Download file with retry and progress
download_file() {
    local url="$1"
    local output="$2"
    local retries=0

    msg_info "Downloading: $url"

    while [ $retries -lt $MAX_DOWNLOAD_RETRIES ]; do
        if curl -L --progress-bar --max-time "$DOWNLOAD_TIMEOUT" \
            -o "$output" "$url" 2>&1 | grep -E --line-buffered '###|%'; then
            msg_ok "Download completed: $(basename "$output")"
            return 0
        fi

        retries=$((retries + 1))
        if [ $retries -lt $MAX_DOWNLOAD_RETRIES ]; then
            msg_warn "Download failed, retrying ($retries/$MAX_DOWNLOAD_RETRIES)..."
            sleep 2
        fi
    done

    msg_error "Failed to download after $MAX_DOWNLOAD_RETRIES attempts"
    return 1
}

# Verify APK signature and integrity
verify_apk() {
    local apk_file="$1"
    local skip_verify="${2:-false}"

    if [ "$skip_verify" = "true" ]; then
        msg_warn "Skipping APK verification"
        return 0
    fi

    msg_info "Verifying APK: $(basename "$apk_file")"

    # Check file exists and is readable
    if [ ! -f "$apk_file" ]; then
        msg_error "APK file not found: $apk_file"
        return 1
    fi

    if [ ! -r "$apk_file" ]; then
        msg_error "APK file not readable: $apk_file"
        return 1
    fi

    # Check file size (minimum 1KB, maximum 2GB)
    local file_size=$(stat -f%z "$apk_file" 2>/dev/null || stat -c%s "$apk_file" 2>/dev/null || echo 0)
    if [ "$file_size" -lt 1024 ]; then
        msg_error "APK file too small (< 1KB), possibly corrupted"
        return 1
    fi

    if [ "$file_size" -gt 2147483648 ]; then
        msg_error "APK file too large (> 2GB), possibly not a valid APK"
        return 1
    fi

    # Check file is a valid ZIP (APK is a ZIP archive)
    if ! unzip -t "$apk_file" &> /dev/null; then
        msg_error "APK file is corrupted or not a valid ZIP archive"
        return 1
    fi

    # Check for AndroidManifest.xml
    if ! unzip -l "$apk_file" | grep -q "AndroidManifest.xml"; then
        msg_error "APK missing AndroidManifest.xml"
        return 1
    fi

    # Verify signature using aapt if available
    if command -v aapt &> /dev/null; then
        if ! aapt dump badging "$apk_file" &> /dev/null; then
            msg_error "APK failed aapt verification"
            return 1
        fi
    fi

    # Check for signature files
    if ! unzip -l "$apk_file" | grep -q "META-INF/.*\(RSA\|DSA\|EC\)"; then
        msg_warn "APK may not be signed (no signature files found)"
    fi

    msg_ok "APK verification passed"
    return 0
}

# Get package name from APK
get_package_name() {
    local apk_file="$1"

    if command -v aapt &> /dev/null; then
        aapt dump badging "$apk_file" 2>/dev/null | grep "package: name=" | \
            sed "s/.*name='\([^']*\)'.*/\1/"
    else
        # Fallback: try to extract from manifest
        unzip -p "$apk_file" AndroidManifest.xml 2>/dev/null | \
            strings | grep -A 1 "package" | tail -1 || echo "unknown"
    fi
}

# Get installed version of a package
get_installed_version() {
    local package="$1"
    waydroid app list 2>/dev/null | grep "^$package" | awk '{print $2}' || echo ""
}

# Create rollback point
create_rollback_point() {
    local package="$1"
    local version="$2"

    cat >> "$ROLLBACK_STATE_FILE" << EOF
{
  "package": "$package",
  "version": "$version",
  "timestamp": "$(date -Iseconds)",
  "action": "installed"
}
EOF
}

# Save current state before installation
save_current_state() {
    msg_info "Creating rollback point..."
    waydroid app list > "${ROLLBACK_DIR}/apps-before-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
}

# ============================================================================
# Installation Functions
# ============================================================================

# Install APK from local file
install_local_apk() {
    local apk_file="$1"
    local skip_verify="${2:-false}"
    local force="${3:-false}"

    if [ ! -f "$apk_file" ]; then
        msg_error "APK file not found: $apk_file"
        return 1
    fi

    # Verify APK
    if ! verify_apk "$apk_file" "$skip_verify"; then
        msg_error "APK verification failed"
        return 1
    fi

    # Get package name
    local package_name=$(get_package_name "$apk_file")
    if [ -z "$package_name" ] || [ "$package_name" = "unknown" ]; then
        msg_error "Could not determine package name"
        return 1
    fi

    msg_info "Package: $package_name"

    # Check if already installed
    local installed_version=$(get_installed_version "$package_name")
    if [ -n "$installed_version" ] && [ "$force" != "true" ]; then
        msg_warn "Package already installed (version: $installed_version)"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            msg_info "Installation cancelled"
            return 0
        fi
    fi

    # Install APK
    msg_info "Installing $(basename "$apk_file")..."
    if waydroid app install "$apk_file"; then
        msg_ok "Successfully installed: $package_name"
        INSTALLED_APPS+=("$package_name")
        create_rollback_point "$package_name" "$(get_installed_version "$package_name")"
        return 0
    else
        msg_error "Failed to install: $package_name"
        FAILED_APPS+=("$package_name")
        return 1
    fi
}

# Install APK from URL
install_url_apk() {
    local url="$1"
    local skip_verify="${2:-false}"
    local force="${3:-false}"

    # Generate cache filename
    local filename=$(basename "$url" | sed 's/[^a-zA-Z0-9._-]/_/g')
    local cache_file="${APP_CACHE_DIR}/${filename}"

    # Download APK
    if ! download_file "$url" "$cache_file"; then
        msg_error "Failed to download APK from URL"
        return 1
    fi

    # Install downloaded APK
    install_local_apk "$cache_file" "$skip_verify" "$force"
    local result=$?

    # Clean up cache file if installation failed
    if [ $result -ne 0 ]; then
        rm -f "$cache_file"
    fi

    return $result
}

# Search F-Droid repository
search_fdroid() {
    local query="$1"
    local index_file="${APP_CACHE_DIR}/fdroid-index.json"

    msg_info "Searching F-Droid for: $query"

    # Download F-Droid index if not cached or older than 24 hours
    if [ ! -f "$index_file" ] || [ $(find "$index_file" -mtime +1 2>/dev/null | wc -l) -gt 0 ]; then
        msg_info "Updating F-Droid index..."
        local index_jar="${APP_CACHE_DIR}/index-v1.jar"

        if download_file "$FDROID_INDEX_URL" "$index_jar"; then
            unzip -p "$index_jar" index-v1.json > "$index_file" 2>/dev/null || {
                msg_error "Failed to extract F-Droid index"
                return 1
            }
            rm -f "$index_jar"
        else
            msg_error "Failed to download F-Droid index"
            return 1
        fi
    fi

    # Search index
    if command -v jq &> /dev/null; then
        jq -r ".packages | to_entries[] | select(.key | contains(\"$query\")) |
            \"\(.key): \(.value.metadata.name // \"N/A\") - \(.value.metadata.summary // \"No description\")\"" \
            "$index_file" 2>/dev/null | head -20
    else
        grep -i "$query" "$index_file" | head -20
    fi
}

# Install app from F-Droid
install_fdroid_app() {
    local package="$1"
    local skip_verify="${2:-false}"
    local force="${3:-false}"

    msg_info "Installing from F-Droid: $package"

    local index_file="${APP_CACHE_DIR}/fdroid-index.json"

    # Ensure we have the index
    if [ ! -f "$index_file" ]; then
        search_fdroid "$package" > /dev/null || return 1
    fi

    # Get APK download URL
    local apk_info
    if command -v jq &> /dev/null; then
        apk_info=$(jq -r ".packages.\"$package\" // empty" "$index_file" 2>/dev/null)

        if [ -z "$apk_info" ]; then
            msg_error "Package not found in F-Droid: $package"
            msg_info "Try searching with: $0 search-fdroid <keyword>"
            return 1
        fi

        # Get latest version APK name
        local apk_name=$(echo "$apk_info" | jq -r '.versions[0].file.name // empty' 2>/dev/null)

        if [ -z "$apk_name" ]; then
            msg_error "No APK found for package: $package"
            return 1
        fi

        local apk_url="${FDROID_REPO}/${apk_name}"
        local apk_hash=$(echo "$apk_info" | jq -r '.versions[0].file.sha256 // empty' 2>/dev/null)

        msg_info "Downloading: $apk_name"
        msg_info "URL: $apk_url"

        # Download and verify
        local cache_file="${APP_CACHE_DIR}/$(basename "$apk_name")"
        if download_file "$apk_url" "$cache_file"; then
            # Verify hash if available
            if [ -n "$apk_hash" ] && command -v sha256sum &> /dev/null; then
                local computed_hash=$(sha256sum "$cache_file" | awk '{print $1}')
                if [ "$computed_hash" != "$apk_hash" ]; then
                    msg_error "Hash verification failed!"
                    msg_error "Expected: $apk_hash"
                    msg_error "Got: $computed_hash"
                    rm -f "$cache_file"
                    return 1
                fi
                msg_ok "Hash verification passed"
            fi

            # Install the APK
            install_local_apk "$cache_file" "$skip_verify" "$force"
            return $?
        else
            msg_error "Failed to download APK from F-Droid"
            return 1
        fi
    else
        msg_error "jq is required for F-Droid installation. Please install it."
        return 1
    fi
}

# Parse YAML config (simple parser)
parse_yaml_config() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        msg_error "Config file not found: $config_file"
        return 1
    fi

    # Check file extension
    case "$config_file" in
        *.yaml|*.yml)
            parse_yaml "$config_file"
            ;;
        *.json)
            parse_json "$config_file"
            ;;
        *)
            msg_error "Unsupported config format. Use .yaml, .yml, or .json"
            return 1
            ;;
    esac
}

# Simple YAML parser for app lists
parse_yaml() {
    local file="$1"
    local in_apps=false
    local app_type=""

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Detect apps section
        if [[ "$line" =~ ^apps:[[:space:]]*$ ]]; then
            in_apps=true
            continue
        fi

        if [ "$in_apps" = true ]; then
            # Detect app type section
            if [[ "$line" =~ ^[[:space:]]+(local|url|fdroid):[[:space:]]*$ ]]; then
                app_type=$(echo "$line" | sed 's/^[[:space:]]*//;s/:[[:space:]]*$//')
                continue
            fi

            # Parse app entry
            if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.+)$ ]]; then
                local app_spec="${BASH_REMATCH[1]}"

                case "$app_type" in
                    local|url)
                        echo "$app_type|$app_spec"
                        ;;
                    fdroid)
                        # Can be package name or path: package
                        if [[ "$app_spec" =~ ^path:[[:space:]]*(.+)$ ]]; then
                            echo "local|${BASH_REMATCH[1]}"
                        elif [[ "$app_spec" =~ ^url:[[:space:]]*(.+)$ ]]; then
                            echo "url|${BASH_REMATCH[1]}"
                        else
                            echo "fdroid|$app_spec"
                        fi
                        ;;
                esac
            fi
        fi
    done < "$file"
}

# Simple JSON parser for app lists
parse_json() {
    local file="$1"

    if ! command -v jq &> /dev/null; then
        msg_error "jq is required for JSON config parsing. Please install it."
        return 1
    fi

    # Parse local apps
    jq -r '.apps.local[]? // empty | "local|\(.)"' "$file" 2>/dev/null

    # Parse URL apps
    jq -r '.apps.url[]? // empty | "url|\(.)"' "$file" 2>/dev/null

    # Parse F-Droid apps
    jq -r '.apps.fdroid[]? // empty |
        if type == "string" then "fdroid|\(.)"
        elif .path then "local|\(.path)"
        elif .url then "url|\(.url)"
        elif .package then "fdroid|\(.package)"
        else empty end' "$file" 2>/dev/null
}

# Batch install from config file
install_batch() {
    local config_file="$1"
    local skip_verify="${2:-false}"
    local force="${3:-false}"

    msg_info "Starting batch installation from: $config_file"

    # Save current state for rollback
    save_current_state

    local total=0
    local success=0
    local failed=0

    # Parse and install apps
    while IFS='|' read -r type spec; do
        total=$((total + 1))
        msg_info "[$total] Installing: $spec (type: $type)"

        case "$type" in
            local)
                if install_local_apk "$spec" "$skip_verify" "$force"; then
                    success=$((success + 1))
                else
                    failed=$((failed + 1))
                fi
                ;;
            url)
                if install_url_apk "$spec" "$skip_verify" "$force"; then
                    success=$((success + 1))
                else
                    failed=$((failed + 1))
                fi
                ;;
            fdroid)
                if install_fdroid_app "$spec" "$skip_verify" "$force"; then
                    success=$((success + 1))
                else
                    failed=$((failed + 1))
                fi
                ;;
            *)
                msg_error "Unknown app type: $type"
                failed=$((failed + 1))
                ;;
        esac

        echo "---"
    done < <(parse_yaml_config "$config_file")

    # Summary
    echo ""
    msg_info "========================================"
    msg_info "Batch Installation Summary"
    msg_info "========================================"
    msg_info "Total apps: $total"
    msg_ok "Successful: $success"
    if [ $failed -gt 0 ]; then
        msg_error "Failed: $failed"
    else
        msg_info "Failed: $failed"
    fi
    msg_info "========================================"

    if [ $failed -gt 0 ]; then
        msg_warn "Some installations failed. Check the log: $LOG_FILE"
        return 1
    fi

    return 0
}

# List installed apps
list_installed_apps() {
    msg_info "Installed Android apps:"
    echo ""

    if ! waydroid app list 2>/dev/null; then
        msg_error "Failed to list apps. Is Waydroid running?"
        return 1
    fi
}

# Check for updates
check_updates() {
    msg_info "Checking for updates..."

    local index_file="${APP_CACHE_DIR}/fdroid-index.json"

    # Update F-Droid index
    if [ -f "$index_file" ]; then
        rm -f "$index_file"
    fi
    search_fdroid "dummy" > /dev/null 2>&1

    if [ ! -f "$index_file" ] || ! command -v jq &> /dev/null; then
        msg_warn "Cannot check for updates (F-Droid index or jq not available)"
        return 1
    fi

    msg_info "Comparing installed apps with F-Droid repository..."

    local updates_found=0

    while read -r package version; do
        # Check if package exists in F-Droid
        local latest_version=$(jq -r ".packages.\"$package\".versions[0].versionName // empty" \
            "$index_file" 2>/dev/null)

        if [ -n "$latest_version" ] && [ "$latest_version" != "$version" ]; then
            echo "${YW}Update available:${CL} $package"
            echo "  Current: $version"
            echo "  Latest:  $latest_version"
            updates_found=$((updates_found + 1))
        fi
    done < <(waydroid app list 2>/dev/null | tail -n +2 | awk '{print $1, $2}')

    if [ $updates_found -eq 0 ]; then
        msg_ok "All apps are up to date!"
    else
        msg_info "Found $updates_found update(s) available"
    fi
}

# Rollback last batch installation
rollback_installation() {
    msg_warn "Rolling back last installation..."

    if [ ! -f "$ROLLBACK_STATE_FILE" ]; then
        msg_error "No rollback state file found"
        return 1
    fi

    # Extract packages from rollback state
    local packages=$(grep -o '"package": "[^"]*"' "$ROLLBACK_STATE_FILE" | cut -d'"' -f4)

    if [ -z "$packages" ]; then
        msg_error "No packages found in rollback state"
        return 1
    fi

    msg_info "Uninstalling packages from last installation:"
    echo "$packages"

    local count=0
    while read -r package; do
        msg_info "Uninstalling: $package"
        if waydroid app uninstall "$package" 2>/dev/null; then
            msg_ok "Uninstalled: $package"
            count=$((count + 1))
        else
            msg_error "Failed to uninstall: $package"
        fi
    done <<< "$packages"

    msg_ok "Rollback complete. Uninstalled $count package(s)"

    # Archive rollback state
    mv "$ROLLBACK_STATE_FILE" "${ROLLBACK_STATE_FILE}.done"

    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-}"
    shift || true

    # Parse global options
    local skip_verify=false
    local force=false
    local no_rollback=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --skip-verify)
                skip_verify=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --no-rollback)
                no_rollback=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    case "$command" in
        install-apk)
            local target="${1:-}"
            if [ -z "$target" ]; then
                msg_error "Missing APK file or URL"
                show_help
                exit 1
            fi

            check_waydroid_ready || exit 1

            if [[ "$target" =~ ^https?:// ]]; then
                install_url_apk "$target" "$skip_verify" "$force"
            else
                install_local_apk "$target" "$skip_verify" "$force"
            fi
            ;;

        install-fdroid)
            local package="${1:-}"
            if [ -z "$package" ]; then
                msg_error "Missing package name"
                show_help
                exit 1
            fi

            check_waydroid_ready || exit 1
            install_fdroid_app "$package" "$skip_verify" "$force"
            ;;

        install-batch)
            local config="${1:-}"
            if [ -z "$config" ]; then
                msg_error "Missing config file"
                show_help
                exit 1
            fi

            check_waydroid_ready || exit 1
            install_batch "$config" "$skip_verify" "$force"
            ;;

        list-installed|list)
            check_waydroid_ready || exit 1
            list_installed_apps
            ;;

        check-updates|updates)
            check_waydroid_ready || exit 1
            check_updates
            ;;

        search-fdroid|search)
            local query="${1:-}"
            if [ -z "$query" ]; then
                msg_error "Missing search query"
                show_help
                exit 1
            fi
            search_fdroid "$query"
            ;;

        verify)
            local apk="${1:-}"
            if [ -z "$apk" ]; then
                msg_error "Missing APK file"
                show_help
                exit 1
            fi
            verify_apk "$apk" "$skip_verify"
            ;;

        rollback)
            check_waydroid_ready || exit 1
            rollback_installation
            ;;

        --help|help|"")
            show_help
            exit 0
            ;;

        *)
            msg_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
