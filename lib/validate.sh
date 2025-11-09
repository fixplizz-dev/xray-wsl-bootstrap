#!/usr/bin/env bash
# Validation functions for Xray WSL Client
# Provides input validation for protocols, UUIDs, ports, etc.

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ======================
# PROTOCOL VALIDATION
# ======================

# Validate protocol name
# Usage: validate_protocol "protocol_name"
validate_protocol() {
    local protocol="$1"

    case "$protocol" in
        "vless"|"vmess"|"trojan")
            log_debug "Valid protocol: $protocol"
            return 0
            ;;
        *)
            log_error "Invalid protocol: $protocol"
            log_error "Supported protocols: vless, vmess, trojan"

            # Suggest similar protocols for typos
            case "$protocol" in
                "vles"|"vlss"|"vles"|"vess")
                    log_error "Did you mean 'vless'?"
                    ;;
                "vmes"|"vmees"|"vmss")
                    log_error "Did you mean 'vmess'?"
                    ;;
                "trojen"|"troyan"|"trojan-go")
                    log_error "Did you mean 'trojan'?"
                    ;;
            esac

            return 11
            ;;
    esac
}

# ======================
# UUID VALIDATION
# ======================

# Validate UUID format (RFC 4122)
# Usage: validate_uuid "uuid_string"
validate_uuid() {
    local uuid="$1"

    # Convert to lowercase for case-insensitive comparison
    local uuid_lower="$(echo "$uuid" | tr '[:upper:]' '[:lower:]')"

    # UUID regex pattern
    local uuid_pattern="^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

    if [[ ! "$uuid_lower" =~ $uuid_pattern ]]; then
        log_error "Invalid UUID format: $uuid"
        log_error "Expected format: 12345678-abcd-1234-efgh-123456789012"
        log_error "Generate UUID with: uuidgen"
        return 11
    fi

    log_debug "Valid UUID format"
    return 0
}

# ======================
# PORT VALIDATION
# ======================

# Validate port number range
# Usage: validate_port "port_number" "port_name"
validate_port() {
    local port="$1"
    local port_name="${2:-port}"

    # Check if it's a number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid $port_name: $port (must be numeric)"
        return 11
    fi

    # Check range
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        log_error "Invalid $port_name: $port (must be 1-65535)"
        return 11
    fi

    # Check for commonly problematic ports
    case "$port" in
        22) log_warn "$port_name $port is SSH - ensure not conflicting with system SSH" ;;
        53) log_warn "$port_name $port is DNS - may conflict with system DNS" ;;
        80|8080) log_warn "$port_name $port is HTTP - may conflict with web services" ;;
        443) log_warn "$port_name $port is HTTPS - commonly used by other services" ;;
        3128|8888) log_warn "$port_name $port commonly used by other proxies" ;;
    esac

    log_debug "Valid $port_name: $port"
    return 0
}

# Check if port is available (not in use)
# Usage: check_port_available "port_number" "port_name"
check_port_available() {
    local port="$1"
    local port_name="${2:-port}"

    # Check if port is in use using ss (more reliable than netstat)
    if command_exists ss; then
        if ss -tuln | grep -q ":$port "; then
            log_error "$port_name $port is already in use"
            log_error "Check with: ss -tuln | grep :$port"
            log_error "Choose a different port or stop the conflicting service"
            return 14
        fi
    elif command_exists netstat; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_error "$port_name $port is already in use"
            log_error "Check with: netstat -tuln | grep :$port"
            return 14
        fi
    else
        log_warn "Cannot check port availability (ss/netstat not found)"
    fi

    log_debug "$port_name $port appears available"
    return 0
}

# ======================
# SECURITY VALIDATION
# ======================

