#!/usr/bin/env bash
# PasarguardBot — Docker install & management script
# https://github.com/AmirKenzo/PasarguardBot

set -euo pipefail

# ── Paths & repo ──────────────────────────────────────────────────────────────
readonly SCRIPT_VERSION="1.0.1"
readonly REPO_URL="https://github.com/AmirKenzo/PasarguardBot.git"
readonly CONFIG_DIR="/opt/pasarguardbot"
readonly SOURCE_DIR="/var/lib/pasarguardbot"
readonly COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
readonly ENV_FILE="${CONFIG_DIR}/.env"
readonly MANAGER_BIN="/usr/local/bin/pasarguardbot"
readonly MANAGER_SCRIPT="${CONFIG_DIR}/pasarguardbot.sh"
readonly SCRIPT_RAW_URL="https://raw.githubusercontent.com/AmirKenzo/PasarguardBot/main/scripts/pasarguardbot.sh"
readonly PHPMYADMIN_PORT=6163

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
    read -r -p "Press Enter to continue..." _
}

rand_hex()  { openssl rand -hex "${1:-16}"; }
rand_b64()  { openssl rand -base64 "${1:-24}" | tr -d '/+=' | head -c "${1:-24}"; }

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "This script must be run as root: sudo $0"
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
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
    elif command -v docker-compose &>/dev/null; then
        docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
    else
        die "Docker Compose not found."
    fi
}

is_installed() {
    [[ -f "$COMPOSE_FILE" && -f "$ENV_FILE" && -d "$SOURCE_DIR/.git" ]]
}

get_env_value() {
    local key="$1"
    local file="${2:-$ENV_FILE}"
    grep -E "^${key}=" "$file" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

detect_server_ip() {
    local ip=""
    ip="$(curl -4 -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
    if [[ -z "$ip" ]]; then
        ip="$(curl -4 -fsS --max-time 3 https://ifconfig.me 2>/dev/null || true)"
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

get_installed_bot_version() {
    local version tag
    if [[ -d "$SOURCE_DIR/.git" ]]; then
        tag="$(get_current_tag 2>/dev/null || true)"
        if [[ -n "$tag" ]]; then
            printf 'v%s' "$tag"
            return 0
        fi
    fi
    if [[ -f "${SOURCE_DIR}/pyproject.toml" ]]; then
        version="$(
            grep -E '^version = ' "${SOURCE_DIR}/pyproject.toml" 2>/dev/null \
                | head -1 \
                | sed -E 's/^version = "(.*)"/\1/'
        )"
        if [[ -n "$version" ]]; then
            printf 'v%s' "$version"
            return 0
        fi
    fi
    printf '%s' '—'
}

get_remote_script_version() {
    curl -fsSL --max-time 10 "$SCRIPT_RAW_URL" 2>/dev/null \
        | grep -m1 '^readonly SCRIPT_VERSION=' \
        | sed -E 's/^readonly SCRIPT_VERSION="(.*)"/\1/' \
        || true
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
    running="$(docker_compose ps --status running -q 2>/dev/null | wc -l | tr -d ' ')"
    total="$(docker_compose ps -a -q 2>/dev/null | wc -l | tr -d ' ')"
    bot_state="$(get_container_state pasarguardbot)"
    printf '%s (%s/%s services running)' "$bot_state" "$running" "$total"
}

show_install_info() {
    local installed_ver latest_tag remote_script_ver bot_runtime fastapi_port

    echo -e "  ${C_DIM}Manager script:${C_RESET}  v${SCRIPT_VERSION}"

    remote_script_ver="$(get_remote_script_version)"
    if [[ -n "$remote_script_ver" && "$remote_script_ver" != "$SCRIPT_VERSION" ]]; then
        echo -e "  ${C_DIM}Script latest:${C_RESET}   v${remote_script_ver} ${C_YELLOW}(update available)${C_RESET}"
    fi

    if is_installed; then
        installed_ver="$(get_installed_bot_version)"
        latest_tag="$(resolve_latest_tag 2>/dev/null || true)"
        bot_runtime="$(get_bot_runtime_summary)"
        fastapi_port="$(get_env_value "FASTAPI_PORT")"
        fastapi_port="${fastapi_port:-6160}"

        echo -e "  ${C_DIM}Bot release:${C_RESET}    ${installed_ver}"
        if [[ -n "$latest_tag" && "v${latest_tag}" != "$installed_ver" ]]; then
            echo -e "  ${C_DIM}Latest release:${C_RESET}  v${latest_tag} ${C_YELLOW}(update available)${C_RESET}"
        elif [[ -n "$latest_tag" ]]; then
            echo -e "  ${C_DIM}Latest release:${C_RESET}  v${latest_tag}"
        fi
        echo -e "  ${C_DIM}Bot container:${C_RESET}  ${bot_runtime}"
        echo -e "  ${C_DIM}API port:${C_RESET}        ${fastapi_port}"
        echo -e "  ${C_DIM}Config:${C_RESET}          ${CONFIG_DIR}"
        echo -e "  ${C_DIM}Source:${C_RESET}          ${SOURCE_DIR}"
    else
        latest_tag="$(resolve_latest_tag 2>/dev/null || true)"
        [[ -n "$latest_tag" ]] && echo -e "  ${C_DIM}Latest release:${C_RESET}  v${latest_tag}"
    fi
    echo
}

draw_banner() {
    clear
    echo -e "${C_CYAN}${C_BOLD}PasarguardBot${C_RESET} ${C_DIM}— Docker manager v${SCRIPT_VERSION}${C_RESET}"
    echo
    show_install_info
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
    echo -e "${C_BOLD}  │${C_RESET}  3) Update bot (release tag)              ${C_BOLD}│${C_RESET}"
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

# ── Prerequisites ─────────────────────────────────────────────────────────────
install_docker() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
        ok "Docker and Docker Compose are already installed."
        return 0
    fi

    info "Installing Docker..."
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
    else
        die "Unsupported operating system."
    fi

    case "${ID:-}" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq ca-certificates curl git openssl nano
            curl -fsSL https://get.docker.com | sh
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if command -v dnf &>/dev/null; then
                dnf install -y docker docker-compose-plugin git openssl nano curl
            else
                yum install -y docker docker-compose-plugin git openssl nano curl
            fi
            systemctl enable --now docker
            ;;
        *)
            die "Automatic Docker install is not supported on this OS. Install Docker manually and retry."
            ;;
    esac

    systemctl enable --now docker 2>/dev/null || true
    ok "Docker installed."
}

