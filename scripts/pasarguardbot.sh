#!/usr/bin/env bash
# PasarguardBot — Docker install & management script
# https://github.com/AmirKenzo/PasarguardBot
#
# Install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/AmirKenzo/PasarguardBot/main/scripts/pasarguardbot.sh)

set -euo pipefail

# ── Paths & constants ──────────────────────────────────────────────────────────
readonly SCRIPT_VERSION="1.1.1"
readonly CONFIG_DIR="/opt/pasarguardbot"
readonly COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
readonly ENV_FILE="${CONFIG_DIR}/.env"
readonly MANAGER_BIN="/usr/local/bin/pasarguardbot"
readonly MANAGER_SCRIPT="${CONFIG_DIR}/pasarguardbot.sh"
readonly SCRIPT_RAW_URL="https://raw.githubusercontent.com/AmirKenzo/PasarguardBot/main/scripts/pasarguardbot.sh"
readonly COMPOSE_RAW_URL="https://raw.githubusercontent.com/AmirKenzo/PasarguardBot/main/docker-compose.yml"
readonly ENV_EXAMPLE_RAW_URL="https://raw.githubusercontent.com/AmirKenzo/PasarguardBot/main/.env.example"
readonly BOT_IMAGE="ghcr.io/amirkenzo/pasarguardbot"
readonly BOT_IMAGE_TAG="latest"
readonly PHPMYADMIN_PORT=6163
readonly MIN_DISK_MB=2048
readonly CURL_CONNECT_TIMEOUT=10
readonly CURL_MAX_TIME=60
readonly CURL_RETRIES=3
readonly CURL_RETRY_DELAY=2

# Populated by detect_os()
OS_ID=""
OS_ID_LIKE=""
OS_VERSION_ID=""
OS_PRETTY_NAME=""
PKG_MANAGER=""

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    readonly C_RESET='\033[0m'
    readonly C_BOLD='\033[1m'
    readonly C_DIM='\033[2m'
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_CYAN='\033[0;36m'
else
    readonly C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN=''
fi

# ── Helpers ─────────────────────────────────────────────────────────────────
info()    { echo -e "${C_BLUE}[*]${C_RESET} $*"; }
ok()      { echo -e "${C_GREEN}[✓]${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
err()     { echo -e "${C_RED}[✗]${C_RESET} $*" >&2; }
die()     { err "$*"; exit 1; }

pause() {
    echo
    read -r -p "Press Enter to continue..." _ || true
}

rand_hex()  { openssl rand -hex "${1:-16}"; }
rand_b64()  { openssl rand -base64 "${1:-24}" | tr -d '/+=' | head -c "${1:-24}"; }

safe_clear() {
    if command -v clear &>/dev/null \
        && [[ -t 1 ]] \
        && [[ -n "${TERM:-}" ]]; then
        clear 2>/dev/null || true
    fi
}

# Always show versions as a single "vX.Y.Z" (supports both 1.0.0 and v1.0.0 tags).
format_version() {
    local v="${1:-}"
    [[ -n "$v" ]] || {
        printf '%s' '—'
        return 0
    }
    while [[ "$v" == [vV]* ]]; do
        v="${v:1}"
    done
    printf 'v%s' "$v"
}

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "This script must be run as root: sudo bash $0"
}

# Allow: bash <(curl -fsSL ...scripts/pasarguardbot.sh) without an outer sudo.
elevate_if_needed() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        return 0
    fi
    command -v sudo &>/dev/null || die "This script must be run as root (sudo not found)."

    local tmp src="${BASH_SOURCE[0]:-}"
    tmp="$(mktemp)"
    if [[ -n "$src" && -r "$src" ]]; then
        cp "$src" "$tmp"
    else
        rm -f "$tmp"
        die "Re-run as root: sudo bash <(curl -fsSL ${SCRIPT_RAW_URL})"
    fi
    chmod +x "$tmp"
    info "Root required — re-running with sudo..."
    exec sudo bash "$tmp" "$@"
}

curl_get() {
    curl --fail --silent --show-error --location \
        --retry "$CURL_RETRIES" \
        --retry-delay "$CURL_RETRY_DELAY" \
        --connect-timeout "$CURL_CONNECT_TIMEOUT" \
        --max-time "$CURL_MAX_TIME" \
        "$@"
}

curl_download() {
    local url="$1"
    local dest="$2"
    curl_get -o "$dest" "$url"
}

explain_network_failure() {
    local context="${1:-download}"
    err "Failed to ${context}."
    err "Possible causes: GitHub Raw unreachable, DNS failure, firewall, or network timeout."
    err "Check connectivity, then retry."
}

set_env_var() {
    local file="$1" key="$2" value="$3"
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    elif grep -q "^# ${key}=" "$file"; then
        sed -i "s|^# ${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >>"$file"
    fi
}

docker_compose() {
    if docker compose version &>/dev/null; then
        docker compose \
            --project-directory "$CONFIG_DIR" \
            -f "$COMPOSE_FILE" \
            --env-file "$ENV_FILE" \
            "$@"
    elif command -v docker-compose &>/dev/null; then
        warn "Using legacy docker-compose; prefer Docker Compose V2 (docker compose)."
        docker-compose \
            --project-directory "$CONFIG_DIR" \
            -f "$COMPOSE_FILE" \
            --env-file "$ENV_FILE" \
            "$@"
    else
        die "Docker Compose not found. Install Docker Compose V2 (docker compose) and retry."
    fi
}

is_installed() {
    [[ -f "$COMPOSE_FILE" && -f "$ENV_FILE" ]]
}

