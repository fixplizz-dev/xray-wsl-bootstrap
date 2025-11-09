#!/bin/bash
set -euo pipefail

# Load common functions
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/validate.sh"

# Script constants
readonly INSTALL_SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="0.1.0"

#######################################
# Check system requirements before installation
#######################################
check_system_requirements() {
    log_info "Checking system requirements..."

    # Check bash version
    if ! check_bash_version; then
        log_error "Bash 5.x or higher is required"
        log_error "Please upgrade your bash version"
        exit 1
    fi

    # Check WSL environment
    if [[ ! -f /proc/version ]] || ! grep -qi "microsoft\|wsl" /proc/version; then
        log_error "This script must be run inside WSL (Windows Subsystem for Linux)"
        exit 1
    fi

    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" != "ubuntu" ]] || ! version_ge "$VERSION_ID" "22.04"; then
            log_warning "Ubuntu 22.04+ is recommended for best compatibility"
        fi
    fi

    # Check systemd
    if ! systemctl --version >/dev/null 2>&1; then
        log_error "systemd is required but not available"
        log_error "Please enable systemd in your WSL distribution"
        exit 1
    fi

    # Check required commands
    local required_commands=("curl" "jq" "unzip" "systemctl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            log_error "Please install missing packages: sudo apt update && sudo apt install -y curl jq unzip"
            exit 1
        fi
    done

    log_success "System requirements check passed"
}

# Download URLs and paths
readonly XRAY_RELEASE_API="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
readonly XRAY_INSTALL_DIR="/usr/local/bin"
readonly XRAY_CONFIG_DIR="/etc/xray"
readonly XRAY_LOG_DIR="/var/log/xray"
readonly XRAY_SERVICE_NAME="xray-wsl"

# Architecture detection
readonly ARCH="$(uname -m)"
case "$ARCH" in
    x86_64) readonly XRAY_ARCH="linux-64" ;;
    aarch64|arm64) readonly XRAY_ARCH="linux-arm64-v8a" ;;
    *)
        log_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

#######################################
# Print script usage information
# Globals:
#   INSTALL_SCRIPT_NAME
# Arguments:
#   None
# Returns:
#   0
#######################################
show_help() {
    local script_name="$INSTALL_SCRIPT_NAME"
    cat << EOF
Usage: $script_name [OPTIONS]

Installs Xray core, creates configuration, and sets up systemd service.

OPTIONS:
    --help, -h          Show this help message
    --config-only       Only generate configuration, don't install Xray binary
    --service-only      Only setup systemd service, assume Xray already installed
    --skip-service      Install Xray and generate config, but skip systemd setup
    --force             Force reinstall even if Xray already exists
    --dry-run          Show what would be done without making changes
    --version VERSION   Install specific Xray version (default: latest)

EXAMPLES:
    # Full installation
    sudo ./$script_name

    # Only generate configuration
    ./$script_name --config-only

    # Install specific version
    sudo ./$script_name --version v1.8.0

    # Dry run to see what would happen
    sudo ./$script_name --dry-run

PREREQUISITES:
    - Valid .env file with server configuration
    - Root privileges (for binary installation and systemd service)
    - Ubuntu 22.04+ or compatible system with systemd

EXIT CODES:
    0   Success
    1   General error
    10  Missing .env file or invalid configuration
    11  System requirements not met
    12  Download or installation failed
    13  Service setup failed

ENVIRONMENT:
    All configuration loaded from .env file.
    See .env.example for required variables.
EOF
}

#######################################
# Check system requirements
# Arguments:
#   None
# Returns:
#   0 if requirements met, 11 otherwise
#######################################
check_system_requirements() {
    log_info "$(get_localized_message "install.checking_requirements")"

    # Check OS compatibility
    if [[ ! -f /etc/os-release ]]; then
        log_error "$(get_localized_message "install.os_unsupported")"
        return 11
    fi

    source /etc/os-release
    case "$ID" in
        ubuntu|debian)
            log_debug "Detected compatible OS: $PRETTY_NAME"
            ;;
        *)
            log_warn "$(get_localized_message "install.os_untested" "$PRETTY_NAME")"
            ;;
    esac

    # Check systemd
    if ! has_systemd; then
        log_error "$(get_localized_message "install.systemd_required")"
        return 11
    fi

    # Check architecture
    log_info "$(get_localized_message "install.arch_detected" "$ARCH" "$XRAY_ARCH")"

    return 0
}

#######################################
# Get latest Xray release information
# Arguments:
#   version - specific version or "latest"
# Returns:
#   0 on success, 12 on failure
# Outputs:
#   JSON release info to stdout
#######################################
get_xray_release_info() {
    local version="${1:-latest}"
    local api_url="$XRAY_RELEASE_API"

    if [[ "$version" != "latest" ]]; then
        api_url="https://api.github.com/repos/XTLS/Xray-core/releases/tags/$version"
    fi

    log_debug "Fetching release info from: $api_url"

    if ! curl --silent --fail --max-time 30 "$api_url"; then
        log_error "$(get_localized_message "install.release_fetch_failed")"
        return 12
    fi
}

