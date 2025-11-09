#!/bin/bash
set -euo pipefail

#######################################
# URL Parser Library for Xray Protocols
# Supports VLESS, VMess, Trojan URLs
#######################################

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/lib/common.sh"

#######################################
# Parse VLESS URL
# Format: vless://uuid@host:port?key1=val1&key2=val2#name
#######################################
parse_vless_url() {
    local url="$1"

    # Remove protocol prefix
    local clean_url="${url#vless://}"

    # Extract name (after #)
    local name=""
    if [[ "$clean_url" == *"#"* ]]; then
        name="${clean_url##*#}"
        clean_url="${clean_url%#*}"
    fi

    # Extract query parameters (after ?)
    local params=""
    if [[ "$clean_url" == *"?"* ]]; then
        params="${clean_url##*?}"
        clean_url="${clean_url%?*}"
    fi

    # Extract UUID and server info
    local uuid="${clean_url%@*}"
    local server_info="${clean_url##*@}"

    # Extract host and port
    local host="${server_info%:*}"
    local port="${server_info##*:}"

    # Parse query parameters
    local type="" encryption="" security="" pbk="" fp="" sni="" sid="" spx="" path="" serviceName=""

    if [[ -n "$params" ]]; then
        # Split parameters by &
        IFS='&' read -ra PARAM_ARRAY <<< "$params"
        for param in "${PARAM_ARRAY[@]}"; do
            local key="${param%=*}"
            local value="${param#*=}"
            # URL decode value
            value=$(printf '%b' "${value//%/\\x}")

            case "$key" in
                "type") type="$value" ;;
                "encryption") encryption="$value" ;;
                "security") security="$value" ;;
                "pbk") pbk="$value" ;;
                "fp") fp="$value" ;;
                "sni") sni="$value" ;;
                "sid") sid="$value" ;;
                "spx") spx="$value" ;;
                "path") path="$value" ;;
                "serviceName") serviceName="$value" ;;
            esac
        done
    fi

    # Output parsed values
    echo "XRAY_PROTOCOL=vless"
    echo "XRAY_UUID=$uuid"
    echo "XRAY_SERVER_HOST=$host"
    echo "XRAY_SERVER_PORT=$port"

    # Network type
    if [[ -n "$type" ]]; then
        echo "XRAY_NETWORK=$type"
    fi

    # Security settings
    if [[ -n "$security" ]]; then
        echo "XRAY_SECURITY=$security"

        # Reality-specific parameters
        if [[ "$security" == "reality" ]]; then
            [[ -n "$pbk" ]] && echo "XRAY_REALITY_PUBLIC_KEY=$pbk"
            [[ -n "$sid" ]] && echo "XRAY_REALITY_SHORT_ID=$sid"
            [[ -n "$fp" ]] && echo "XRAY_REALITY_FINGERPRINT=$fp"
            [[ -n "$sni" ]] && echo "XRAY_REALITY_SERVER_NAME=$sni"
            [[ -n "$spx" ]] && echo "XRAY_REALITY_SPIDER_X=$spx"
        elif [[ "$security" == "tls" ]] || [[ "$security" == "xtls" ]]; then
            [[ -n "$sni" ]] && echo "XRAY_TLS_SNI=$sni"
        fi
    fi

    # Transport settings
    if [[ "$type" == "ws" ]]; then
        [[ -n "$path" ]] && echo "XRAY_WS_PATH=$path"
    elif [[ "$type" == "grpc" ]]; then
        [[ -n "$serviceName" ]] && echo "XRAY_GRPC_SERVICE_NAME=$serviceName"
    fi

    # Connection name
    [[ -n "$name" ]] && echo "XRAY_CONNECTION_NAME=$name"
}