get_env_value() {
    local key="$1"
    local file="${2:-$ENV_FILE}"
    grep -E "^${key}=" "$file" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

# ── OS detection & bootstrap ───────────────────────────────────────────────────
detect_os() {
    [[ -f /etc/os-release ]] || die "Cannot detect OS: /etc/os-release not found."

    # shellcheck disable=SC1091
    . /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_ID_LIKE="${ID_LIKE:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_PRETTY_NAME="${PRETTY_NAME:-$OS_ID}"
    if [[ -n "$OS_VERSION_ID" ]]; then
        OS_PRETTY_NAME="${OS_PRETTY_NAME} (${OS_VERSION_ID})"
    fi

    local family
    family="$(printf '%s %s' "$OS_ID" "$OS_ID_LIKE" | tr '[:upper:]' '[:lower:]')"

    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt-get"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
    elif command -v apk &>/dev/null; then
        PKG_MANAGER="apk"
    else
        die "Unsupported package manager on ${OS_PRETTY_NAME}. Supported: apt-get, dnf, yum, pacman, zypper, apk."
    fi

    case "$family" in
        *ubuntu*|*debian*|*kali*|*linuxmint*|*pop*|*raspbian*) ;;
        *rhel*|*centos*|*rocky*|*alma*|*fedora*|*amzn*|*amazon*|*ol*|*oracle*) ;;
        *arch*|*manjaro*) ;;
        *suse*|*sles*) ;;
        *alpine*) ;;
        *)
            warn "OS '${OS_PRETTY_NAME}' is not in the tested list; continuing with ${PKG_MANAGER}."
            ;;
    esac
}

pkg_is_installed() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        apt-get)
            dpkg -s "$pkg" &>/dev/null
            ;;
        dnf|yum)
            rpm -q "$pkg" &>/dev/null
            ;;
        pacman)
            pacman -Qi "$pkg" &>/dev/null
            ;;
        zypper)
            rpm -q "$pkg" &>/dev/null
            ;;
        apk)
            apk info -e "$pkg" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

run_pkg_install() {
    local -a pkgs=("$@")
    local -a missing=()
    local pkg cmd_desc

    [[ ${#pkgs[@]} -gt 0 ]] || return 0

    for pkg in "${pkgs[@]}"; do
        if ! pkg_is_installed "$pkg"; then
            missing+=("$pkg")
        fi
    done

    [[ ${#missing[@]} -gt 0 ]] || return 0

    info "Installing packages: ${missing[*]}"
    cmd_desc="${PKG_MANAGER} install ${missing[*]}"

    case "$PKG_MANAGER" in
        apt-get)
            export DEBIAN_FRONTEND=noninteractive
            if ! apt-get update -y; then
                die "Package install failed on ${OS_PRETTY_NAME} (${PKG_MANAGER}). Failed command: apt-get update -y"
            fi
            if ! apt-get install -y --no-install-recommends "${missing[@]}"; then
                die "Package install failed on ${OS_PRETTY_NAME} (${PKG_MANAGER}). Failed command: ${cmd_desc}"
            fi
            ;;
        dnf)
            if ! dnf install -y "${missing[@]}"; then
                die "Package install failed on ${OS_PRETTY_NAME} (${PKG_MANAGER}). Failed command: ${cmd_desc}"
            fi
            ;;
        yum)
            if ! yum install -y "${missing[@]}"; then
                die "Package install failed on ${OS_PRETTY_NAME} (${PKG_MANAGER}). Failed command: ${cmd_desc}"
            fi
            ;;
        pacman)
            if ! pacman -Sy --noconfirm --needed "${missing[@]}"; then
                die "Package install failed on ${OS_PRETTY_NAME} (${PKG_MANAGER}). Failed command: ${cmd_desc}"
            fi
            ;;
        zypper)
            if ! zypper --non-interactive install -y "${missing[@]}"; then
                die "Package install failed on ${OS_PRETTY_NAME} (${PKG_MANAGER}). Failed command: ${cmd_desc}"
            fi
            ;;
        apk)
            if ! apk add --no-cache "${missing[@]}"; then
                die "Package install failed on ${OS_PRETTY_NAME} (${PKG_MANAGER}). Failed command: ${cmd_desc}"
            fi
            ;;
        *)
            die "Unsupported package manager: ${PKG_MANAGER}"
            ;;
    esac
}

base_packages_for_os() {
    case "$PKG_MANAGER" in
        apt-get)
            printf '%s\n' curl ca-certificates openssl coreutils ncurses-bin nano sed grep util-linux bash iproute2
            ;;
        dnf|yum)
            printf '%s\n' curl ca-certificates openssl coreutils ncurses nano sed grep util-linux bash iproute
            ;;
        pacman)
            printf '%s\n' curl ca-certificates openssl coreutils ncurses nano sed grep util-linux bash iproute2
            ;;
        zypper)
            printf '%s\n' curl ca-certificates openssl coreutils ncurses-utils nano sed grep util-linux bash iproute2
            ;;
        apk)
            printf '%s\n' curl ca-certificates openssl coreutils ncurses nano sed grep util-linux bash iproute2
            ;;
        *)
            die "Unsupported package manager: ${PKG_MANAGER}"
            ;;
    esac
}

install_base_packages() {
    local -a pkgs=()
    local line

    info "Bootstrapping base packages for ${OS_PRETTY_NAME} (${PKG_MANAGER})..."
    while IFS= read -r line; do
        [[ -n "$line" ]] && pkgs+=("$line")
    done < <(base_packages_for_os)

    run_pkg_install "${pkgs[@]}"

    for cmd in curl openssl sed grep; do
        command -v "$cmd" &>/dev/null || die "Required command '${cmd}' is missing after package install on ${OS_PRETTY_NAME}."
    done

    ok "Base packages ready."
}

