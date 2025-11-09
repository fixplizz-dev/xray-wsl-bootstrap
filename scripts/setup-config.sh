#!/bin/bash
set -euo pipefail

#######################################
# Interactive Configuration Setup
# Guides user through .env file creation
#######################################

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/url_parser.sh"

# Colors are already defined in common.sh

#######################################
# Print colored header
#######################################
print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}               Xray WSL Bootstrap - Configuration Setup        ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#######################################
# Print step header
#######################################
print_step() {
    local step="$1"
    local title="$2"
    echo ""
    echo -e "${BLUE}[Step $step]${NC} ${BOLD}$title${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
}

#######################################
# Get user input with validation
#######################################
get_input() {
    local prompt="$1"
    local default="${2:-}"
    local validate_func="${3:-}"
    local value

    while true; do
        if [[ -n "$default" ]]; then
            echo -ne "${GREEN}$prompt${NC} [${YELLOW}$default${NC}]: "
        else
            echo -ne "${GREEN}$prompt${NC}: "
        fi

        read -r value

        # Use default if empty
        if [[ -z "$value" ]] && [[ -n "$default" ]]; then
            value="$default"
        fi

        # Skip validation if empty and no default
        if [[ -z "$value" ]] && [[ -z "$default" ]]; then
            echo -e "${RED}This field is required${NC}"
            continue
        fi

        # Run validation if provided
        if [[ -n "$validate_func" ]] && command -v "$validate_func" >/dev/null; then
            if ! "$validate_func" "$value"; then
                continue
            fi
        fi

        echo "$value"
        return 0
    done
}

#######################################
# Validation functions
#######################################
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        echo -e "${RED}Error: Port must be between 1 and 65535${NC}"
        return 1
    fi
    return 0
}

validate_protocol() {
    local protocol="$1"
    case "$protocol" in
        vless|vmess|trojan)
            return 0
            ;;
        *)
            echo -e "${RED}Error: Protocol must be vless, vmess, or trojan${NC}"
            return 1
            ;;
    esac
}

validate_uuid() {
    local uuid="$1"
    if [[ ! "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        echo -e "${RED}Error: Invalid UUID format (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)${NC}"
        return 1
    fi
    return 0
}

validate_security() {
    local security="$1"
    case "$security" in
        none|tls|xtls|reality)
            return 0
            ;;
        *)
            echo -e "${RED}Error: Security must be none, tls, xtls, or reality${NC}"
            return 1
            ;;
    esac
}

