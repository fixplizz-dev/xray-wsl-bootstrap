#!/usr/bin/env bash
# Xray Configuration Generator
# Generates xray.json from environment variables

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/validate.sh"

# Configuration constants
readonly DEFAULT_OUTPUT_FILE="$PROJECT_ROOT/configs/xray.json"
readonly TEMPLATE_FILE="$PROJECT_ROOT/configs/xray.template.json"

#######################################
# Check system requirements for config generation
#######################################
check_system_requirements() {
    log_info "Checking system requirements..."

    # Check bash version
    if ! check_bash_version; then
        log_error "Bash 5.x or higher is required"
        exit 1
    fi

    # Check required commands for config generation
    local required_commands=("jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            log_error "Please install: sudo apt update && sudo apt install -y jq"
            exit 1
        fi
    done

    log_success "System requirements check passed"
}

# ======================
# HELP FUNCTIONS
# ======================

show_help() {
    local lang="${XRAY_CLIENT_LANG:-en}"

    case "$lang" in
        "ru")
            cat << 'EOF'
Использование: generate-config.sh [ОПЦИИ] [ВЫХОДНОЙ_ФАЙЛ]

Генерирует конфигурацию Xray из переменных окружения (.env).

АРГУМЕНТЫ:
    ВЫХОДНОЙ_ФАЙЛ    Путь к выходному файлу JSON (по умолчанию: configs/xray.json)

ОПЦИИ:
    --help, -h       Показать эту справку
    --validate-only  Только проверить переменные, не генерировать файл
    --stdout         Вывести JSON в stdout вместо файла

ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ:
    Все конфигурационные переменные загружаются из .env файла.
    См. .env.example для примера конфигурации.

ПРИМЕРЫ:
    # Сгенерировать конфигурацию в файл по умолчанию
    ./scripts/generate-config.sh

    # Сгенерировать в указанный файл
    ./scripts/generate-config.sh /tmp/xray-test.json

    # Только проверить конфигурацию
    ./scripts/generate-config.sh --validate-only

    # Вывести JSON в терминал
    ./scripts/generate-config.sh --stdout

КОДЫ ВЫХОДА:
    0   Успех
    10  Отсутствует .env или обязательные переменные
    11  Неверный формат значений
    12  Ошибка записи файла
EOF
            ;;
        *)
            cat << 'EOF'
Usage: generate-config.sh [OPTIONS] [OUTPUT_FILE]

Generates Xray configuration JSON from environment variables (.env).

ARGUMENTS:
    OUTPUT_FILE      Path to output JSON file (default: configs/xray.json)

OPTIONS:
    --help, -h       Show this help message
    --validate-only  Only validate environment, don't generate file
    --stdout         Output JSON to stdout instead of file

ENVIRONMENT:
    All configuration variables are loaded from .env file.
    See .env.example for configuration template.

EXAMPLES:
    # Generate config to default file
    ./scripts/generate-config.sh

    # Generate to specified file
    ./scripts/generate-config.sh /tmp/xray-test.json

    # Only validate configuration
    ./scripts/generate-config.sh --validate-only

    # Output JSON to terminal
    ./scripts/generate-config.sh --stdout

EXIT CODES:
    0   Success
    10  Missing .env or required variables
    11  Invalid value format
    12  File write error
EOF
            ;;
    esac
}

# ======================
# DEPENDENCY CHECKS
# ======================

check_dependencies() {
    local missing_deps=()

    if ! command_exists jq; then
        missing_deps+=("jq")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"

        case "${XRAY_CLIENT_LANG:-en}" in
            "ru")
                log_error "Установите зависимости:"
                log_error "  Ubuntu/Debian: sudo apt update && sudo apt install ${missing_deps[*]}"
                ;;
            *)
                log_error "Install dependencies:"
                log_error "  Ubuntu/Debian: sudo apt update && sudo apt install ${missing_deps[*]}"
                ;;
        esac

        exit 12
    fi
}

# ======================
# JSON GENERATION FUNCTIONS
# ======================

# Generate protocol-specific settings
generate_protocol_settings() {
    local protocol="$1"

    case "$protocol" in
        "vless")
            jq -n \
                --arg uuid "$XRAY_UUID_OR_PASS" \
                '{
                    "vnext": [
                        {
                            "address": $ENV.XRAY_SERVER_HOST,
                            "port": ($ENV.XRAY_SERVER_PORT | tonumber),
                            "users": [
                                {
                                    "id": $uuid,
                                    "encryption": "none",
                                    "flow": (if $ENV.XRAY_SECURITY == "xtls" then "xtls-rprx-vision" else "" end)
                                }
                            ]
                        }
                    ]
                }'
            ;;
        "vmess")
            jq -n \
                --arg uuid "$XRAY_UUID_OR_PASS" \
                '{
                    "vnext": [
                        {
                            "address": $ENV.XRAY_SERVER_HOST,
                            "port": ($ENV.XRAY_SERVER_PORT | tonumber),
                            "users": [
                                {
                                    "id": $uuid,
                                    "alterId": 0,
                                    "security": "auto"
                                }
                            ]
                        }
                    ]
                }'
            ;;
        "trojan")
            jq -n \
                --arg password "$XRAY_UUID_OR_PASS" \
                '{
                    "servers": [
                        {
                            "address": $ENV.XRAY_SERVER_HOST,
                            "port": ($ENV.XRAY_SERVER_PORT | tonumber),
                            "password": $password
                        }
                    ]
                }'
            ;;
        *)
            log_error "Unsupported protocol: $protocol"
            exit 11
            ;;
    esac
}