# Validate security method for given protocol
# Usage: validate_security "protocol" "security_method"
validate_security() {
    local protocol="$1"
    local security="$2"

    case "$protocol" in
        "vless")
            case "$security" in
                "tls"|"xtls"|"reality"|"none")
                    log_debug "Valid security for $protocol: $security"
                    return 0
                    ;;
                *)
                    log_error "Invalid security '$security' for protocol '$protocol'"
                    log_error "Valid options for VLESS: tls, xtls, reality, none"
                    return 11
                    ;;
            esac
            ;;
        "vmess")
            case "$security" in
                "tls"|"none")
                    log_debug "Valid security for $protocol: $security"
                    return 0
                    ;;
                "xtls"|"reality")
                    log_error "Security '$security' not supported for VMess"
                    log_error "Valid options for VMess: tls, none"
                    return 11
                    ;;
                *)
                    log_error "Invalid security '$security' for protocol '$protocol'"
                    log_error "Valid options for VMess: tls, none"
                    return 11
                    ;;
            esac
            ;;
        "trojan")
            case "$security" in
                "tls")
                    log_debug "Valid security for $protocol: $security"
                    return 0
                    ;;
                "xtls"|"reality"|"none")
                    log_error "Security '$security' not supported for Trojan"
                    log_error "Trojan requires TLS security"
                    return 11
                    ;;
                *)
                    log_error "Invalid security '$security' for protocol '$protocol'"
                    log_error "Trojan requires TLS security"
                    return 11
                    ;;
            esac
            ;;
        *)
            log_error "Unknown protocol for security validation: $protocol"
            return 11
            ;;
    esac
}

# ======================
# REALITY VALIDATION
# ======================

# Validate Reality public key format
# Usage: validate_reality_public_key "public_key"
validate_reality_public_key() {
    local public_key="$1"

    # Reality public key is base64 encoded (typically 44 characters)
    if [[ ${#public_key} -lt 40 || ${#public_key} -gt 50 ]]; then
        log_error "Invalid Reality public key length: ${#public_key} characters"
        log_error "Expected 40-50 characters (base64 encoded)"
        return 11
    fi

    # Check if it's valid base64
    if ! echo "$public_key" | base64 -d >/dev/null 2>&1; then
        log_error "Invalid Reality public key format (not valid base64)"
        return 11
    fi

    log_debug "Valid Reality public key format"
    return 0
}

# Validate Reality short ID format
# Usage: validate_reality_short_id "short_id"
validate_reality_short_id() {
    local short_id="$1"

    # Short ID is hex string, 1-16 characters
    if [[ ! "$short_id" =~ ^[0-9a-fA-F]{1,16}$ ]]; then
        log_error "Invalid Reality short ID: $short_id"
        log_error "Must be hex string, 1-16 characters (e.g., abcd1234)"
        return 11
    fi

    log_debug "Valid Reality short ID format"
    return 0
}

# Validate Reality fingerprint
# Usage: validate_reality_fingerprint "fingerprint"
validate_reality_fingerprint() {
    local fingerprint="$1"

    case "$fingerprint" in
        "chrome"|"firefox"|"safari"|"ios"|"android"|"edge"|"360"|"qq")
            log_debug "Valid Reality fingerprint: $fingerprint"
            return 0
            ;;
        *)
            log_error "Invalid Reality fingerprint: $fingerprint"
            log_error "Valid options: chrome, firefox, safari, ios, android, edge, 360, qq"

            # Suggest corrections for common typos
            case "$fingerprint" in
                "Chrome"|"CHROME") log_error "Did you mean 'chrome' (lowercase)?" ;;
                "Firefox"|"FIREFOX") log_error "Did you mean 'firefox' (lowercase)?" ;;
                "Safari"|"SAFARI") log_error "Did you mean 'safari' (lowercase)?" ;;
            esac

            return 11
            ;;
    esac
}

