#!/bin/bash
set -euo pipefail

# Load common functions
source "$(dirname "$0")/../lib/common.sh"

# Script constants
readonly CHECK_IP_SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="0.1.0"

#######################################
# Check system requirements for IP checking
#######################################
check_system_requirements() {
    # Check bash version
    if ! check_bash_version; then
        log_error "Bash 5.x or higher is required"
        exit 1
    fi

    # Check required commands
    local required_commands=("curl" "dig")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            log_error "Please install: sudo apt update && sudo apt install -y curl dnsutils"
            exit 1
        fi
    done
}

# External IP services (multiple for redundancy)
readonly IP_SERVICES=(
    "https://ip.me"
    "https://ipinfo.io/ip"
    "https://icanhazip.com"
    "https://checkip.amazonaws.com"
)

# DNS leak test services
readonly DNS_SERVICES=(
    "1.1.1.1"     # Cloudflare
    "8.8.8.8"     # Google
    "208.67.222.222"  # OpenDNS
)

# Test domains for DNS resolution
readonly TEST_DOMAINS=(
    "google.com"
    "cloudflare.com"
    "github.com"
)

# Geolocation API for IP info
readonly GEO_API="https://ipapi.co/{ip}/json/"

#######################################
# Print script usage information
# Globals:
#   CHECK_IP_SCRIPT_NAME
# Arguments:
#   None
# Returns:
#   0
#######################################
show_help() {
    local script_name="$CHECK_IP_SCRIPT_NAME"
    cat << EOF
Usage: $script_name [OPTIONS]

Checks current external IP address and potential DNS leaks.

OPTIONS:
    --help, -h           Show this help message
    --quick             Quick check (IP only, no geolocation)
    --dns-only          Only check DNS leaks, skip IP check
    --json              Output results in JSON format
    --timeout SECONDS   Timeout for HTTP requests (default: 10)
    --verbose           Show detailed information

EXAMPLES:
    # Quick IP check
    ./$script_name --quick

    # Full check with DNS leak detection
    ./$script_name

    # Only DNS leak check
    ./$script_name --dns-only

    # JSON output for parsing
    ./$script_name --json

EXIT CODES:
    0   Success
    1   General error
    2   Network connectivity issues
    3   DNS leak detected

ENVIRONMENT:
    XRAY_CLIENT_LANG    Output language (en/ru, default: en)
    HTTP_PROXY          HTTP proxy for requests
    HTTPS_PROXY         HTTPS proxy for requests
EOF
}

#######################################
# Check external IP address using multiple services
# Globals:
#   IP_SERVICES
# Arguments:
#   timeout - request timeout in seconds
# Returns:
#   0 on success, 1 on failure
# Outputs:
#   IP address to stdout
#######################################
get_external_ip() {
    local timeout="${1:-10}"
    local ip=""
    local service=""

    for service in "${IP_SERVICES[@]}"; do
        log_debug "Trying IP service: $service"

        if ip=$(curl --silent --max-time "$timeout" --fail "$service" 2>/dev/null | tr -d '[:space:]'); then
            # Validate IP format
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                log_info "$(get_localized_message "ip_detected" "$ip" "$service")"
                echo "$ip"  # Only output the IP, not the log message
                return 0
            fi
        fi

        log_warn "$(get_localized_message "ip_service_failed" "$service")"
    done

    log_error "$(get_localized_message "ip_all_services_failed")"
    return 1
}

#######################################
# Get geolocation information for IP address
# Arguments:
#   ip - IP address to lookup
#   timeout - request timeout in seconds
# Returns:
#   0 on success, 1 on failure
# Outputs:
#   JSON geolocation data to stdout
#######################################
get_ip_geolocation() {
    local ip="$1"
    local timeout="${2:-10}"
    local url="${GEO_API/\{ip\}/$ip}"

    log_debug "Getting geolocation for IP: $ip"

    if curl --silent --max-time "$timeout" --fail "$url" 2>/dev/null; then
        return 0
    else
        log_warn "$(get_localized_message "geolocation_failed")"
        return 1
    fi
}