# Generate stream settings (TLS, XTLS, Reality)
generate_stream_settings() {
    local security="${XRAY_SECURITY:-none}"

    case "$security" in
        "none")
            echo "{}"
            ;;
        "tls")
            jq -n \
                '{
                    "network": "tcp",
                    "security": "tls",
                    "tlsSettings": {
                        "serverName": $ENV.XRAY_SNI,
                        "allowInsecure": false
                    }
                }'
            ;;
        "xtls")
            jq -n \
                '{
                    "network": "tcp",
                    "security": "xtls",
                    "xtlsSettings": {
                        "serverName": $ENV.XRAY_SNI,
                        "allowInsecure": false
                    }
                }'
            ;;
        "reality")
            jq -n \
                '{
                    "network": "tcp",
                    "security": "reality",
                    "realitySettings": {
                        "serverName": $ENV.XRAY_SNI,
                        "fingerprint": $ENV.XRAY_FINGERPRINT,
                        "publicKey": $ENV.XRAY_PUBLIC_KEY,
                        "shortId": $ENV.XRAY_SHORT_ID
                    }
                }'
            ;;
        *)
            log_error "Unsupported security: $security"
            exit 11
            ;;
    esac
}

# Generate HTTP inbound if HTTP port is specified
generate_http_inbound() {
    if [[ -n "${XRAY_LOCAL_HTTP_PORT:-}" ]]; then
        jq -n \
            '{
                "tag": "http-in",
                "port": ($ENV.XRAY_LOCAL_HTTP_PORT | tonumber),
                "listen": "127.0.0.1",
                "protocol": "http",
                "settings": {}
            }'
    else
        echo "null"
    fi
}

# Generate complete Xray configuration
generate_config() {
    local protocol_settings="$(generate_protocol_settings "$XRAY_PROTOCOL")"
    local stream_settings="$(generate_stream_settings)"
    local http_inbound="$(generate_http_inbound)"

    # Create the complete configuration
    jq -n \
        --argjson protocol_settings "$protocol_settings" \
        --argjson stream_settings "$stream_settings" \
        --argjson http_inbound "$http_inbound" \
        '{
            "log": {
                "loglevel": "warning"
            },
            "inbounds": (
                [
                    {
                        "tag": "socks-in",
                        "port": ($ENV.XRAY_LOCAL_SOCKS_PORT | tonumber),
                        "listen": "127.0.0.1",
                        "protocol": "socks",
                        "settings": {
                            "auth": "noauth",
                            "udp": true
                        }
                    }
                ] + (if $http_inbound != null then [$http_inbound] else [] end)
            ),
            "outbounds": [
                {
                    "tag": "proxy",
                    "protocol": $ENV.XRAY_PROTOCOL,
                    "settings": $protocol_settings,
                    "streamSettings": $stream_settings
                },
                {
                    "tag": "direct",
                    "protocol": "freedom"
                },
                {
                    "tag": "block",
                    "protocol": "blackhole"
                }
            ],
            "routing": {
                "domainStrategy": "IPIfNonMatch",
                "rules": [
                    {
                        "type": "field",
                        "domain": ["geosite:category-ads-all"],
                        "outboundTag": "block"
                    },
                    {
                        "type": "field",
                        "protocol": ["bittorrent"],
                        "outboundTag": "direct"
                    },
                    {
                        "type": "field",
                        "ip": ["geoip:private", "geoip:cn"],
                        "outboundTag": "direct"
                    }
                ]
            }
        }'
}

# ======================
# MAIN FUNCTION
# ======================

main() {
    local output_file="$DEFAULT_OUTPUT_FILE"
    local validate_only=false
    local output_stdout=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --validate-only)
                validate_only=true
                shift
                ;;
            --stdout)
                output_stdout=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                log_error "Use --help for usage information"
                exit 11
                ;;
            *)
                output_file="$1"
                shift
                ;;
        esac
    done

    # Check system requirements
    check_system_requirements

    # Check dependencies
    check_dependencies

    # Load and validate environment
    load_env
    validate_env_for_protocol "$XRAY_PROTOCOL"

    # If only validating, exit here
    if [[ "$validate_only" == "true" ]]; then
        log_info "Environment validation successful"
        exit 0
    fi

    # Generate configuration
    log_info "Generating Xray configuration for protocol: $XRAY_PROTOCOL"
    local config_json="$(generate_config)"

    # Output configuration
    if [[ "$output_stdout" == "true" ]]; then
        echo "$config_json"
    else
        # Ensure output directory exists
        local output_dir="$(dirname "$output_file")"
        mkdir -p "$output_dir"

        # Write to file
        echo "$config_json" > "$output_file"
        log_info "Configuration written to: $output_file"

        # Validate generated JSON
        if ! jq . "$output_file" >/dev/null 2>&1; then
            log_error "Generated invalid JSON configuration"
            exit 12
        fi
    fi

    log_info "$(get_localized_message 'config.generated')"
}

# Add localized message for config generation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Add the localized message function extension
    get_localized_message() {
        local key="$1"
        local lang="${XRAY_CLIENT_LANG:-en}"

        case "$key" in
            "config.generated")
                case "$lang" in
                    "ru") echo "Конфигурация успешно сгенерирована" ;;
                    *) echo "Configuration generated successfully" ;;
                esac
                ;;
            *)
                # Call the original function from common.sh
                source "$PROJECT_ROOT/lib/common.sh"
                get_localized_message "$key"
                ;;
        esac
    }

    main "$@"
fi