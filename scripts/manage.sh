#!/bin/bash
set -euo pipefail

#######################################
# Xray WSL Management Script
# Provides unified management interface for Xray VPN client
#######################################

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source required libraries
source "$PROJECT_ROOT/lib/common.sh"

readonly SERVICE_NAME="xray-wsl"
readonly CONFIG_DIR="/etc/xray"

#######################################
# Check system requirements for management operations
#######################################
check_system_requirements() {
    # Check bash version
    if ! check_bash_version; then
        log_error "Bash 5.x or higher is required"
        exit 1
    fi

    # Check systemd availability
    if ! command -v systemctl >/dev/null 2>&1; then
        log_error "systemctl is required for service management"
        log_error "Please ensure systemd is available in your WSL environment"
        exit 1
    fi

    # Check WSL environment
    if [[ ! -f /proc/version ]] || ! grep -qi "microsoft\|wsl" /proc/version; then
        log_warning "This script is designed for WSL environment"
    fi
}

#######################################
# Print usage information
#######################################
print_usage() {
    cat << EOF
Xray WSL Management Script

USAGE:
    $0 <command>

COMMANDS:
    start       Start Xray service
    stop        Stop Xray service
    restart     Restart Xray service
    status      Show service status
    logs        Show service logs (last 50 lines)
    enable      Enable autostart on boot
    disable     Disable autostart on boot
    reload      Reload service configuration
    check-ip    Check current IP address
    version     Show Xray version
    config      Show current configuration path
    validate    Validate configuration file
    help        Show this help message

EXAMPLES:
    $0 start                    # Start Xray service
    $0 status                   # Check if service is running
    $0 logs                     # View recent logs
    $0 check-ip                 # Verify VPN connection
    $0 enable                   # Enable autostart

EOF
}

#######################################
# Check if script is run with appropriate privileges
#######################################
check_privileges() {
    local command="$1"

    case "$command" in
        "start"|"stop"|"restart"|"enable"|"disable"|"reload")
            if [ "$EUID" -ne 0 ]; then
                log_error "Command '$command' requires root privileges"
                log_info "Run with: sudo $0 $command"
                exit 1
            fi
            ;;
    esac
}

#######################################
# Start Xray service
#######################################
start_service() {
    log_info "Starting Xray service..."

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_warn "Service is already running"
        return 0
    fi

    systemctl start "$SERVICE_NAME"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Service started successfully"
    else
        log_error "Failed to start service"
        return 1
    fi
}

#######################################
# Stop Xray service
#######################################
stop_service() {
    log_info "Stopping Xray service..."

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log_warn "Service is not running"
        return 0
    fi

    systemctl stop "$SERVICE_NAME"

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Service stopped successfully"
    else
        log_error "Failed to stop service"
        return 1
    fi
}

#######################################
# Restart Xray service
#######################################
restart_service() {
    log_info "Restarting Xray service..."
    systemctl restart "$SERVICE_NAME"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Service restarted successfully"
    else
        log_error "Failed to restart service"
        return 1
    fi
}

#######################################
# Show service status
#######################################
show_status() {
    log_info "Checking Xray service status..."
    echo ""

    systemctl status "$SERVICE_NAME" --no-pager -l

    echo ""
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Service is running"
    else
        log_warn "Service is not running"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        log_info "Autostart: enabled"
    else
        log_info "Autostart: disabled"
    fi
}

#######################################
# Show service logs
#######################################
show_logs() {
    log_info "Showing Xray service logs (last 50 lines)..."
    echo ""

    journalctl -u "$SERVICE_NAME" -n 50 --no-pager -l
}

#######################################
# Enable autostart
#######################################
enable_service() {
    log_info "Enabling Xray service autostart..."

    systemctl enable "$SERVICE_NAME"
    log_success "Autostart enabled"
}

#######################################
# Disable autostart
#######################################
disable_service() {
    log_info "Disabling Xray service autostart..."

    systemctl disable "$SERVICE_NAME"
    log_success "Autostart disabled"
}

#######################################
# Reload service configuration
#######################################
reload_service() {
    log_info "Reloading Xray service configuration..."

    systemctl daemon-reload
    systemctl reload-or-restart "$SERVICE_NAME"

    log_success "Configuration reloaded"
}

#######################################
# Check IP address
#######################################
check_ip() {
    "$PROJECT_ROOT/scripts/check-ip.sh"
}

#######################################
# Show Xray version
#######################################
show_version() {
    log_info "Checking Xray version..."

    if command -v xray >/dev/null 2>&1; then
        xray version
    else
        log_error "Xray binary not found"
        return 1
    fi
}

#######################################
# Show configuration path
#######################################
show_config() {
    log_info "Current configuration:"
    echo "  Config file: $CONFIG_DIR/config.json"
    echo "  Service file: /etc/systemd/system/$SERVICE_NAME.service"
    echo "  Environment: $PROJECT_ROOT/.env"

    if [ -f "$CONFIG_DIR/config.json" ]; then
        log_success "Configuration file exists"
    else
        log_error "Configuration file not found"
    fi
}

#######################################
# Validate configuration
#######################################
validate_config() {
    log_info "Validating Xray configuration..."

    if [ ! -f "$CONFIG_DIR/config.json" ]; then
        log_error "Configuration file not found: $CONFIG_DIR/config.json"
        return 1
    fi

    if command -v xray >/dev/null 2>&1; then
        if xray test -config "$CONFIG_DIR/config.json"; then
            log_success "Configuration is valid"
        else
            log_error "Configuration validation failed"
            return 1
        fi
    else
        log_warn "Xray binary not found, skipping validation"
    fi
}

#######################################
# Main execution
#######################################
main() {
    local command="${1:-help}"

    # Check system requirements
    check_system_requirements

    check_privileges "$command"

    case "$command" in
        "start")
            start_service
            ;;
        "stop")
            stop_service
            ;;
        "restart")
            restart_service
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs
            ;;
        "enable")
            enable_service
            ;;
        "disable")
            disable_service
            ;;
        "reload")
            reload_service
            ;;
        "check-ip")
            check_ip
            ;;
        "version")
            show_version
            ;;
        "config")
            show_config
            ;;
        "validate")
            validate_config
            ;;
        "help"|"--help"|"-h")
            print_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"