#######################################
# Check for DNS leaks by testing resolution servers
# Globals:
#   DNS_SERVICES
#   TEST_DOMAINS
# Arguments:
#   None
# Returns:
#   0 if no leaks, 3 if leaks detected
#######################################
check_dns_leaks() {
    local domain=""
    local dns_server=""
    local resolved_ip=""
    local leak_detected=0
    local results=()

    log_info "$(get_localized_message "dns_leak_check_start")"

    for domain in "${TEST_DOMAINS[@]}"; do
        log_debug "Testing DNS resolution for: $domain"

        for dns_server in "${DNS_SERVICES[@]}"; do
            if resolved_ip=$(dig @"$dns_server" +short +time=5 +tries=1 "$domain" 2>/dev/null | head -1); then
                if [[ -n "$resolved_ip" && $resolved_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                    results+=("$domain:$dns_server:$resolved_ip")
                    log_debug "$domain via $dns_server -> $resolved_ip"
                else
                    log_warn "$(get_localized_message "dns_resolution_failed" "$domain" "$dns_server")"
                    leak_detected=1
                fi
            else
                log_warn "$(get_localized_message "dns_resolution_timeout" "$domain" "$dns_server")"
                leak_detected=1
            fi
        done
    done

    # Analyze results for consistency
    local unique_ips
    unique_ips=$(printf '%s\n' "${results[@]}" | cut -d: -f3 | sort -u | wc -l)

    if [[ $unique_ips -gt 5 ]]; then
        log_warn "$(get_localized_message "dns_inconsistent_results")"
        leak_detected=1
    fi

    if [[ $leak_detected -eq 0 ]]; then
        log_info "$(get_localized_message "dns_no_leaks_detected")"
    else
        log_error "$(get_localized_message "dns_leaks_detected")"
    fi

    return $leak_detected
}

#######################################
# Output results in JSON format
# Arguments:
#   ip - external IP address
#   geo_data - geolocation JSON data
#   dns_status - DNS leak check status
# Returns:
#   0
#######################################
output_json_results() {
    local ip="$1"
    local geo_data="$2"
    local dns_status="$3"

    jq -n \
        --arg ip "$ip" \
        --argjson geo "$geo_data" \
        --argjson dns_ok "$([ $dns_status -eq 0 ] && echo true || echo false)" \
        '{
            "external_ip": $ip,
            "geolocation": $geo,
            "dns_leak_free": $dns_ok,
            "timestamp": now,
            "version": "'"$SCRIPT_VERSION"'"
        }'
}

#######################################
# Main function
# Arguments:
#   All command line arguments
# Returns:
#   Exit code based on results
#######################################
main() {
    local quick_mode=false
    local dns_only=false
    local json_output=false
    local verbose=false
    local timeout=10
    local external_ip=""
    local geo_data="{}"
    local dns_status=0

    # Check system requirements
    check_system_requirements

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --quick)
                quick_mode=true
                shift
                ;;
            --dns-only)
                dns_only=true
                shift
                ;;
            --json)
                json_output=true
                shift
                ;;
            --timeout)
                if [[ -n "${2:-}" ]]; then
                    timeout="$2"
                    shift 2
                else
                    log_error "$(get_localized_message "missing_timeout_value")"
                    exit 1
                fi
                ;;
            --verbose)
                verbose=true
                export XRAY_DEBUG=1
                shift
                ;;
            *)
                log_error "$(get_localized_message "unknown_option" "$1")"
                show_help
                exit 1
                ;;
        esac
    done

    # Check dependencies
    check_dependencies "curl" "dig"
    if [[ $json_output == true ]]; then
        check_dependencies "jq"
        export XRAY_DISABLE_COLORS=1  # Disable colors for clean JSON output
    fi

    log_info "$(get_localized_message "check_ip_start")"

    # Get external IP (unless DNS-only mode)
    if [[ $dns_only == false ]]; then
        if external_ip=$(get_external_ip "$timeout"); then
            if [[ $json_output == false ]]; then
                echo "$(get_localized_message "external_ip"): $external_ip"
            fi

            # Get geolocation (unless quick mode)
            if [[ $quick_mode == false ]]; then
                if geo_json=$(get_ip_geolocation "$external_ip" "$timeout"); then
                    geo_data="$geo_json"
                    if [[ $json_output == false ]]; then
                        local country city
                        country=$(echo "$geo_data" | jq -r '.country_name // "Unknown"')
                        city=$(echo "$geo_data" | jq -r '.city // "Unknown"')
                        echo "$(get_localized_message "location"): $city, $country"
                    fi
                fi
            fi
        else
            log_error "$(get_localized_message "failed_to_get_ip")"
            exit 2
        fi
    fi

    # Check DNS leaks (unless quick mode with IP-only)
    if [[ $quick_mode == false || $dns_only == true ]]; then
        check_dns_leaks
        dns_status=$?
    fi

    # Output results
    if [[ $json_output == true ]]; then
        output_json_results "$external_ip" "$geo_data" "$dns_status"
    else
        if [[ $dns_status -eq 0 ]]; then
            log_info "$(get_localized_message "check_complete_success")"
        else
            log_error "$(get_localized_message "check_complete_dns_issues")"
        fi
    fi

    # Exit with appropriate code
    if [[ $dns_status -ne 0 ]]; then
        exit 3
    fi

    exit 0
}

# Run main function with all arguments
main "$@"