bootstrap() {
    elevate_if_needed "$@"
    require_root
    detect_os
    install_base_packages
    ensure_manager_command
}

# ── Docker install ─────────────────────────────────────────────────────────────
docker_compose_available() {
    docker compose version &>/dev/null || command -v docker-compose &>/dev/null
}

docker_engine_ready() {
    command -v docker &>/dev/null && docker version &>/dev/null
}

start_docker_daemon() {
    if command -v systemctl &>/dev/null; then
        systemctl enable docker >/dev/null 2>&1 || true
        systemctl start docker 2>/dev/null || systemctl restart docker 2>/dev/null || true
        return 0
    fi
    if command -v rc-update &>/dev/null; then
        rc-update add docker default >/dev/null 2>&1 || true
        if command -v rc-service &>/dev/null; then
            rc-service docker start 2>/dev/null || true
        elif command -v service &>/dev/null; then
            service docker start 2>/dev/null || true
        fi
        return 0
    fi
    if command -v service &>/dev/null; then
        service docker start 2>/dev/null || true
    fi
}

wait_for_docker_daemon() {
    local i=0
    local max=30
    local log_out=""

    info "Waiting for Docker daemon..."
    while (( i < max )); do
        if docker info &>/dev/null; then
            ok "Docker daemon is ready."
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done

    err "Docker daemon did not become ready."
    if command -v systemctl &>/dev/null; then
        log_out="$(systemctl status docker --no-pager 2>&1 || true)"
        [[ -n "$log_out" ]] && echo "$log_out" >&2
        log_out="$(journalctl -u docker -n 40 --no-pager 2>&1 || true)"
        [[ -n "$log_out" ]] && echo "$log_out" >&2
    elif command -v rc-service &>/dev/null; then
        rc-service docker status >&2 || true
    fi
    die "Docker daemon is not running. Fix Docker, then retry."
}

verify_docker_stack() {
    command -v docker &>/dev/null || die "docker command not found after install."
    docker version >/dev/null || die "docker version failed. Docker Engine is not usable."
    if docker compose version &>/dev/null; then
        ok "Docker Compose V2 available: $(docker compose version --short 2>/dev/null || docker compose version | head -1)"
    elif command -v docker-compose &>/dev/null; then
        warn "Only legacy docker-compose found; Compose V2 (docker compose) is preferred."
        docker-compose version >/dev/null || die "docker-compose is present but not working."
    else
        die "Docker Compose not found. Need 'docker compose' (V2) or docker-compose."
    fi
    wait_for_docker_daemon
    docker info >/dev/null || die "docker info failed after daemon start."
}

install_docker_via_get_docker() {
    local tmp
    tmp="$(mktemp)"
    info "Installing Docker Engine via get.docker.com..."
    if ! curl_download "https://get.docker.com" "$tmp"; then
        rm -f "$tmp"
        explain_network_failure "download get.docker.com"
        exit 1
    fi
    if ! sh "$tmp"; then
        rm -f "$tmp"
        die "get.docker.com installer failed on ${OS_PRETTY_NAME}."
    fi
    rm -f "$tmp"
}

try_install_packages_soft() {
    local -a pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    case "$PKG_MANAGER" in
        apt-get)
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y --no-install-recommends "${pkgs[@]}" 2>/dev/null
            ;;
        dnf)
            dnf install -y "${pkgs[@]}" 2>/dev/null
            ;;
        yum)
            yum install -y "${pkgs[@]}" 2>/dev/null
            ;;
        pacman)
            pacman -Sy --noconfirm --needed "${pkgs[@]}" 2>/dev/null
            ;;
        zypper)
            zypper --non-interactive install -y "${pkgs[@]}" 2>/dev/null
            ;;
        apk)
            apk add --no-cache "${pkgs[@]}" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

install_docker_compose_plugin_fallback() {
    if docker compose version &>/dev/null; then
        return 0
    fi

    info "Installing Docker Compose plugin (fallback)..."
    case "$PKG_MANAGER" in
        apt-get)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y >/dev/null 2>&1 || true
            try_install_packages_soft docker-compose-plugin \
                || try_install_packages_soft docker-compose \
                || true
            ;;
        dnf|yum|zypper)
            try_install_packages_soft docker-compose-plugin \
                || try_install_packages_soft docker-compose \
                || true
            ;;
        pacman)
            try_install_packages_soft docker-compose || true
            ;;
        apk)
            try_install_packages_soft docker-cli-compose \
                || try_install_packages_soft docker-compose \
                || true
            ;;
    esac
}

install_docker() {
    if docker_engine_ready && docker_compose_available && docker info &>/dev/null; then
        ok "Docker and Docker Compose are already installed."
        verify_docker_stack
        return 0
    fi

    info "Installing Docker Engine and Compose for ${OS_PRETTY_NAME}..."

    case "$PKG_MANAGER" in
        apt-get|dnf|yum|zypper)
            # Official convenience script installs Docker CE + compose plugin on these families.
            install_docker_via_get_docker
            ;;
        pacman)
            run_pkg_install docker docker-compose
            ;;
        apk)
            run_pkg_install docker docker-cli-compose
            ;;
        *)
            die "Automatic Docker install is not supported with ${PKG_MANAGER} on ${OS_PRETTY_NAME}."
            ;;
    esac

    start_docker_daemon
    install_docker_compose_plugin_fallback
    verify_docker_stack
    ok "Docker installed."
}