install_prerequisites() {
    info "Checking prerequisites..."
    install_docker

    for cmd in git openssl; do
        command -v "$cmd" &>/dev/null || {
            apt-get install -y -qq "$cmd" 2>/dev/null || yum install -y "$cmd" 2>/dev/null || true
        }
    done

    command -v git &>/dev/null || die "git not found."
    command -v openssl &>/dev/null || die "openssl not found."
    ok "Prerequisites ready."
}

# ── Env generation ────────────────────────────────────────────────────────────
prompt_required() {
    local var_name="$1"
    local prompt_text="$2"
    local value=""
    while [[ -z "$value" ]]; do
        read -r -p "$prompt_text: " value
        value="${value// /}"
        [[ -n "$value" ]] || warn "This value is required."
    done
    printf '%s' "$value"
}

prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local value=""
    read -r -p "${prompt_text} [${default_value}]: " value
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
    set_env_var "$ENV_FILE" "PASARGUARDBOT_SOURCE_DIR" "$SOURCE_DIR"
}

generate_env_file() {
    local api_id api_hash bot_token admin_id
    local db_pass db_root_pass webhook_secret crypto_key
    local example="${SOURCE_DIR}/.env.example"

    [[ -f "$example" ]] || die ".env.example not found in ${SOURCE_DIR}"

    if [[ -f "$ENV_FILE" ]]; then
        warn ".env already exists — keeping the existing file."
        return 0
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

    mkdir -p "$CONFIG_DIR"/{logs,sessions,data/mariadb,data/redis}
    chmod 700 "$CONFIG_DIR"

    cp "$example" "$ENV_FILE"

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

    ok ".env created at ${ENV_FILE} (from .env.example)"
    echo
    info "Database credentials (appended to .env):"
    echo -e "  ${C_DIM}Database:${C_RESET} pasarguardbot"
    echo -e "  ${C_DIM}User:${C_RESET}     pasarguardbot"
    echo -e "  ${C_DIM}Password:${C_RESET} ${db_pass}"
    echo -e "  ${C_DIM}Root:${C_RESET}     ${db_root_pass}"
}

# ── Clone & compose ───────────────────────────────────────────────────────────
resolve_latest_tag() {
    local tag
    tag="$(
        git ls-remote --tags --refs "$REPO_URL" 2>/dev/null \
            | sed 's/.*refs\/tags\///' \
            | grep -v '\^{}$' \
            | sort -V \
            | tail -1
    )"
    [[ -n "$tag" ]] || die "No release tags found on ${REPO_URL}. Create a tag on GitHub first (e.g. 1.0.0)."
    printf '%s' "$tag"
}