#######################################
# Parse VMess URL (base64 encoded JSON)
# Format: vmess://base64-encoded-json
#######################################
parse_vmess_url() {
    local url="$1"

    # Remove protocol prefix
    local encoded="${url#vmess://}"

    # Decode base64
    local json_data
    if ! json_data=$(echo "$encoded" | base64 -d 2>/dev/null); then
        log_error "Failed to decode VMess URL base64"
        return 1
    fi

    # Parse JSON using jq if available, otherwise manual parsing
    if command -v jq >/dev/null 2>&1; then
        echo "XRAY_PROTOCOL=vmess"
        echo "XRAY_UUID=$(echo "$json_data" | jq -r '.id // empty')"
        echo "XRAY_SERVER_HOST=$(echo "$json_data" | jq -r '.add // empty')"
        echo "XRAY_SERVER_PORT=$(echo "$json_data" | jq -r '.port // empty')"

        local net=$(echo "$json_data" | jq -r '.net // empty')
        [[ -n "$net" ]] && echo "XRAY_NETWORK=$net"

        local tls=$(echo "$json_data" | jq -r '.tls // empty')
        [[ -n "$tls" ]] && echo "XRAY_SECURITY=$tls"

        local sni=$(echo "$json_data" | jq -r '.sni // empty')
        [[ -n "$sni" ]] && echo "XRAY_TLS_SNI=$sni"

        local path=$(echo "$json_data" | jq -r '.path // empty')
        [[ -n "$path" ]] && echo "XRAY_WS_PATH=$path"

        local ps=$(echo "$json_data" | jq -r '.ps // empty')
        [[ -n "$ps" ]] && echo "XRAY_CONNECTION_NAME=$ps"
    else
        log_error "jq is required for VMess URL parsing"
        return 1
    fi
}

#######################################
# Parse Trojan URL
# Format: trojan://password@host:port?key1=val1&key2=val2#name
#######################################
parse_trojan_url() {
    local url="$1"

    # Remove protocol prefix
    local clean_url="${url#trojan://}"

    # Extract name (after #)
    local name=""
    if [[ "$clean_url" == *"#"* ]]; then
        name="${clean_url##*#}"
        clean_url="${clean_url%#*}"
    fi

    # Extract query parameters (after ?)
    local params=""
    if [[ "$clean_url" == *"?"* ]]; then
        params="${clean_url##*?}"
        clean_url="${clean_url%?*}"
    fi

    # Extract password and server info
    local password="${clean_url%@*}"
    local server_info="${clean_url##*@}"

    # Extract host and port
    local host="${server_info%:*}"
    local port="${server_info##*:}"

    # Parse query parameters
    local type="" security="" sni="" path="" serviceName=""

    if [[ -n "$params" ]]; then
        IFS='&' read -ra PARAM_ARRAY <<< "$params"
        for param in "${PARAM_ARRAY[@]}"; do
            local key="${param%=*}"
            local value="${param#*=}"
            # URL decode value
            value=$(printf '%b' "${value//%/\\x}")

            case "$key" in
                "type") type="$value" ;;
                "security") security="$value" ;;
                "sni") sni="$value" ;;
                "path") path="$value" ;;
                "serviceName") serviceName="$value" ;;
            esac
        done
    fi

    # Output parsed values
    echo "XRAY_PROTOCOL=trojan"
    echo "XRAY_PASSWORD=$password"
    echo "XRAY_SERVER_HOST=$host"
    echo "XRAY_SERVER_PORT=$port"

    # Network and security settings
    [[ -n "$type" ]] && echo "XRAY_NETWORK=$type"
    [[ -n "$security" ]] && echo "XRAY_SECURITY=$security"
    [[ -n "$sni" ]] && echo "XRAY_TLS_SNI=$sni"

    # Transport settings
    if [[ "$type" == "ws" ]]; then
        [[ -n "$path" ]] && echo "XRAY_WS_PATH=$path"
    elif [[ "$type" == "grpc" ]]; then
        [[ -n "$serviceName" ]] && echo "XRAY_GRPC_SERVICE_NAME=$serviceName"
    fi

    # Connection name
    [[ -n "$name" ]] && echo "XRAY_CONNECTION_NAME=$name"
}