# ── Preflight checks ───────────────────────────────────────────────────────────
check_disk_space() {
    local target avail_kb avail_mb
    target="$CONFIG_DIR"
    [[ -d "$target" ]] || target="$(dirname "$CONFIG_DIR")"
    [[ -d "$target" ]] || target="/"

    avail_kb="$(df -Pk "$target" 2>/dev/null | awk 'NR==2 {print $4}')"
    avail_kb="${avail_kb:-0}"
    avail_mb=$((avail_kb / 1024))

    if (( avail_mb < MIN_DISK_MB )); then
        die "Insufficient disk space on ${target}: ${avail_mb}MB free, need at least ${MIN_DISK_MB}MB."
    fi
    ok "Disk space OK (${avail_mb}MB free)."
}

port_in_use() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -ltn 2>/dev/null | grep -qE ":${port}\\s" && return 0
        return 1
    fi
    if command -v netstat &>/dev/null; then
        netstat -ltn 2>/dev/null | grep -qE ":${port}\\s" && return 0
        return 1
    fi
    return 1
}

check_required_ports() {
    local port
    local -a ports=(6160 6161 6162 6163)
    local busy=0

    for port in "${ports[@]}"; do
        if port_in_use "$port"; then
            # Allow reinstall when our own containers already own the ports.
            if docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -qE "pasarguardbot.*:${port}->|:.*:${port}->"; then
                continue
            fi
            warn "Port ${port} appears to be in use."
            busy=1
        fi
    done

    if (( busy )); then
        warn "Required ports may be occupied (6160 FastAPI, 6161 Redis, 6162 MariaDB, 6163 phpMyAdmin)."
        read -r -p "Continue anyway? (y/N): " confirm || true
        [[ "${confirm,,}" == "y" ]] || die "Aborted due to occupied ports."
    fi
}

ensure_config_dirs() {
    mkdir -p "$CONFIG_DIR"/{logs,sessions,data/mariadb,data/redis}
    chmod 700 "$CONFIG_DIR"
}

# ── Version / status (no network in menu) ──────────────────────────────────────
get_installed_bot_version() {
    local version revision digest short_id

    if ! command -v docker &>/dev/null; then
        printf '%s' '—'
        return 0
    fi

    if ! docker image inspect "${BOT_IMAGE}:${BOT_IMAGE_TAG}" &>/dev/null; then
        printf '%s' '—'
        return 0
    fi

    version="$(docker image inspect "${BOT_IMAGE}:${BOT_IMAGE_TAG}" \
        --format '{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null || true)"
    if [[ -n "$version" && "$version" != "<no value>" && "$version" != "null" ]]; then
        format_version "$version"
        return 0
    fi

    revision="$(docker image inspect "${BOT_IMAGE}:${BOT_IMAGE_TAG}" \
        --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null || true)"
    if [[ -n "$revision" && "$revision" != "<no value>" && "$revision" != "null" ]]; then
        printf 'sha-%s' "${revision:0:7}"
        return 0
    fi

    digest="$(docker image inspect "${BOT_IMAGE}:${BOT_IMAGE_TAG}" \
        --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' 2>/dev/null || true)"
    if [[ -n "$digest" && "$digest" == *"@"* ]]; then
        printf '%s' "${digest##*@}"
        return 0
    fi

    short_id="$(docker image inspect "${BOT_IMAGE}:${BOT_IMAGE_TAG}" \
        --format '{{.Id}}' 2>/dev/null | sed 's/^sha256://' | cut -c1-12 || true)"
    if [[ -n "$short_id" ]]; then
        printf '%s' "$short_id"
        return 0
    fi

    printf '%s' '—'
}

detect_server_ip() {
    local ip=""
    ip="$(curl_get --max-time 5 https://api.ipify.org 2>/dev/null || true)"
    if [[ -z "$ip" ]]; then
        ip="$(curl_get --max-time 5 https://ifconfig.me 2>/dev/null || true)"
    fi
    if [[ -z "$ip" ]]; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    [[ -n "$ip" ]] || ip="YOUR_SERVER_IP"
    printf '%s' "$ip"
}

show_service_urls() {
    [[ -f "$ENV_FILE" ]] || return 0

    local ip fastapi_port webhook_secret webhook_url pma_url
    ip="$(detect_server_ip)"
    fastapi_port="$(get_env_value "FASTAPI_PORT")"
    fastapi_port="${fastapi_port:-6160}"
    webhook_secret="$(get_env_value "WEBHOOK_SECRET")"
    webhook_url="http://${ip}:${fastapi_port}/api/webhook"
    pma_url="http://${ip}:${PHPMYADMIN_PORT}"

    echo
    info "Webhook (set in Pasarguard panel):"
    echo -e "  ${C_DIM}URL:${C_RESET}     ${webhook_url}"
    if [[ -n "$webhook_secret" ]]; then
        echo -e "  ${C_DIM}Header:${C_RESET}  x-webhook-secret: ${webhook_secret}"
    else
        warn "WEBHOOK_SECRET not found in ${ENV_FILE}"
    fi
    echo
    info "phpMyAdmin:"
    echo -e "  ${C_DIM}URL:${C_RESET}  ${pma_url}"
    echo
    warn "Replace the IP with your domain if you use one."
}

get_container_state() {
    local name="$1"
    docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || printf '%s' 'missing'
}