get_current_tag() {
    git -C "$SOURCE_DIR" describe --tags --exact-match HEAD 2>/dev/null \
        || git -C "$SOURCE_DIR" tag --points-at HEAD 2>/dev/null | head -1 \
        || true
}

checkout_release_tag() {
    local latest="$1"
    local current

    current="$(get_current_tag)"
    if [[ "$current" == "$latest" ]]; then
        ok "Already on release v${latest}"
        return 0
    fi

    info "Checking out release v${latest}..."
    git -C "$SOURCE_DIR" fetch --tags --prune origin
    if git -C "$SOURCE_DIR" checkout --force "$latest" 2>/dev/null; then
        ok "Source at v${latest}"
        return 0
    fi

    warn "Could not switch to v${latest} — re-cloning..."
    rm -rf "$SOURCE_DIR"
    git clone --depth 1 --branch "$latest" "$REPO_URL" "$SOURCE_DIR"
    ok "Source cloned at v${latest}"
}

clone_source() {
    local latest
    latest="$(resolve_latest_tag)"

    if [[ -d "$SOURCE_DIR/.git" ]]; then
        info "Source already cloned — syncing to latest release tag..."
        checkout_release_tag "$latest"
    else
        info "Cloning release v${latest} from GitHub → ${SOURCE_DIR}"
        mkdir -p "$(dirname "$SOURCE_DIR")"
        git clone --depth 1 --branch "$latest" "$REPO_URL" "$SOURCE_DIR"
        ok "Source cloned at v${latest}"
    fi
    ok "Source ready: ${SOURCE_DIR} (v${latest})"
}

setup_compose() {
    local src_compose="${SOURCE_DIR}/docker-compose.yml"
    [[ -f "$src_compose" ]] || die "docker-compose.yml not found in ${SOURCE_DIR}"

    mkdir -p "$CONFIG_DIR"/{logs,sessions,data/mariadb,data/redis}
    cp "$src_compose" "$COMPOSE_FILE"

    ok "docker-compose.yml copied from source to ${COMPOSE_FILE}"
}

cleanup_stale_resources() {
    docker rm -f pasarguardbot-redis pasarguardbot-mariadb pasarguardbot-phpmyadmin pasarguardbot 2>/dev/null || true
    docker volume rm pasarguardbot_mariadb_data pasarguardbot_redis_data 2>/dev/null || true
    docker network rm pasarguardbot_default 2>/dev/null || true
}

install_manager_command() {
    local self source_copy self_real manager_real
    self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
    source_copy="${SOURCE_DIR}/scripts/pasarguardbot.sh"

    if [[ -z "$self" || ! -f "$self" ]]; then
        if [[ -f "$source_copy" ]]; then
            self="$source_copy"
        else
            die "Manager script source not found (checked: ${BASH_SOURCE[0]} and ${source_copy})."
        fi
    fi

    mkdir -p "$CONFIG_DIR"
    self_real="$(readlink -f "$self" 2>/dev/null || printf '%s' "$self")"
    manager_real="$(readlink -f "$MANAGER_SCRIPT" 2>/dev/null || printf '%s' "$MANAGER_SCRIPT")"

    if [[ "$self_real" != "$manager_real" ]]; then
        cp "$self" "$MANAGER_SCRIPT"
    fi

    chmod +x "$MANAGER_SCRIPT"
    ln -sf "$MANAGER_SCRIPT" "$MANAGER_BIN"
    ok "pasarguardbot command registered in PATH."
}

