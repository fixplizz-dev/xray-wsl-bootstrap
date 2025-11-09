#!/usr/bin/env bash
# Common functions and utilities for Xray WSL Client
# Provides logging, environment loading, and helper functions

set -euo pipefail

# Global constants
if [[ -z "${SCRIPT_NAME:-}" ]]; then
    readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
fi
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [[ -z "${XRAY_LOG_FORMAT:-}" ]]; then
    readonly XRAY_LOG_FORMAT="timestamp_level_script_function_message"
fi

# Color constants (only for interactive terminals)
if [[ -z "${RED:-}" ]]; then
    if [[ -t 2 ]]; then
        readonly RED='\033[0;31m'
        readonly GREEN='\033[0;32m'
        readonly YELLOW='\033[1;33m'
        readonly BLUE='\033[0;34m'
        readonly CYAN='\033[0;36m'
        readonly MAGENTA='\033[0;35m'
        readonly BOLD='\033[1m'
        readonly DIM='\033[2m'
        readonly NC='\033[0m'  # No Color
    else
        readonly RED=''
        readonly GREEN=''
        readonly YELLOW=''
        readonly BLUE=''
        readonly CYAN=''
        readonly MAGENTA=''
        readonly BOLD=''
        readonly DIM=''
        readonly NC=''
    fi
fi

# ======================
# SYSTEM CHECKS
# ======================

# Check if Bash version is 5.x or higher
check_bash_version() {
    local bash_version="${BASH_VERSION%%.*}"
    if [[ "$bash_version" -lt 5 ]]; then
        return 1
    fi
    return 0
}

# ======================
# LOGGING FUNCTIONS
# ======================

# Get current timestamp in ISO 8601 format
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get calling function name
get_caller() {
    # Skip get_caller itself and the log_* function
    local caller="${FUNCNAME[2]:-main}"
    echo "$caller"
}

# Log info message (green prefix for interactive terminals)
# Usage: log_info "message"
log_info() {
    local message="$1"
    local timestamp="$(get_timestamp)"
    local caller="$(get_caller)"

    # Plain text format for logs and automation
    printf "%s INFO %s %s %s\n" "$timestamp" "$SCRIPT_NAME" "$caller" "$message" >&2

    # Optional colored output for interactive terminals
    if [[ -t 2 ]] && [[ "${XRAY_DISABLE_COLORS:-}" != "1" ]]; then
        printf "${GREEN}[INFO]${NC} %s\n" "$message" >&1
    fi
}

# Log warning message (yellow prefix for interactive terminals)
# Usage: log_warn "message"
log_warn() {
    local message="$1"
    local timestamp="$(get_timestamp)"
    local caller="$(get_caller)"

    printf "%s WARN %s %s %s\n" "$timestamp" "$SCRIPT_NAME" "$caller" "$message" >&2

    if [[ -t 2 ]] && [[ "${XRAY_DISABLE_COLORS:-}" != "1" ]]; then
        printf "${YELLOW}[WARN]${NC} %s\n" "$message" >&1
    fi
}

# Log error message (red prefix for interactive terminals)
# Usage: log_error "message"
log_error() {
    local message="$1"
    local timestamp="$(get_timestamp)"
    local caller="$(get_caller)"

    printf "%s ERROR %s %s %s\n" "$timestamp" "$SCRIPT_NAME" "$caller" "$message" >&2

    if [[ -t 2 ]] && [[ "${XRAY_DISABLE_COLORS:-}" != "1" ]]; then
        printf "${RED}[ERROR]${NC} %s\n" "$message" >&1
    fi
}

# Log success message (green prefix for interactive terminals)
# Usage: log_success "message"
log_success() {
    local message="$1"
    local timestamp="$(get_timestamp)"
    local caller="$(get_caller)"

    printf "%s INFO %s %s %s\n" "$timestamp" "$SCRIPT_NAME" "$caller" "$message" >&2

    if [[ -t 2 ]] && [[ "${XRAY_DISABLE_COLORS:-}" != "1" ]]; then
        printf "${GREEN}[SUCCESS]${NC} %s\n" "$message" >&1
    fi
}

# Log debug message (only if XRAY_DEBUG=1)
# Usage: log_debug "message"
log_debug() {
    if [[ "${XRAY_DEBUG:-}" == "1" ]]; then
        local message="$1"
        local timestamp="$(get_timestamp)"
        local caller="$(get_caller)"

        printf "%s DEBUG %s %s %s\n" "$timestamp" "$SCRIPT_NAME" "$caller" "$message" >&2

        if [[ -t 2 ]] && [[ "${XRAY_DISABLE_COLORS:-}" != "1" ]]; then
            printf "${BLUE}[DEBUG]${NC} %s\n" "$message" >&1
        fi
    fi
}