get_bot_runtime_summary() {
    local running total bot_state
    if ! command -v docker &>/dev/null || ! is_installed; then
        printf '%s' '—'
        return 0
    fi
    if ! docker info &>/dev/null; then
        printf '%s' 'docker unavailable'
        return 0
    fi
    running="$(docker_compose ps --status running -q 2>/dev/null | wc -l | tr -d ' ' || true)"
    total="$(docker_compose ps -a -q 2>/dev/null | wc -l | tr -d ' ' || true)"
    running="${running:-0}"
    total="${total:-0}"
    bot_state="$(get_container_state pasarguardbot)"
    printf '%s (%s/%s services running)' "$bot_state" "$running" "$total"
}

show_install_info() {
    local installed_ver bot_runtime fastapi_port

    echo -e "  ${C_DIM}Manager script:${C_RESET}  $(format_version "$SCRIPT_VERSION")"
    echo -e "  ${C_DIM}Host OS:${C_RESET}         ${OS_PRETTY_NAME:-unknown}"

    if is_installed; then
        installed_ver="$(get_installed_bot_version)" || installed_ver="—"
        bot_runtime="$(get_bot_runtime_summary)" || bot_runtime="—"
        fastapi_port="$(get_env_value "FASTAPI_PORT")"
        fastapi_port="${fastapi_port:-6160}"

        echo -e "  ${C_DIM}Bot image:${C_RESET}       ${installed_ver}"
        echo -e "  ${C_DIM}Bot container:${C_RESET}  ${bot_runtime}"
        echo -e "  ${C_DIM}API port:${C_RESET}        ${fastapi_port}"
        echo -e "  ${C_DIM}Config:${C_RESET}          ${CONFIG_DIR}"
    fi
    echo
}

draw_banner() {
    safe_clear
    echo -e "${C_CYAN}${C_BOLD}PasarguardBot${C_RESET} ${C_DIM}— Docker manager $(format_version "$SCRIPT_VERSION")${C_RESET}"
    echo
    show_install_info || true
}

draw_menu() {
    draw_banner
    if is_installed; then
        echo -e "  ${C_GREEN}●${C_RESET} Status: ${C_GREEN}Installed${C_RESET}"
    else
        echo -e "  ${C_RED}●${C_RESET} Status: ${C_RED}Not installed${C_RESET}"
    fi
    echo
    echo -e "${C_BOLD}  ┌─────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}  │${C_RESET}  1) Install bot                           ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}  │${C_RESET}  2) Uninstall bot                         ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}  │${C_RESET}  3) Update bot                            ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}  │${C_RESET}  4) View logs                             ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}  │${C_RESET}  5) Edit .env file                        ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}  │${C_RESET}  6) Full restart                          ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}  │${C_RESET}  7) Service status                        ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}  │${C_RESET}  8) Show webhook & URLs                   ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}  │${C_RESET}  9) Update manager script                 ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}  │${C_RESET}  0) Exit                                   ${C_BOLD}│${C_RESET}"
    echo -e "${C_BOLD}  └─────────────────────────────────────────┘${C_RESET}"
    echo
}

# ── Env generation ────────────────────────────────────────────────────────────
prompt_required() {
    local _var_name="$1"
    local prompt_text="$2"
    local value=""
    while [[ -z "$value" ]]; do
        read -r -p "$prompt_text: " value || true
        value="${value// /}"
        [[ -n "$value" ]] || warn "This value is required."
    done
    printf '%s' "$value"
}

prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local value=""
    read -r -p "${prompt_text} [${default_value}]: " value || true
    value="${value// /}"
    if [[ -z "$value" ]]; then
        value="$default_value"
    fi
    printf '%s' "$value"
}

append_mariadb_vars() {
    local db_pass="$1"
    local db_root_pass="$2"

    set_env_var "$ENV_FILE" "MARIADB_ROOT_PASSWORD" "$db_root_pass"
    set_env_var "$ENV_FILE" "MARIADB_DATABASE" "pasarguardbot"
    set_env_var "$ENV_FILE" "MARIADB_USER" "pasarguardbot"
    set_env_var "$ENV_FILE" "MARIADB_PASSWORD" "$db_pass"
}

append_deploy_paths() {
    set_env_var "$ENV_FILE" "PASARGUARDBOT_CONFIG_DIR" "$CONFIG_DIR"
}