#######################################
# Download and extract Xray binary
# Arguments:
#   release_json - JSON release information
#   target_dir - directory to install binary
#   dry_run - true/false
# Returns:
#   0 on success, 12 on failure
#######################################
install_xray_binary() {
    local release_json="$1"
    local target_dir="$2"
    local dry_run="${3:-false}"

    # Parse release information
    local version tag_name download_url
    version=$(echo "$release_json" | jq -r '.tag_name')
    tag_name="$version"

    # Find download URL for our architecture
    download_url=$(echo "$release_json" | jq -r \
        --arg arch "$XRAY_ARCH" \
        '.assets[] | select(.name | contains($arch) and contains(".zip")) | .browser_download_url')

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        log_error "$(get_localized_message "install.no_binary_for_arch" "$XRAY_ARCH")"
        return 12
    fi

    log_info "$(get_localized_message "install.downloading_xray" "$version")"
    log_debug "Download URL: $download_url"

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would download: $download_url"
        log_info "[DRY RUN] Would extract to: $target_dir"
        return 0
    fi

    # Create temporary directory for download
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT

    local zip_file="$temp_dir/xray.zip"

    # Download Xray
    if ! curl --location --fail --max-time 300 --output "$zip_file" "$download_url"; then
        log_error "$(get_localized_message "install.download_failed")"
        return 12
    fi

    # Verify download
    if [[ ! -f "$zip_file" || ! -s "$zip_file" ]]; then
        log_error "$(get_localized_message "install.download_empty")"
        return 12
    fi

    log_info "$(get_localized_message "install.extracting_xray")"

    # Extract and install
    if ! unzip -q -o "$zip_file" -d "$temp_dir"; then
        log_error "$(get_localized_message "install.extract_failed")"
        return 12
    fi

    # Install binary
    if [[ -f "$temp_dir/xray" ]]; then
        install -m 755 "$temp_dir/xray" "$target_dir/xray"
        log_info "$(get_localized_message "install.binary_installed" "$target_dir/xray")"
    else
        log_error "$(get_localized_message "install.binary_not_found")"
        return 12
    fi

    # Verify installation
    if ! "$target_dir/xray" version >/dev/null 2>&1; then
        log_error "$(get_localized_message "install.binary_verification_failed")"
        return 12
    fi

    local installed_version
    installed_version=$("$target_dir/xray" version | head -1)
    log_info "$(get_localized_message "install.binary_verified" "$installed_version")"

    return 0
}

#######################################
# Create Xray configuration
# Arguments:
#   config_dir - configuration directory
#   dry_run - true/false
# Returns:
#   0 on success, 10 on failure
#######################################
create_xray_configuration() {
    local config_dir="$1"
    local dry_run="${2:-false}"

    log_info "$(get_localized_message "install.creating_config")"

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create configuration in: $config_dir"
        log_info "[DRY RUN] Would run: $PROJECT_ROOT/scripts/generate-config.sh"
        return 0
    fi

    # Create config directory
    mkdir -p "$config_dir"

    # Generate configuration using our script
    local config_file="$config_dir/config.json"

    if ! "$PROJECT_ROOT/scripts/generate-config.sh" "$config_file"; then
        log_error "$(get_localized_message "install.config_generation_failed")"
        return 10
    fi

    # Set proper permissions
    chmod 644 "$config_file"

    log_info "$(get_localized_message "install.config_created" "$config_file")"

    return 0
}

#######################################
# Setup systemd service
# Arguments:
#   service_name - name of the service
#   dry_run - true/false
# Returns:
#   0 on success, 13 on failure
#######################################
setup_systemd_service() {
    local service_name="$1"
    local dry_run="${2:-false}"

    log_info "$(get_localized_message "install.setting_up_service" "$service_name")"

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create systemd service: $service_name"
        log_info "[DRY RUN] Would enable and start service"
        return 0
    fi

    # Create service file from template
    local service_file="/etc/systemd/system/${service_name}.service"
    local template_file="$PROJECT_ROOT/systemd/xray-wsl.service.template"

    if [[ ! -f "$template_file" ]]; then
        log_error "$(get_localized_message "install.service_template_missing" "$template_file")"
        return 13
    fi

    # Substitute variables in template
    sed \
        -e "s|{{XRAY_BINARY}}|$XRAY_INSTALL_DIR/xray|g" \
        -e "s|{{XRAY_CONFIG}}|$XRAY_CONFIG_DIR/config.json|g" \
        -e "s|{{XRAY_LOG_DIR}}|$XRAY_LOG_DIR|g" \
        "$template_file" > "$service_file"

    # Create log directory
    mkdir -p "$XRAY_LOG_DIR"

    # Set proper permissions
    chmod 644 "$service_file"
    chmod 755 "$XRAY_LOG_DIR"

    # Reload systemd and enable service
    systemctl daemon-reload

    if ! systemctl enable "$service_name"; then
        log_error "$(get_localized_message "install.service_enable_failed")"
        return 13
    fi

    log_info "$(get_localized_message "install.service_created" "$service_file")"

    return 0
}