# ======================
# ENVIRONMENT FUNCTIONS
# ======================

# Load and validate .env file
# Usage: load_env [env_file_path]
load_env() {
    local env_file="${1:-$PROJECT_ROOT/.env}"

    if [[ ! -f "$env_file" ]]; then
        log_error ".env file not found: $env_file"
        log_error "Copy .env.example to .env and configure with your server details"
        exit 10
    fi

    log_debug "Loading environment from: $env_file"

    # Check file permissions for security
    local perms="$(stat -c %a "$env_file" 2>/dev/null || echo "000")"
    if [[ "$perms" != "600" ]]; then
        log_warn ".env file permissions are $perms, should be 600 for security"
        log_warn "Run: chmod 600 $env_file"
    fi

    # Source the .env file in a subshell to validate syntax first
    if ! (set -e; source "$env_file") >/dev/null 2>&1; then
        log_error "Invalid .env file syntax in: $env_file"
        exit 11
    fi

    # Load variables if syntax is valid
    set -a  # Export all variables
    source "$env_file"
    set +a  # Stop exporting

    log_debug "Environment loaded successfully"
}

# Check if required environment variable is set and not empty
# Usage: require_env VAR_NAME
require_env() {
    local var_name="$1"
    local var_value="${!var_name:-}"

    if [[ -z "$var_value" ]]; then
        log_error "Required environment variable not set: $var_name"
        return 1
    fi

    log_debug "Required variable $var_name is set"
    return 0
}

# Check if all required environment variables are set
# Usage: check_required_env VAR1 VAR2 VAR3
check_required_env() {
    local missing_vars=()

    for var_name in "$@"; do
        if ! require_env "$var_name"; then
            missing_vars+=("$var_name")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Check .env.example for required configuration"
        exit 10
    fi
}

# ======================
# UTILITY FUNCTIONS
# ======================

# Exit with error code and message
# Usage: die "error message" [exit_code]
die() {
    local message="$1"
    local exit_code="${2:-1}"

    log_error "$message"
    exit "$exit_code"
}

# Check if command exists
# Usage: command_exists command_name
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
# Usage: is_root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Check if systemd is available and running
# Usage: has_systemd
has_systemd() {
    command_exists systemctl && systemctl is-system-running >/dev/null 2>&1
}

# Check if required commands are available
# Usage: check_dependencies "cmd1" "cmd2" ...
check_dependencies() {
    local missing_deps=()
    local cmd

    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Install dependencies:"
        log_error "  Ubuntu/Debian: sudo apt update && sudo apt install ${missing_deps[*]}"
        return 1
    fi

    return 0
}