generate_env_file() {
    local api_id api_hash bot_token admin_id
    local db_pass db_root_pass webhook_secret crypto_key
    local tmp

    if [[ -f "$ENV_FILE" ]]; then
        warn ".env already exists — keeping the existing file."
        chmod 600 "$ENV_FILE" 2>/dev/null || true
        return 0
    fi

    ensure_config_dirs

    tmp="$(mktemp)"
    info "Downloading .env.example from GitHub..."
    if ! curl_download "$ENV_EXAMPLE_RAW_URL" "$tmp"; then
        rm -f "$tmp"
        explain_network_failure "download .env.example"
        exit 1
    fi
    if [[ ! -s "$tmp" ]] || ! grep -q '^API_ID=' "$tmp"; then
        rm -f "$tmp"
        die "Downloaded .env.example is empty or invalid."
    fi

    echo
    info "Enter your Telegram credentials:"
    api_id=$(prompt_with_default "  API_ID (from my.telegram.org)" "2040")
    api_hash=$(prompt_with_default "  API_HASH" "b18441a1ff607e10a989891a5462e627")
    bot_token=$(prompt_required "BOT_TOKEN" "  BOT_TOKEN (from @BotFather)")
    admin_id=$(prompt_required "ADMIN_ID" "  ADMIN_ID (numeric Telegram user ID)")

    db_pass="$(rand_b64 24)"
    db_root_pass="$(rand_b64 32)"
    webhook_secret="$(rand_hex 16)"
    crypto_key="$(rand_b64 32)"

    cp "$tmp" "$ENV_FILE"
    rm -f "$tmp"
    chmod 600 "$ENV_FILE"

    set_env_var "$ENV_FILE" "API_ID" "$api_id"
    set_env_var "$ENV_FILE" "API_HASH" "$api_hash"
    set_env_var "$ENV_FILE" "BOT_TOKEN" "$bot_token"
    set_env_var "$ENV_FILE" "ADMIN_ID" "$admin_id"
    set_env_var "$ENV_FILE" "SQLALCHEMY_DATABASE_URL" "mysql+asyncmy://pasarguardbot:${db_pass}@mariadb:3306/pasarguardbot"
    set_env_var "$ENV_FILE" "FASTAPI_PORT" "6160"
    set_env_var "$ENV_FILE" "WEBHOOK_SECRET" "$webhook_secret"
    set_env_var "$ENV_FILE" "CRYPTO_KEY" "$crypto_key"
    set_env_var "$ENV_FILE" "REDIS_URL" "redis://redis:6379/0"
    set_env_var "$ENV_FILE" "REDIS_NAMESPACE_PREFIX" "pasarguardbot:mainbot"
    set_env_var "$ENV_FILE" "TELETHON_SESSION_PATH" "sessions/KenzoSession"
    set_env_var "$ENV_FILE" "LOG_DIR" "./logs"
    set_env_var "$ENV_FILE" "LOG_TO_FILE" "true"
    set_env_var "$ENV_FILE" "LOG_LEVEL" "INFO"
    append_mariadb_vars "$db_pass" "$db_root_pass"
    append_deploy_paths

    chmod 600 "$ENV_FILE"

    ok ".env created at ${ENV_FILE}"
    echo
    info "Database credentials (saved in .env):"
    echo -e "  ${C_DIM}Database:${C_RESET} pasarguardbot"
    echo -e "  ${C_DIM}User:${C_RESET}     pasarguardbot"
    echo -e "  ${C_DIM}Password:${C_RESET} ${db_pass}"
    echo -e "  ${C_DIM}Root:${C_RESET}     ${db_root_pass}"
}

# ── Compose download & validation ──────────────────────────────────────────────
validate_compose_file() {
    local file="$1"

    [[ -s "$file" ]] || {
        err "Compose file is empty."
        return 1
    }
    grep -q 'ghcr.io/amirkenzo/pasarguardbot:latest' "$file" || {
        err "Compose file missing required image ghcr.io/amirkenzo/pasarguardbot:latest"
        return 1
    }
    if grep -E '^\s+build:' "$file" >/dev/null 2>&1; then
        err "Production Compose must not contain build: for services."
        return 1
    fi
    return 0
}

setup_compose() {
    local tmp

    ensure_config_dirs
    tmp="$(mktemp)"

    info "Downloading production docker-compose.yml from GitHub..."
    if ! curl_download "$COMPOSE_RAW_URL" "$tmp"; then
        rm -f "$tmp"
        explain_network_failure "download docker-compose.yml"
        exit 1
    fi

    if ! validate_compose_file "$tmp"; then
        rm -f "$tmp"
        die "Downloaded docker-compose.yml failed validation."
    fi

    # Validate with docker compose config when .env exists (or create a stub for config check).
    if [[ -f "$ENV_FILE" ]]; then
        if ! docker compose --project-directory "$CONFIG_DIR" -f "$tmp" --env-file "$ENV_FILE" config >/dev/null; then
            rm -f "$tmp"
            die "docker compose config failed for downloaded Compose file (invalid YAML or references)."
        fi
    fi

    cp "$tmp" "$COMPOSE_FILE"
    rm -f "$tmp"
    ok "docker-compose.yml updated at ${COMPOSE_FILE}"
}

pull_images() {
    info "Pulling Docker images..."
    if ! docker_compose pull; then
        err "Failed to pull one or more images."
        err "If the bot image fails: check GHCR availability and that your CPU architecture is supported (amd64/arm64)."
        die "docker compose pull failed."
    fi
    ok "Images pulled."
}

wait_for_containers_healthy() {
    local i=0
    local max=90
    local bot_state

    info "Waiting for containers..."
    while (( i < max )); do
        bot_state="$(get_container_state pasarguardbot)"
        if [[ "$bot_state" == "running" ]]; then
            ok "Bot container is running."
            return 0
        fi
        sleep 2
        i=$((i + 2))
    done

    warn "Timed out waiting for bot container. Current status:"
    docker_compose ps || true
    return 1
}

cleanup_stale_named_containers() {
    # Only remove known PasarguardBot container names (not unrelated resources).
    docker rm -f pasarguardbot-redis pasarguardbot-mariadb pasarguardbot-phpmyadmin pasarguardbot 2>/dev/null || true
}

prune_dangling_images_safe() {
    # Only dangling images; never prune volumes or running containers.
    docker image prune -f >/dev/null 2>&1 || true
}

install_manager_from_file() {
    local src="$1"
    head -1 "$src" | grep -q '#!/usr/bin/env bash' || {
        die "Manager script is invalid (missing bash shebang)."
    }
    mkdir -p "$CONFIG_DIR"
    cp "$src" "$MANAGER_SCRIPT"
    chmod +x "$MANAGER_SCRIPT"
    ln -sf "$MANAGER_SCRIPT" "$MANAGER_BIN"
    hash -r 2>/dev/null || true
}

manager_command_ready() {
    [[ -x "$MANAGER_SCRIPT" && -e "$MANAGER_BIN" ]]
}