#######################################
# Parse Shadowsocks URL (basic support)
# Format: ss://method:password@host:port#name
#######################################
parse_shadowsocks_url() {
    local url="$1"

    log_warn "Shadowsocks URLs are not directly supported by Xray"
    log_info "Please use VLESS, VMess, or Trojan instead"
    return 1
}

#######################################
# Auto-detect and parse URL
#######################################
parse_proxy_url() {
    local url="$1"

    if [[ -z "$url" ]]; then
        log_error "URL is required"
        return 1
    fi

    # Detect protocol
    case "$url" in
        vless://*)
            log_info "Detected VLESS URL"
            parse_vless_url "$url"
            ;;
        vmess://*)
            log_info "Detected VMess URL"
            parse_vmess_url "$url"
            ;;
        trojan://*)
            log_info "Detected Trojan URL"
            parse_trojan_url "$url"
            ;;
        ss://*)
            log_info "Detected Shadowsocks URL"
            parse_shadowsocks_url "$url"
            ;;
        *)
            log_error "Unsupported URL format: $url"
            log_info "Supported formats: vless://, vmess://, trojan://"
            return 1
            ;;
    esac
}

#######################################
# Parse QR code from file or stdin
#######################################
parse_qr_code() {
    local qr_file="$1"

    # Check if qrencode/zbarimg is available
    if ! command -v zbarimg >/dev/null 2>&1; then
        log_error "zbarimg is required for QR code parsing"
        log_info "Install with: sudo apt install zbar-tools"
        return 1
    fi

    local qr_data
    if [[ "$qr_file" == "-" ]]; then
        # Read from stdin
        if ! qr_data=$(zbarimg --raw -q /dev/stdin 2>/dev/null); then
            log_error "Failed to decode QR code from stdin"
            return 1
        fi
    else
        # Read from file
        if [[ ! -f "$qr_file" ]]; then
            log_error "QR code file not found: $qr_file"
            return 1
        fi

        if ! qr_data=$(zbarimg --raw -q "$qr_file" 2>/dev/null); then
            log_error "Failed to decode QR code from file: $qr_file"
            return 1
        fi
    fi

    if [[ -z "$qr_data" ]]; then
        log_error "No QR code data found"
        return 1
    fi

    log_info "QR code decoded successfully"
    parse_proxy_url "$qr_data"
}

#######################################
# Generate .env file from parsed data
#######################################
generate_env_from_url() {
    local url="$1"
    local env_file="${2:-.env}"

    local parsed_data
    if ! parsed_data=$(parse_proxy_url "$url" 2>&1); then
        return 1
    fi
    
    # Filter out log lines from parsed data (timestamp format: YYYY-MM-DD HH:MM:SS)
    parsed_data=$(echo "$parsed_data" | grep -v "^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}" | grep -v "^\[INFO\]" | grep -v "^\[WARN\]" | grep -v "^\[ERROR\]")

    # Create backup if env file exists
    if [[ -f "$env_file" ]]; then
        cp "$env_file" "$env_file.backup.$(date +%s)"
        log_info "Created backup: $env_file.backup.$(date +%s)"
    fi

    # Write parsed data to env file
    {
        echo "# Generated from URL: $(date)"
        echo "# Connection: $(echo "$parsed_data" | grep XRAY_CONNECTION_NAME | cut -d= -f2- || echo "Imported")"
        echo ""
        echo "$parsed_data"
        echo ""
        echo "# Local proxy settings"
        echo "XRAY_LOCAL_SOCKS_PORT=1080"
        echo "XRAY_LOCAL_HTTP_PORT=8080"
        echo ""
        echo "# Other settings"
        echo "XRAY_AUTOSTART=off"
        echo "XRAY_CLIENT_LANG=en"
        echo "XRAY_LOG_LEVEL=warn"
    } > "$env_file"

    chmod 600 "$env_file"
    log_info "Configuration written to $env_file"

    return 0
}