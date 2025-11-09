#!/bin/bash
set -euo pipefail

#######################################
# Parse Xray URL/QR Code Script
# Converts proxy URLs to .env configuration
#######################################

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/url_parser.sh"

#######################################
# Print usage information
#######################################
print_usage() {
    cat << EOF
Parse Xray URL/QR Code Script

USAGE:
    $0 [OPTIONS] <url|qr-file>

OPTIONS:
    -o, --output FILE    Output .env file (default: .env)
    -q, --qr             Parse QR code from image file
    -s, --stdin          Read QR code from stdin
    -h, --help           Show this help message

EXAMPLES:
    # Parse VLESS URL
    $0 "vless://uuid@server.com:443?type=tcp&security=reality..."

    # Parse from QR code file
    $0 --qr qrcode.png

    # Parse from QR code via stdin
    cat qrcode.png | $0 --stdin

    # Specify output file
    $0 -o server1.env "vless://..."

SUPPORTED FORMATS:
    - vless://uuid@host:port?params#name
    - vmess://base64-encoded-json
    - trojan://password@host:port?params#name

QR CODE REQUIREMENTS:
    - Install zbar-tools: sudo apt install zbar-tools
    - Supported formats: PNG, JPEG, GIF, TIFF

EOF
}

#######################################
# Main execution
#######################################
main() {
    local output_file=".env"
    local qr_mode=false
    local stdin_mode=false
    local input_data=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -q|--qr)
                qr_mode=true
                shift
                ;;
            -s|--stdin)
                stdin_mode=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                input_data="$1"
                shift
                ;;
        esac
    done

    # Validate input
    if [[ "$stdin_mode" == true ]]; then
        log_info "Reading QR code from stdin..."
        if ! generate_env_from_qr "-" "$output_file"; then
            log_error "Failed to parse QR code from stdin"
            exit 1
        fi
    elif [[ "$qr_mode" == true ]]; then
        if [[ -z "$input_data" ]]; then
            log_error "QR code file is required when using --qr option"
            print_usage
            exit 1
        fi

        log_info "Parsing QR code from file: $input_data"
        if ! generate_env_from_qr "$input_data" "$output_file"; then
            log_error "Failed to parse QR code from file: $input_data"
            exit 1
        fi
    else
        if [[ -z "$input_data" ]]; then
            log_error "URL is required"
            print_usage
            exit 1
        fi

        log_info "Parsing URL..."
        if ! generate_env_from_url "$input_data" "$output_file"; then
            log_error "Failed to parse URL: $input_data"
            exit 1
        fi
    fi

    log_info "Configuration generated successfully!"
    log_info "Next steps:"
    log_info "1. Review configuration: cat $output_file"
    log_info "2. Run installation: sudo ./scripts/install.sh"
    log_info "3. Check connection: ./scripts/check-ip.sh"
}

#######################################
# Helper function for QR code parsing
#######################################
generate_env_from_qr() {
    local qr_file="$1"
    local env_file="$2"

    local qr_url
    if ! qr_url=$(parse_qr_code "$qr_file"); then
        return 1
    fi

    generate_env_from_url "$qr_url" "$env_file"
}

# Execute main function with all arguments
main "$@"