# Validate complete Reality configuration
# Usage: validate_reality_config "public_key" "short_id" "fingerprint" "sni"
validate_reality_config() {
    local public_key="$1"
    local short_id="$2"
    local fingerprint="$3"
    local sni="$4"

    local errors=0

    if [[ -z "$public_key" ]]; then
        log_error "Reality public key is required"
        ((errors++))
    else
        validate_reality_public_key "$public_key" || ((errors++))
    fi

    if [[ -z "$short_id" ]]; then
        log_error "Reality short ID is required"
        ((errors++))
    else
        validate_reality_short_id "$short_id" || ((errors++))
    fi

    if [[ -z "$fingerprint" ]]; then
        log_error "Reality fingerprint is required"
        ((errors++))
    else
        validate_reality_fingerprint "$fingerprint" || ((errors++))
    fi

    if [[ -z "$sni" ]]; then
        log_error "Reality SNI (server name) is required"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Reality configuration has $errors error(s)"
        log_error "Reality requires all 4 parameters: public_key, short_id, fingerprint, sni"
        return 11
    fi

    log_debug "Valid Reality configuration"
    return 0
}

# ======================
# HOSTNAME VALIDATION
# ======================

# Validate hostname/domain format
# Usage: validate_hostname "hostname"
validate_hostname() {
    local hostname="$1"

    # Basic hostname validation (simplified)
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid hostname format: $hostname"
        log_error "Hostname should be a valid domain name or IP address"
        return 11
    fi

    log_debug "Valid hostname format"
    return 0
}

# ======================
# ENVIRONMENT VALIDATION
# ======================

# Validate all required environment variables for given protocol
# Usage: validate_env_for_protocol "protocol"
validate_env_for_protocol() {
    local protocol="$1"
    local errors=0

    log_debug "Validating environment for protocol: $protocol"

    # Base required variables for all protocols
    local base_vars=("XRAY_PROTOCOL" "XRAY_SERVER_HOST" "XRAY_SERVER_PORT" "XRAY_UUID_OR_PASS" "XRAY_LOCAL_SOCKS_PORT")

    for var in "${base_vars[@]}"; do
        if ! require_env "$var"; then
            ((errors++))
        fi
    done

    # Return early if base variables are missing
    if [[ $errors -gt 0 ]]; then
        return 10
    fi

    # Protocol-specific validation
    validate_protocol "$XRAY_PROTOCOL" || ((errors++))
    validate_hostname "$XRAY_SERVER_HOST" || ((errors++))
    validate_port "$XRAY_SERVER_PORT" "server port" || ((errors++))
    validate_port "$XRAY_LOCAL_SOCKS_PORT" "SOCKS port" || ((errors++))

    # UUID validation for VLESS/VMess
    if [[ "$protocol" == "vless" || "$protocol" == "vmess" ]]; then
        validate_uuid "$XRAY_UUID_OR_PASS" || ((errors++))
    fi

    # HTTP port validation (if set)
    if [[ -n "${XRAY_LOCAL_HTTP_PORT:-}" ]]; then
        validate_port "$XRAY_LOCAL_HTTP_PORT" "HTTP port" || ((errors++))

        # Check for port conflicts
        if [[ "$XRAY_LOCAL_HTTP_PORT" == "$XRAY_LOCAL_SOCKS_PORT" ]]; then
            log_error "HTTP port and SOCKS port cannot be the same: $XRAY_LOCAL_SOCKS_PORT"
            ((errors++))
        fi
    fi

    # Security validation
    if [[ -n "${XRAY_SECURITY:-}" ]]; then
        validate_security "$protocol" "$XRAY_SECURITY" || ((errors++))

        # Reality-specific validation
        if [[ "$XRAY_SECURITY" == "reality" ]]; then
            validate_reality_config "${XRAY_PUBLIC_KEY:-}" "${XRAY_SHORT_ID:-}" "${XRAY_FINGERPRINT:-}" "${XRAY_SNI:-}" || ((errors++))
        fi
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Environment validation failed with $errors error(s)"
        return 11
    fi

    log_info "Environment validation successful"
    return 0
}

# Export validation functions
export -f validate_protocol validate_uuid validate_port check_port_available
export -f validate_security validate_reality_public_key validate_reality_short_id
export -f validate_reality_fingerprint validate_reality_config validate_hostname
export -f validate_env_for_protocol