# ── Actions ───────────────────────────────────────────────────────────────────
action_install() {
    draw_banner
    info "Starting PasarguardBot installation..."
    echo

    if is_installed; then
        warn "Bot is already installed."
        read -r -p "Continue anyway? (y/N): " confirm
        [[ "${confirm,,}" == "y" ]] || return 0
    fi

    install_prerequisites
    clone_source
    generate_env_file
    setup_compose
    install_manager_command
    cleanup_stale_resources

    info "Building Docker image (this may take a few minutes)..."
    docker_compose build --pull bot

    info "Starting services..."
    docker_compose up -d

    echo
    ok "Installation completed successfully!"
    echo
    info "Paths:"
    echo -e "  ${C_DIM}Bot .env:${C_RESET}    ${ENV_FILE}"
    echo -e "  ${C_DIM}Source:${C_RESET}         ${SOURCE_DIR}"
    echo -e "  ${C_DIM}Logs:${C_RESET}           ${CONFIG_DIR}/logs"
    echo -e "  ${C_DIM}Data:${C_RESET}           ${CONFIG_DIR}/data"
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
    if ! is_installed; then
        warn "Bot is not installed."
        pause
        return 0
    fi

    echo -e "${C_RED}${C_BOLD}  ⚠  Uninstall PasarguardBot${C_RESET}"
    echo
    echo "  1) Remove containers only (database and redis data are kept)"
    echo "  2) Full remove + delete database and redis data"
    echo "  3) Full remove + delete all files (${CONFIG_DIR} and ${SOURCE_DIR})"
    echo "  0) Cancel"
    echo
    read -r -p "Choice: " choice

    case "$choice" in
        1)
            info "Stopping and removing containers..."
            docker_compose down --remove-orphans 2>/dev/null || true
            ok "Containers removed. Data and .env were kept."
            ;;
        2)
            read -r -p "Are you sure? Database and redis data will be deleted (y/N): " confirm
            [[ "${confirm,,}" == "y" ]] || return 0
            docker_compose down --remove-orphans 2>/dev/null || true
            rm -rf "${CONFIG_DIR}/data"
            docker rmi pasarguardbot:latest 2>/dev/null || true
            ok "Containers removed and data directory deleted."
            ;;
        3)
            read -r -p "Everything will be deleted! Type 'yes' to confirm: " confirm
            [[ "$confirm" == "yes" ]] || return 0
            docker_compose down --remove-orphans 2>/dev/null || true
            docker rmi pasarguardbot:latest 2>/dev/null || true
            rm -rf "$CONFIG_DIR" "$SOURCE_DIR"
            rm -f "$MANAGER_BIN"
            ok "All files removed."
            ;;
        *)
            info "Cancelled."
            ;;
    esac
    pause
}

action_update() {
    draw_banner
    is_installed || die "Install the bot first (option 1)."

    info "Checking for a newer release tag on GitHub..."
    local old_tag new_tag latest
    old_tag="$(get_current_tag)"
    old_tag="${old_tag:-unknown}"
    latest="$(resolve_latest_tag)"
    checkout_release_tag "$latest"
    new_tag="$(get_current_tag)"
    new_tag="${new_tag:-$latest}"

    setup_compose

    info "Rebuilding image..."
    docker_compose build --pull bot

    info "Restarting services..."
    docker_compose up -d --force-recreate

    ok "Update complete (v${old_tag} → v${new_tag})."
    pause
}

action_update_script() {
    draw_banner

    local tmp new_ver old_ver
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN

    info "Downloading latest manager script from GitHub..."
    curl -fsSL --max-time 30 "$SCRIPT_RAW_URL" -o "$tmp" || die "Failed to download manager script."

    head -1 "$tmp" | grep -q '#!/usr/bin/env bash' || die "Downloaded file does not look like a valid script."

    new_ver="$(grep -m1 '^readonly SCRIPT_VERSION=' "$tmp" | sed -E 's/^readonly SCRIPT_VERSION="(.*)"/\1/')"
    old_ver="$SCRIPT_VERSION"

    if [[ -z "$new_ver" ]]; then
        die "Could not read SCRIPT_VERSION from downloaded script."
    fi

    if [[ "$new_ver" == "$old_ver" ]]; then
        ok "Manager script is already up to date (v${old_ver})."
        pause
        return 0
    fi

    mkdir -p "$CONFIG_DIR"
    cp "$tmp" "$MANAGER_SCRIPT"
    chmod +x "$MANAGER_SCRIPT"
    ln -sf "$MANAGER_SCRIPT" "$MANAGER_BIN"

    ok "Manager script updated: v${old_ver} → v${new_ver}"
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
    read -r -p "Choice: " choice

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
    read -r -p "Restart the bot? (Y/n): " restart
    if [[ "${restart,,}" != "n" ]]; then
        action_restart_quiet
    fi
    pause
}

action_restart_quiet() {
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
        read -r -p "  Select an option: " choice
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

case "${1:-}" in
    install)   require_root; action_install ;;
    uninstall) require_root; action_uninstall ;;
    update)         require_root; action_update ;;
    update-script)  require_root; action_update_script ;;
    logs)           require_root; action_logs ;;
    restart)        require_root; action_restart ;;
    status)         require_root; action_status ;;
    urls)           require_root; action_urls ;;
    ""|menu)        require_root; main_menu ;;
    *)
        echo "Usage: pasarguardbot [install|uninstall|update|update-script|logs|restart|status|urls|menu]"
        exit 1
        ;;
esac