#######################################
# URL/QR import workflow
#######################################
import_from_url_qr() {
    print_step "1" "Import Configuration"
    echo -e "${CYAN}📥 Paste your proxy URL or file path:${NC}"
    echo -e "  ${BOLD}Supported:${NC} vless:// vmess:// trojan:// URLs"
    echo -e "  ${BOLD}Or:${NC} path to QR code image file"
    echo -e "  ${DIM}Press Enter to skip and configure manually${NC}"
    echo ""

    local input
    input=$(get_input "URL or file path" "")

    # Skip if empty
    if [[ -z "$input" ]]; then
        echo -e "${YELLOW}⏭  Skipping URL import, proceeding to manual setup${NC}"
        return 1
    fi

    # Clean input: remove newlines, carriage returns, and extra spaces
    input=$(echo "$input" | tr -d '\n\r' | xargs)

    # Check if it's a file (QR code)
    if [[ -f "$input" ]]; then
        echo -e "${BLUE}🔍 Processing QR code image...${NC}"
        if "$PROJECT_ROOT/scripts/parse-url.sh" --qr "$input" -o ".env.tmp"; then
            echo -e "${GREEN}✅ QR code imported successfully!${NC}"
            return 0
        else
            echo -e "${RED}❌ Failed to read QR code${NC}"
            return 1
        fi
    fi

    # Check if it's a URL
    if [[ "$input" =~ ^(vless|vmess|trojan):// ]]; then
        echo -e "${BLUE}🔗 Processing proxy URL...${NC}"
        echo -e "${DIM}Debug: URL detected with protocol ${BASH_REMATCH[1]}://${NC}"
        echo -e "${DIM}Debug: Calling generate_env_from_url...${NC}"

        if generate_env_from_url "$input" ".env.tmp" 2>&1; then
            echo -e "${GREEN}✅ URL imported successfully!${NC}"
            echo -e "${CYAN}📝 Configuration saved to .env${NC}"
            return 0
        else
            echo -e "${RED}❌ Failed to parse URL${NC}"
            echo -e "${DIM}Debug: Error occurred in generate_env_from_url${NC}"
            return 1
        fi
    fi

    # Invalid input
    echo -e "${RED}❌ Invalid input. Expected: vless://, vmess://, trojan:// URL or QR image file${NC}"
    return 1

}

#######################################
# Manual configuration workflow
#######################################
manual_configuration() {
    print_step "2" "Manual Configuration"

    local protocol host port auth security

    # Protocol selection
    echo -e "${CYAN}Select protocol:${NC}"
    echo -e "  ${YELLOW}1.${NC} VLESS (recommended)"
    echo -e "  ${YELLOW}2.${NC} VMess"
    echo -e "  ${YELLOW}3.${NC} Trojan"

    local proto_choice
    echo -ne "${GREEN}Choose protocol (1-3)${NC} [${YELLOW}1${NC}]: "
    read -r proto_choice
    # Use default if empty
    if [[ -z "$proto_choice" ]]; then
        proto_choice="1"
    fi

    case "$proto_choice" in
        1) protocol="vless" ;;
        2) protocol="vmess" ;;
        3) protocol="trojan" ;;
        *) protocol="vless" ;;
    esac

    echo ""

    # Server details
    echo -ne "${GREEN}Server hostname or IP address${NC}: "
    read -r host
    while [[ -z "$host" ]]; do
        echo -e "${RED}This field is required${NC}"
        echo -ne "${GREEN}Server hostname or IP address${NC}: "
        read -r host
    done

    echo -ne "${GREEN}Server port${NC} [${YELLOW}443${NC}]: "
    read -r port
    if [[ -z "$port" ]]; then
        port="443"
    fi

    # Authentication
    if [[ "$protocol" == "trojan" ]]; then
        echo -ne "${GREEN}Trojan password${NC}: "
        read -r auth
        while [[ -z "$auth" ]]; do
            echo -e "${RED}This field is required${NC}"
            echo -ne "${GREEN}Trojan password${NC}: "
            read -r auth
        done
    else
        echo ""
        echo -e "${YELLOW}Generate new UUID? (y/N)${NC}"
        read -r -n 1 gen_uuid
        echo ""

        if [[ "$gen_uuid" =~ ^[Yy]$ ]]; then
            if command -v uuidgen >/dev/null 2>&1; then
                auth=$(uuidgen | tr '[:upper:]' '[:lower:]')
                echo -e "${GREEN}Generated UUID: $auth${NC}"
            else
                auth="$(cat /proc/sys/kernel/random/uuid)"
                echo -e "${GREEN}Generated UUID: $auth${NC}"
            fi
        else
            echo -ne "${GREEN}UUID${NC}: "
            read -r auth
            while [[ -z "$auth" ]]; do
                echo -e "${RED}This field is required${NC}"
                echo -ne "${GREEN}UUID${NC}: "
                read -r auth
            done
        fi
    fi

    # Security settings
    echo ""
    echo -e "${CYAN}Select security type:${NC}"
    echo -e "  ${YELLOW}1.${NC} None (plain TCP)"
    echo -e "  ${YELLOW}2.${NC} TLS"
    echo -e "  ${YELLOW}3.${NC} XTLS"
    echo -e "  ${YELLOW}4.${NC} Reality (recommended)"

    local sec_choice
    sec_choice=$(get_input "Choose security (1-4)" "4")

    case "$sec_choice" in
        1) security="none" ;;
        2) security="tls" ;;
        3) security="xtls" ;;
        4) security="reality" ;;
        *) security="reality" ;;
    esac

    # Write configuration
    {
        echo "# Generated by interactive setup - $(date)"
        echo ""
        echo "# Server Configuration"
        echo "XRAY_PROTOCOL=$protocol"
        echo "XRAY_SERVER_HOST=$host"
        echo "XRAY_SERVER_PORT=$port"

        if [[ "$protocol" == "trojan" ]]; then
            echo "XRAY_PASSWORD=$auth"
        else
            echo "XRAY_UUID=$auth"
        fi

        echo ""
        echo "# Security Settings"
        echo "XRAY_SECURITY=$security"

        if [[ "$security" == "reality" ]]; then
            echo ""
            echo "# Reality Settings (configure these manually)"
            echo "#XRAY_REALITY_PUBLIC_KEY=your-public-key"
            echo "#XRAY_REALITY_SHORT_ID=your-short-id"
            echo "#XRAY_REALITY_FINGERPRINT=chrome"
            echo "#XRAY_REALITY_SERVER_NAME=www.google.com"
        elif [[ "$security" == "tls" ]] || [[ "$security" == "xtls" ]]; then
            echo ""
            echo "# TLS Settings"
            echo "XRAY_TLS_SNI=$host"
        fi

        echo ""
        echo "# Local Proxy Settings"
        echo "XRAY_LOCAL_SOCKS_PORT=1080"
        echo "XRAY_LOCAL_HTTP_PORT=8080"

        echo ""
        echo "# Other Settings"
        echo "XRAY_AUTOSTART=off"
        echo "XRAY_CLIENT_LANG=en"
        echo "XRAY_LOG_LEVEL=warn"

    } > ".env.tmp"

    return 0
}