install_manager_command() {
    local tmp
    tmp="$(mktemp)"

    info "Installing manager script from GitHub..."
    if ! curl_download "$SCRIPT_RAW_URL" "$tmp"; then
        rm -f "$tmp"
        # Fallback: if we are already running a local copy, install that.
        if [[ -f "${BASH_SOURCE[0]:-}" && -s "${BASH_SOURCE[0]}" ]]; then
            warn "Could not download manager script; installing the running copy."
            cp "${BASH_SOURCE[0]}" "$tmp"
        else
            explain_network_failure "download manager script"
            exit 1
        fi
    fi

    install_manager_from_file "$tmp"
    rm -f "$tmp"
    ok "pasarguardbot command installed at ${MANAGER_BIN}"
}

# Register /usr/local/bin/pasarguardbot when missing (e.g. first curl | bash run).
ensure_manager_command() {
    if manager_command_ready; then
        return 0
    fi

    local src="${BASH_SOURCE[0]:-}"
    if [[ -n "$src" && -r "$src" && -s "$src" ]]; then
        info "Registering pasarguardbot command..."
        install_manager_from_file "$src"
        ok "pasarguardbot command installed at ${MANAGER_BIN}"
        return 0
    fi

    install_manager_command
}

# ── Actions ───────────────────────────────────────────────────────────────────
action_install() {
    draw_banner
    info "Starting PasarguardBot installation..."
    echo

    if is_installed; then
        warn "Bot appears already installed (${CONFIG_DIR})."
        read -r -p "Continue (will keep existing .env and data)? (y/N): " confirm || true
        [[ "${confirm,,}" == "y" ]] || return 0
    fi

    check_disk_space
    install_docker
    check_required_ports
    ensure_config_dirs
    generate_env_file
    setup_compose
    install_manager_command
    cleanup_stale_named_containers

    pull_images

    info "Starting services..."
    if ! docker_compose up -d; then
        die "docker compose up failed. Check logs with: docker compose -f ${COMPOSE_FILE} logs"
    fi

    wait_for_containers_healthy || true

    echo
    ok "Installation completed successfully!"
    echo
    info "Paths:"
    echo -e "  ${C_DIM}Config:${C_RESET}  ${CONFIG_DIR}"
    echo -e "  ${C_DIM}.env:${C_RESET}    ${ENV_FILE}"
    echo -e "  ${C_DIM}Logs:${C_RESET}    ${CONFIG_DIR}/logs"
    echo -e "  ${C_DIM}Data:${C_RESET}    ${CONFIG_DIR}/data"
    echo
    info "Image:"
    echo -e "  ${C_DIM}Bot:${C_RESET}  ${BOT_IMAGE}:${BOT_IMAGE_TAG} ($(get_installed_bot_version))"
    echo
    info "Ports:"
    echo -e "  ${C_DIM}FastAPI:${C_RESET}      6160 (public)"
    echo -e "  ${C_DIM}phpMyAdmin:${C_RESET}   6163 (public)"
    echo -e "  ${C_DIM}Redis:${C_RESET}        6161 (localhost only)"
    echo -e "  ${C_DIM}MariaDB:${C_RESET}      6162 (localhost only)"
    show_service_urls
    echo
    info "Commands:"
    echo -e "  ${C_DIM}Manage:${C_RESET}   pasarguardbot"
    echo -e "  ${C_DIM}Status:${C_RESET}   pasarguardbot → option 7"
    pause
}

action_uninstall() {
    draw_banner
    if ! is_installed && [[ ! -d "$CONFIG_DIR" ]]; then
        warn "Bot is not installed."
        pause
        return 0
    fi

    echo -e "${C_RED}${C_BOLD}  ⚠  Uninstall PasarguardBot${C_RESET}"
    echo
    echo "  1) Remove containers only (keep .env and data)"
    echo "  2) Remove containers + data (keep .env / config if present)"
    echo "  3) Full remove (${CONFIG_DIR} and ${MANAGER_BIN})"
    echo "  0) Cancel"
    echo
    read -r -p "Choice: " choice || true

    case "$choice" in
        1)
            info "Stopping and removing containers..."
            if [[ -f "$COMPOSE_FILE" && -f "$ENV_FILE" ]]; then
                docker_compose down --remove-orphans 2>/dev/null || true
            else
                cleanup_stale_named_containers
            fi
            ok "Containers removed. .env and data were kept."
            ;;
        2)
            read -r -p "Delete database/redis data under ${CONFIG_DIR}/data? Type 'yes' to confirm: " confirm || true
            [[ "$confirm" == "yes" ]] || {
                info "Cancelled."
                pause
                return 0
            }
            if [[ -f "$COMPOSE_FILE" && -f "$ENV_FILE" ]]; then
                docker_compose down --remove-orphans 2>/dev/null || true
            else
                cleanup_stale_named_containers
            fi
            rm -rf "${CONFIG_DIR}/data"
            ok "Containers and data removed. Config/.env kept if present."
            ;;
        3)
            read -r -p "Everything under ${CONFIG_DIR} will be deleted! Type 'yes' to confirm: " confirm || true
            [[ "$confirm" == "yes" ]] || {
                info "Cancelled."
                pause
                return 0
            }
            if [[ -f "$COMPOSE_FILE" && -f "$ENV_FILE" ]]; then
                docker_compose down --remove-orphans 2>/dev/null || true
            else
                cleanup_stale_named_containers
            fi
            while IFS= read -r img_id; do
                [[ -n "$img_id" ]] && docker rmi "$img_id" 2>/dev/null || true
            done < <(docker images "${BOT_IMAGE}" -q 2>/dev/null || true)
            rm -rf "$CONFIG_DIR"
            rm -f "$MANAGER_BIN"
            ok "All PasarguardBot files removed."
            ;;
        *)
            info "Cancelled."
            ;;
    esac
    pause
}