# Get localized message based on XRAY_CLIENT_LANG
# Usage: get_localized_message "key"
get_localized_message() {
    local key="$1"
    local lang="${XRAY_CLIENT_LANG:-en}"

    # Fallback to English if language not supported
    if [[ "$lang" != "ru" ]]; then
        lang="en"
    fi

    # Message definitions (can be extended)
    case "$key" in
        "install.success")
            case "$lang" in
                "ru") echo "Установка завершена успешно" ;;
                *) echo "Installation completed successfully" ;;
            esac
            ;;
        "service.starting")
            case "$lang" in
                "ru") echo "Запуск сервиса..." ;;
                *) echo "Starting service..." ;;
            esac
            ;;
        "service.stopped")
            case "$lang" in
                "ru") echo "Сервис остановлен" ;;
                *) echo "Service stopped" ;;
            esac
            ;;
        "ip_detected")
            case "$lang" in
                "ru") echo "Обнаружен IP $2 через $3" ;;
                *) echo "Detected IP $2 via $3" ;;
            esac
            ;;
        "ip_service_failed")
            case "$lang" in
                "ru") echo "Сервис $2 недоступен" ;;
                *) echo "Service $2 unavailable" ;;
            esac
            ;;
        "ip_all_services_failed")
            case "$lang" in
                "ru") echo "Все IP сервисы недоступны" ;;
                *) echo "All IP services failed" ;;
            esac
            ;;
        "geolocation_failed")
            case "$lang" in
                "ru") echo "Не удалось получить информацию о геолокации" ;;
                *) echo "Failed to get geolocation information" ;;
            esac
            ;;
        "dns_leak_check_start")
            case "$lang" in
                "ru") echo "Проверка утечек DNS..." ;;
                *) echo "Checking DNS leaks..." ;;
            esac
            ;;
        "dns_resolution_failed")
            case "$lang" in
                "ru") echo "Не удалось разрешить $2 через $3" ;;
                *) echo "Failed to resolve $2 via $3" ;;
            esac
            ;;
        "dns_resolution_timeout")
            case "$lang" in
                "ru") echo "Таймаут разрешения $2 через $3" ;;
                *) echo "DNS resolution timeout for $2 via $3" ;;
            esac
            ;;
        "dns_inconsistent_results")
            case "$lang" in
                "ru") echo "Обнаружены несовместимые DNS результаты" ;;
                *) echo "Inconsistent DNS results detected" ;;
            esac
            ;;
        "dns_no_leaks_detected")
            case "$lang" in
                "ru") echo "Утечки DNS не обнаружены" ;;
                *) echo "No DNS leaks detected" ;;
            esac
            ;;
        "dns_leaks_detected")
            case "$lang" in
                "ru") echo "ОБНАРУЖЕНЫ УТЕЧКИ DNS!" ;;
                *) echo "DNS LEAKS DETECTED!" ;;
            esac
            ;;
        "missing_timeout_value")
            case "$lang" in
                "ru") echo "Отсутствует значение таймаута" ;;
                *) echo "Missing timeout value" ;;
            esac
            ;;
        "unknown_option")
            case "$lang" in
                "ru") echo "Неизвестная опция: $2" ;;
                *) echo "Unknown option: $2" ;;
            esac
            ;;
        "check_ip_start")
            case "$lang" in
                "ru") echo "Начинаем проверку IP и DNS..." ;;
                *) echo "Starting IP and DNS check..." ;;
            esac
            ;;
        "external_ip")
            case "$lang" in
                "ru") echo "Внешний IP" ;;
                *) echo "External IP" ;;
            esac
            ;;
        "location")
            case "$lang" in
                "ru") echo "Местоположение" ;;
                *) echo "Location" ;;
            esac
            ;;
        "failed_to_get_ip")
            case "$lang" in
                "ru") echo "Не удалось получить внешний IP" ;;
                *) echo "Failed to get external IP" ;;
            esac
            ;;
        "check_complete_success")
            case "$lang" in
                "ru") echo "Проверка завершена успешно" ;;
                *) echo "Check completed successfully" ;;
            esac
            ;;
        "check_complete_dns_issues")
            case "$lang" in
                "ru") echo "Проверка завершена с проблемами DNS" ;;
                *) echo "Check completed with DNS issues" ;;
            esac
            ;;
        "install.checking_requirements")
            case "$lang" in
                "ru") echo "Проверка системных требований..." ;;
                *) echo "Checking system requirements..." ;;
            esac
            ;;
        "install.os_unsupported")
            case "$lang" in
                "ru") echo "Неподдерживаемая операционная система" ;;
                *) echo "Unsupported operating system" ;;
            esac
            ;;
        "install.os_untested")
            case "$lang" in
                "ru") echo "Нетестированная ОС: $2 (может работать)" ;;
                *) echo "Untested OS: $2 (may work)" ;;
            esac
            ;;
        "install.systemd_required")
            case "$lang" in
                "ru") echo "Требуется systemd для управления сервисами" ;;
                *) echo "systemd is required for service management" ;;
            esac
            ;;
        "install.arch_detected")
            case "$lang" in
                "ru") echo "Обнаружена архитектура: $2 (Xray: $3)" ;;
                *) echo "Detected architecture: $2 (Xray: $3)" ;;
            esac
            ;;
        "install.release_fetch_failed")
            case "$lang" in
                "ru") echo "Не удалось получить информацию о релизе" ;;
                *) echo "Failed to fetch release information" ;;
            esac
            ;;
        "install.no_binary_for_arch")
            case "$lang" in
                "ru") echo "Нет бинарного файла для архитектуры: $2" ;;
                *) echo "No binary available for architecture: $2" ;;
            esac
            ;;
        "install.downloading_xray")
            case "$lang" in
                "ru") echo "Загрузка Xray $2..." ;;
                *) echo "Downloading Xray $2..." ;;
            esac
            ;;
        "install.download_failed")
            case "$lang" in
                "ru") echo "Ошибка загрузки" ;;
                *) echo "Download failed" ;;
            esac
            ;;
        "install.download_empty")
            case "$lang" in
                "ru") echo "Загруженный файл пуст или поврежден" ;;
                *) echo "Downloaded file is empty or corrupted" ;;
            esac
            ;;
        "install.extracting_xray")
            case "$lang" in
                "ru") echo "Извлечение архива..." ;;
                *) echo "Extracting archive..." ;;
            esac
            ;;
        "install.extract_failed")
            case "$lang" in
                "ru") echo "Ошибка извлечения архива" ;;
                *) echo "Archive extraction failed" ;;
            esac
            ;;
        "install.binary_installed")
            case "$lang" in
                "ru") echo "Бинарный файл установлен: $2" ;;
                *) echo "Binary installed: $2" ;;
            esac
            ;;
        "install.binary_not_found")
            case "$lang" in
                "ru") echo "Бинарный файл не найден в архиве" ;;
                *) echo "Binary not found in archive" ;;
            esac
            ;;
        "install.binary_verification_failed")
            case "$lang" in
                "ru") echo "Ошибка проверки бинарного файла" ;;
                *) echo "Binary verification failed" ;;
            esac
            ;;
        "install.binary_verified")
            case "$lang" in
                "ru") echo "Бинарный файл проверен: $2" ;;
                *) echo "Binary verified: $2" ;;
            esac
            ;;
        "install.creating_config")
            case "$lang" in
                "ru") echo "Создание конфигурации..." ;;
                *) echo "Creating configuration..." ;;
            esac
            ;;
        "install.config_generation_failed")
            case "$lang" in
                "ru") echo "Ошибка генерации конфигурации" ;;
                *) echo "Configuration generation failed" ;;
            esac
            ;;
        "install.config_created")
            case "$lang" in
                "ru") echo "Конфигурация создана: $2" ;;
                *) echo "Configuration created: $2" ;;
            esac
            ;;
        "install.setting_up_service")
            case "$lang" in
                "ru") echo "Настройка сервиса $2..." ;;
                *) echo "Setting up service $2..." ;;
            esac
            ;;
        "install.service_template_missing")
            case "$lang" in
                "ru") echo "Отсутствует шаблон сервиса: $2" ;;
                *) echo "Service template missing: $2" ;;
            esac
            ;;
        "install.service_enable_failed")
            case "$lang" in
                "ru") echo "Ошибка активации сервиса" ;;
                *) echo "Failed to enable service" ;;
            esac
            ;;
        "install.service_created")
            case "$lang" in
                "ru") echo "Сервис создан: $2" ;;
                *) echo "Service created: $2" ;;
            esac
            ;;
        "install.service_start_failed")
            case "$lang" in
                "ru") echo "Ошибка запуска сервиса" ;;
                *) echo "Failed to start service" ;;
            esac
            ;;
        "install.service_started_successfully")
            case "$lang" in
                "ru") echo "Сервис успешно запущен" ;;
                *) echo "Service started successfully" ;;
            esac
            ;;
        "install.service_failed_to_start")
            case "$lang" in
                "ru") echo "Сервис не смог запуститься" ;;
                *) echo "Service failed to start" ;;
            esac
            ;;
        "install.starting")
            case "$lang" in
                "ru") echo "Начинаем установку Xray WSL Bootstrap v$2" ;;
                *) echo "Starting Xray WSL Bootstrap installation v$2" ;;
            esac
            ;;
        "install.config_validation_failed")
            case "$lang" in
                "ru") echo "Ошибка валидации конфигурации" ;;
                *) echo "Configuration validation failed" ;;
            esac
            ;;
        "install.root_required")
            case "$lang" in
                "ru") echo "Требуются права root для установки" ;;
                *) echo "Root privileges required for installation" ;;
            esac
            ;;
        "install.already_installed")
            case "$lang" in
                "ru") echo "Xray уже установлен: $2" ;;
                *) echo "Xray already installed: $2" ;;
            esac
            ;;
        "install.missing_version_value")
            case "$lang" in
                "ru") echo "Отсутствует значение версии" ;;
                *) echo "Missing version value" ;;
            esac
            ;;
        *)
            echo "Unknown message key: $key"
            ;;
    esac
}

# Filter sensitive information from logs
# Usage: filter_secrets < input
filter_secrets() {
    # Remove UUIDs, passwords, and keys from log output
    sed -E \
        -e 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/**UUID**/gi' \
        -e 's/(password|pass|key|secret|token)=[^[:space:]]+/\1=**HIDDEN**/gi' \
        -e 's/"(password|pass|key|secret|token)":[[:space:]]*"[^"]*"/"'"'"'\1'"'"'":**HIDDEN**/gi'
}

# ======================
# INITIALIZATION
# ======================

# Initialize logging
log_debug "Common library loaded from: ${BASH_SOURCE[0]}"

# Export functions for use in other scripts
export -f log_info log_warn log_error log_debug
export -f load_env require_env check_required_env
export -f command_exists has_systemd check_dependencies
export -f get_localized_message filter_secrets