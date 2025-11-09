#!/bin/bash
set -euo pipefail

#######################################
# Xray WSL Bootstrap - One-Command Installer
# Downloads full repository and runs installation
#######################################

readonly REPO_URL="https://github.com/fixplizz-dev/xray-wsl-bootstrap.git"
readonly INSTALL_DIR="$HOME/xray-wsl-bootstrap"
readonly SCRIPT_VERSION="${PROJECT_VERSION:-0.1.1}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#######################################
# Print colored message
# Arguments:
#   $1 - color code
#   $2 - message
#######################################
print_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}[$(date '+%H:%M:%S')] $message${NC}"
}

#######################################
# Print info message
#######################################
info() {
    print_message "$BLUE" "INFO: $1"
}

#######################################
# Print warning message
#######################################
warn() {
    print_message "$YELLOW" "WARN: $1"
}

#######################################
# Print error message
#######################################
error() {
    print_message "$RED" "ERROR: $1"
}

#######################################
# Print success message
#######################################
success() {
    print_message "$GREEN" "SUCCESS: $1"
}

#######################################
# Check system requirements
#######################################
check_requirements() {
    info "Checking system requirements..."

    # Check if we're in WSL
    if ! grep -qi microsoft /proc/version 2>/dev/null; then
        warn "This script is designed for WSL2. Continuing anyway..."
    fi

    # Check required commands
    local missing_commands=()

    for cmd in git curl bash; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -gt 0 ]; then
        error "Missing required commands: ${missing_commands[*]}"
        error "Please install: sudo apt update && sudo apt install -y git curl bash"
        exit 1
    fi

    # Check if systemd is available
    if ! command -v systemctl >/dev/null 2>&1; then
        error "systemctl not found. This script requires systemd support in WSL."
        error "Enable systemd in WSL: https://learn.microsoft.com/windows/wsl/systemd"
        exit 1
    fi

    success "System requirements check passed"
}

#######################################
# Download repository
#######################################
download_repository() {
    info "Downloading Xray WSL Bootstrap repository..."

    # Remove existing directory if it exists
    if [ -d "$INSTALL_DIR" ]; then
        warn "Existing installation found at $INSTALL_DIR"
        read -p "Remove and reinstall? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
            info "Removed existing installation"
        else
            info "Using existing installation"
            return 0
        fi
    fi

    # Clone repository
    if ! git clone "$REPO_URL" "$INSTALL_DIR"; then
        error "Failed to clone repository from $REPO_URL"
        exit 1
    fi

    success "Repository downloaded to $INSTALL_DIR"
}

#######################################
# Setup configuration
#######################################
setup_configuration() {
    info "Setting up configuration..."

    cd "$INSTALL_DIR"

    # Copy example configuration
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
            chmod 600 .env
            info "Created .env file from template"
            warn "IMPORTANT: Edit .env file with your server parameters before installation"
            warn "Run: nano $INSTALL_DIR/.env"
        else
            error ".env.example file not found in repository"
            exit 1
        fi
    else
        info ".env file already exists, skipping creation"
    fi
}

#######################################
# Run installation
#######################################
run_installation() {
    info "Starting Xray installation..."

    cd "$INSTALL_DIR"

    # Check if .env is configured
    if grep -q "your.server.com" .env 2>/dev/null || grep -q "CHANGE_ME" .env 2>/dev/null; then
        warn "Default values detected in .env file"
        warn "Please configure .env with your actual server parameters"
        warn "Edit: nano $INSTALL_DIR/.env"
        warn "Then run: cd $INSTALL_DIR && sudo ./scripts/install.sh"
        return 0
    fi

    # Make install script executable
    chmod +x scripts/install.sh

    # Run installation
    info "Running installation script..."
    sudo ./scripts/install.sh

    if [ $? -eq 0 ]; then
        success "Installation completed successfully!"
        info "Next steps:"
        info "  1. Check connection: cd $INSTALL_DIR && ./scripts/check-ip.sh"
        info "  2. Manage service: cd $INSTALL_DIR && ./scripts/manage.sh status"
        info "  3. Enable autostart: cd $INSTALL_DIR && sudo systemctl enable xray-wsl"
    else
        error "Installation failed. Please check the logs above."
        exit 1
    fi
}

#######################################
# Print usage information
#######################################
print_usage() {
    cat << EOF
Xray WSL Bootstrap - One-Command Installer v$SCRIPT_VERSION

USAGE:
    curl -fsSL https://raw.githubusercontent.com/fixplizz-dev/xray-wsl-bootstrap/main/bootstrap.sh | bash

DESCRIPTION:
    Downloads and installs Xray VPN client for WSL2 with systemd support.

    This script will:
    1. Check system requirements (WSL2, systemd, git, curl)
    2. Download the full repository to ~/xray-wsl-bootstrap
    3. Create .env configuration file from template
    4. Guide you through the installation process

REQUIREMENTS:
    - WSL2 with Ubuntu 22.04+
    - Systemd enabled in WSL
    - Internet connection
    - git, curl, bash installed

CONFIGURATION:
    After running this script, edit the configuration file:
    nano ~/xray-wsl-bootstrap/.env

    Then complete installation:
    cd ~/xray-wsl-bootstrap && sudo ./scripts/install.sh

MORE INFO:
    Repository: $REPO_URL
    Documentation: ${REPO_URL}#readme

EOF
}

#######################################
# Main execution
#######################################
main() {
    # Handle help flag
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        print_usage
        exit 0
    fi

    info "Starting Xray WSL Bootstrap v$SCRIPT_VERSION"
    info "Repository: $REPO_URL"

    check_requirements
    download_repository
    setup_configuration

    # Fix permissions
    info "Setting up file permissions..."
    cd "$INSTALL_DIR"
    chmod +x xray-wsl 2>/dev/null || true
    chmod +x scripts/*.sh 2>/dev/null || true
    chmod +x lib/*.sh 2>/dev/null || true

    info "Bootstrap completed successfully!"
    info ""
    info "LAUNCHING INTERACTIVE SETUP:"

    # Check if interactive CLI exists and ensure it's executable
    if [[ -f "$INSTALL_DIR/xray-wsl" ]]; then
        # Ensure executable permission
        chmod +x "$INSTALL_DIR/xray-wsl"

        success "Starting Xray WSL Bootstrap interactive interface..."
        info ""
        info "The interactive menu will help you:"
        info "• Configure VPN connection (URL/QR or manual)"
        info "• Install Xray automatically"
        info "• Start and manage the VPN service"
        info "• Check connection and system status"
        info ""

        # Add a small delay so user can read the messages
        sleep 2

        # Setup complete - provide manual launch instructions
        echo ""
        success "✅ Installation complete!"
        echo ""
        success "� To start the interactive configuration menu:"
        info "   cd $INSTALL_DIR"
        info "   ./xray-wsl"
        echo ""
        success "📁 Project installed in: $INSTALL_DIR"
        info "📖 Quick start: Configure → Install → Check IP"
    else
        # Fallback to old method
        info "NEXT STEPS:"
        info "1. Configure your server settings:"
        info "   nano $INSTALL_DIR/.env"
        info ""
        info "2. Run the installation:"
        info "   cd $INSTALL_DIR && sudo ./scripts/install.sh"
        info ""
        info "3. Check connection:"
        info "   cd $INSTALL_DIR && ./scripts/check-ip.sh"

        success "Ready for configuration and installation!"
    fi
}

# Execute main function with all arguments
main "$@"