action_update() {
    local old_ver new_ver

    draw_banner
    is_installed || die "Install the bot first (option 1)."
    command -v docker &>/dev/null || die "Docker is not installed."
    docker info &>/dev/null || die "Docker daemon is not running."

    old_ver="$(get_installed_bot_version)"

    info "Updating production Compose and pulling latest images..."
    setup_compose
    pull_images

    info "Recreating containers..."
    if ! docker_compose up -d --force-recreate --remove-orphans; then
        die "Update failed during docker compose up."
    fi

    wait_for_containers_healthy || true
    prune_dangling_images_safe

    new_ver="$(get_installed_bot_version)"
    ok "Update complete (${old_ver} → ${new_ver})."
    pause
}

action_update_script() {
    draw_banner

    local tmp new_ver old_ver
    tmp="$(mktemp)"

    info "Downloading latest manager script from GitHub..."
    if ! curl_download "$SCRIPT_RAW_URL" "$tmp"; then
        rm -f "$tmp"
        explain_network_failure "download manager script"
        pause
        return 1
    fi

    head -1 "$tmp" | grep -q '#!/usr/bin/env bash' || {
        rm -f "$tmp"
        die "Downloaded file does not look like a valid script."
    }

    new_ver="$(grep -m1 '^readonly SCRIPT_VERSION=' "$tmp" | sed -E 's/^readonly SCRIPT_VERSION="(.*)"/\1/')"
    old_ver="$SCRIPT_VERSION"

    if [[ -z "$new_ver" ]]; then
        rm -f "$tmp"
        die "Could not read SCRIPT_VERSION from downloaded script."
    fi

    # Always install (even when versions match) so /usr/local/bin/pasarguardbot exists.
    install_manager_from_file "$tmp"
    rm -f "$tmp"

    if [[ "$new_ver" == "$old_ver" ]]; then
        ok "Manager script is already up to date ($(format_version "$old_ver"))."
        ok "pasarguardbot command ensured at ${MANAGER_BIN}"
        pause
        return 0
    fi

    ok "Manager script updated: $(format_version "$old_ver") → $(format_version "$new_ver")"
    warn "Run pasarguardbot again to use the new script."
    pause
}

action_logs() {
    draw_banner
    is_installed || die "Install the bot first (option 1)."

    echo "  1) Bot logs"
    echo "  2) MariaDB logs"
    echo "  3) Redis logs"
    echo "  4) All services"
    echo "  5) Live bot logs (Ctrl+C to exit)"
    echo "  0) Back"
    echo
    read -r -p "Choice: " choice || true

    case "$choice" in
        1) docker_compose logs --tail=200 bot ;;
        2) docker_compose logs --tail=200 mariadb ;;
        3) docker_compose logs --tail=200 redis ;;
        4) docker_compose logs --tail=100 ;;
        5)
            info "Live logs — press Ctrl+C to exit"
            docker_compose logs -f bot
            ;;
        0) return 0 ;;
        *) warn "Invalid choice." ;;
    esac
    pause
}

action_edit_env() {
    draw_banner
    is_installed || die "Install the bot first (option 1)."

    local editor="${EDITOR:-nano}"
    command -v "$editor" &>/dev/null || editor="nano"

    info "Editing ${ENV_FILE} with ${editor}"
    echo
    "$editor" "$ENV_FILE"

    echo
    read -r -p "Restart the bot? (Y/n): " restart || true
    if [[ "${restart,,}" != "n" ]]; then
        action_restart_quiet
    fi
    pause
}

action_restart_quiet() {
    docker_compose pull bot || true
    docker_compose down
    docker_compose up -d
    ok "Full restart completed."
}

action_restart() {
    draw_banner
    is_installed || die "Install the bot first (option 1)."

    info "Performing a full restart of all services..."
    action_restart_quiet
    pause
}

action_status() {
    draw_banner
    is_installed || die "Install the bot first (option 1)."

    info "Container status:"
    echo
    docker_compose ps
    echo
    info "Resource usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
        pasarguardbot pasarguardbot-mariadb pasarguardbot-redis pasarguardbot-phpmyadmin 2>/dev/null \
        || true
    show_service_urls
    pause
}

action_urls() {
    draw_banner
    is_installed || die "Install the bot first (option 1)."
    show_service_urls
    pause
}

# ── Main ──────────────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        draw_menu
        read -r -p "  Select an option: " choice || exit 0
        case "$choice" in
            1) action_install ;;
            2) action_uninstall ;;
            3) action_update ;;
            4) action_logs ;;
            5) action_edit_env ;;
            6) action_restart ;;
            7) action_status ;;
            8) action_urls ;;
            9) action_update_script ;;
            0|q|Q) draw_banner; ok "Goodbye!"; exit 0 ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

bootstrap "$@"

case "${1:-}" in
    install)        action_install ;;
    uninstall)      action_uninstall ;;
    update)         action_update ;;
    update-script)  action_update_script ;;
    logs)           action_logs ;;
    restart)        action_restart ;;
    status)         action_status ;;
    urls)           action_urls ;;
    ""|menu)        main_menu ;;
    *)
        echo "Usage: pasarguardbot [install|uninstall|update|update-script|logs|restart|status|urls|menu]"
        exit 1
        ;;
esac