#######################################
# Review and finalize configuration
#######################################
review_configuration() {
    print_step "3" "Review Configuration"

    if [[ ! -f ".env.tmp" ]]; then
        echo -e "${RED}✗ No configuration file found${NC}"
        return 1
    fi

    echo -e "${CYAN}Generated configuration:${NC}"
    echo ""

    # Display configuration with syntax highlighting
    while IFS= read -r line; do
        if [[ "$line" =~ ^#.* ]]; then
            echo -e "${BLUE}$line${NC}"
        elif [[ "$line" =~ ^[A-Z_]+=.* ]]; then
            local key="${line%=*}"
            local value="${line#*=}"
            echo -e "${GREEN}$key${NC}=${YELLOW}$value${NC}"
        else
            echo "$line"
        fi
    done < ".env.tmp"

    echo ""
    echo -e "${YELLOW}Is this configuration correct? (Y/n)${NC}"
    read -r -n 1 confirm
    echo ""

    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Configuration cancelled${NC}"
        rm -f ".env.tmp"
        return 1
    fi

    # Finalize configuration
    if [[ -f ".env" ]]; then
        cp ".env" ".env.backup.$(date +%s)"
        echo -e "${GREEN}✓ Created backup of existing .env file${NC}"
    fi

    mv ".env.tmp" ".env"
    chmod 600 ".env"

    echo -e "${GREEN}✓ Configuration saved to .env${NC}"
    return 0
}

#######################################
# Next steps guidance
#######################################
show_next_steps() {
    print_step "4" "Next Steps"

    echo -e "${GREEN}Configuration completed successfully!${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "  ${YELLOW}1.${NC} Install Xray: ${BOLD}sudo ./scripts/install.sh${NC}"
    echo -e "  ${YELLOW}2.${NC} Check connection: ${BOLD}./scripts/check-ip.sh${NC}"
    echo -e "  ${YELLOW}3.${NC} Manage service: ${BOLD}./scripts/manage.sh status${NC}"
    echo ""

    echo -e "${CYAN}Useful commands:${NC}"
    echo -e "  ${YELLOW}•${NC} Edit configuration: ${BOLD}nano .env${NC}"
    echo -e "  ${YELLOW}•${NC} View logs: ${BOLD}./scripts/manage.sh logs${NC}"
    echo -e "  ${YELLOW}•${NC} Enable autostart: ${BOLD}sudo ./scripts/manage.sh autostart-enable${NC}"
    echo ""

    echo -e "${YELLOW}Ready to install? (Y/n)${NC}"
    read -r -n 1 install_now
    echo ""

    if [[ ! "$install_now" =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}Starting installation...${NC}"
        echo ""
        if [[ -f "$PROJECT_ROOT/scripts/install.sh" ]]; then
            exec sudo "$PROJECT_ROOT/scripts/install.sh"
        else
            echo -e "${RED}✗ Install script not found${NC}"
            return 1
        fi
    fi
}

#######################################
# Print usage information
#######################################
print_usage() {
    cat << EOF
Interactive Configuration Setup

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --url URL        Import from URL directly
    --qr FILE        Import from QR code file
    --manual         Skip import, configure manually
    -h, --help       Show this help message

EXAMPLES:
    # Interactive setup
    $0

    # Import from URL
    $0 --url "vless://uuid@server.com:443?..."

    # Import from QR code
    $0 --qr qrcode.png

EOF
}

#######################################
# Main execution
#######################################
main() {
    local import_url=""
    local import_qr=""
    local manual_mode=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --url)
                import_url="$2"
                shift 2
                ;;
            --qr)
                import_qr="$2"
                shift 2
                ;;
            --manual)
                manual_mode=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    print_header

    # Direct import modes
    if [[ -n "$import_url" ]]; then
        print_step "1" "Importing from URL"
        if generate_env_from_url "$import_url" ".env.tmp"; then
            review_configuration && show_next_steps
        else
            exit 1
        fi
        return
    fi

    if [[ -n "$import_qr" ]]; then
        print_step "1" "Importing from QR Code"
        if "$PROJECT_ROOT/scripts/parse-url.sh" --qr "$import_qr" -o ".env.tmp"; then
            review_configuration && show_next_steps
        else
            exit 1
        fi
        return
    fi

    # Interactive workflow
    if [[ "$manual_mode" == true ]] || ! import_from_url_qr; then
        manual_configuration
    fi

    if review_configuration; then
        show_next_steps
    else
        echo -e "${RED}Setup cancelled${NC}"
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"