#######################################
# Start Xray service
# Arguments:
#   service_name - name of the service
# Returns:
#   0 on success, 13 on failure
#######################################
start_xray_service() {
    local service_name="$1"

    log_info "$(get_localized_message "service.starting")"

    if ! systemctl start "$service_name"; then
        log_error "$(get_localized_message "install.service_start_failed")"
        return 13
    fi

    # Wait a moment for service to initialize
    sleep 2

    # Check service status
    if systemctl is-active --quiet "$service_name"; then
        log_info "$(get_localized_message "install.service_started_successfully")"

        # Show service status
        systemctl status "$service_name" --no-pager --lines=5
    else
        log_error "$(get_localized_message "install.service_failed_to_start")"
        log_error "Check logs: journalctl -u $service_name --no-pager --lines=10"
        return 13
    fi

    return 0
}

#######################################
# Main function
# Arguments:
#   All command line arguments
# Returns:
#   Exit code based on results
#######################################
main() {
    local config_only=false
    local service_only=false
    local skip_service=false
    local force_install=false
    local dry_run=false
    local xray_version="latest"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --config-only)
                config_only=true
                shift
                ;;
            --service-only)
                service_only=true
                shift
                ;;
            --skip-service)
                skip_service=true
                shift
                ;;
            --force)
                force_install=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --version)
                if [[ -n "${2:-}" ]]; then
                    xray_version="$2"
                    shift 2
                else
                    log_error "$(get_localized_message "install.missing_version_value")"
                    exit 1
                fi
                ;;
            *)
                log_error "$(get_localized_message "unknown_option" "$1")"
                show_help
                exit 1
                ;;
        esac
    done

    log_info "$(get_localized_message "install.starting" "$SCRIPT_VERSION")"

    # Check system requirements
    check_system_requirements || exit $?

    # Load and validate environment (unless service-only)
    if [[ "$service_only" == false ]]; then
        load_env
        if ! validate_env_for_protocol "$XRAY_PROTOCOL"; then
            log_error "$(get_localized_message "install.config_validation_failed")"
            exit 10
        fi
    fi

    # Check root privileges for binary installation and systemd
    if [[ "$config_only" == false && $EUID -ne 0 ]]; then
        log_error "$(get_localized_message "install.root_required")"
        log_error "Run: sudo $0 $*"
        exit 1
    fi

    # Install Xray binary
    if [[ "$config_only" == false && "$service_only" == false ]]; then
        # Check if Xray is already installed
        if [[ -f "$XRAY_INSTALL_DIR/xray" && "$force_install" == false ]]; then
            local existing_version
            existing_version=$("$XRAY_INSTALL_DIR/xray" version 2>/dev/null | head -1 || echo "unknown")
            log_info "$(get_localized_message "install.already_installed" "$existing_version")"
            log_info "Use --force to reinstall"
        else
            # Get release information
            local release_json
            if ! release_json=$(get_xray_release_info "$xray_version"); then
                exit 12
            fi

            # Install binary
            if ! install_xray_binary "$release_json" "$XRAY_INSTALL_DIR" "$dry_run"; then
                exit 12
            fi
        fi
    fi

    # Create configuration
    if [[ "$service_only" == false ]]; then
        if ! create_xray_configuration "$XRAY_CONFIG_DIR" "$dry_run"; then
            exit 10
        fi
    fi

    # Setup systemd service
    if [[ "$skip_service" == false && "$config_only" == false ]]; then
        if ! setup_systemd_service "$XRAY_SERVICE_NAME" "$dry_run"; then
            exit 13
        fi

        # Start service (unless dry run)
        if [[ "$dry_run" == false ]]; then
            if ! start_xray_service "$XRAY_SERVICE_NAME"; then
                exit 13
            fi
        fi
    fi

    # Final success message
    log_info "$(get_localized_message "install.success")"

    if [[ "$dry_run" == false ]]; then
        log_info ""
        log_info "Next steps:"
        log_info "1. Check service status: systemctl status $XRAY_SERVICE_NAME"
        log_info "2. Test connection: ./scripts/check-ip.sh"
        log_info "3. Configure your applications to use:"
        log_info "   - SOCKS5: 127.0.0.1:$XRAY_LOCAL_SOCKS_PORT"
        if [[ -n "${XRAY_LOCAL_HTTP_PORT:-}" ]]; then
            log_info "   - HTTP: 127.0.0.1:$XRAY_LOCAL_HTTP_PORT"
        fi
    fi

    exit 0
}

# Run main function with all arguments
main "$@"