#!/usr/bin/env bash
# docker-panel.sh - A lightweight Docker management panel written in Bash
# Inspired by 1Panel's Docker management logic
# License: MIT

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Config ──────────────────────────────────────────────────────────────
SCRIPT_NAME="docker-panel"
VERSION="1.0.0"
CONFIG_DIR="${HOME}/.docker-panel"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
LOG_FILE="${CONFIG_DIR}/docker-panel.log"
HISTORY_FILE="${CONFIG_DIR}/history"

# ── Utility Functions ───────────────────────────────────────────────────

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${msg}" >> "${LOG_FILE}"
}

info()  { echo -e "${GREEN}[INFO]${NC} $*"; log "INFO" "$@"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*";  log "WARN" "$@"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; log "ERROR" "$@"; }
debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${CYAN}[DEBUG]${NC} $*" && log "DEBUG" "$@"; }

print_header() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              Docker Panel v${VERSION}                        ║"
    echo "║         Lightweight Docker Management Tool                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_separator() {
    echo -e "${BLUE}──────────────────────────────────────────────────────────────${NC}"
}

print_menu_item() {
    local num="$1"
    local label="$2"
    echo -e "  ${CYAN}[${num}]${NC} ${label}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $*"
}

print_failure() {
    echo -e "${RED}✗${NC} $*"
}

confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-y}"
    local yn
    if [[ "$default" == "y" ]]; then
        read -rp "$prompt [Y/n]: " yn
        yn="${yn:-y}"
    else
        read -rp "$prompt [y/N]: " yn
        yn="${yn:-n}"
    fi
    [[ "$yn" =~ ^[Yy]$ ]]
}

pause() {
    echo
    read -rp "Press Enter to continue..." _dummy
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        error "Docker is not installed or not in PATH"
        return 1
    fi
    if ! docker info &>/dev/null; then
        error "Docker daemon is not running or you don't have permission"
        error "Try: sudo usermod -aG docker \$USER && newgrp docker"
        return 1
    fi
    return 0
}

check_docker_compose() {
    if docker compose version &>/dev/null 2>&1; then
        echo "plugin"
    elif command -v docker-compose &>/dev/null 2>&1; then
        echo "standalone"
    else
        echo "none"
    fi
}

# ── Docker Stats ────────────────────────────────────────────────────────

get_docker_stats() {
    local stats
    stats=$(docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}\t{{.Reclaimable}}" 2>/dev/null)
    echo "$stats"
}

get_container_count() {
    docker ps -aq 2>/dev/null | wc -l
}

get_running_count() {
    docker ps -q 2>/dev/null | wc -l
}

get_image_count() {
    docker images -q 2>/dev/null | wc -l
}

get_volume_count() {
    docker volume ls -q 2>/dev/null | wc -l
}

get_network_count() {
    docker network ls -q 2>/dev/null | wc -l
}

# ── Container Management ────────────────────────────────────────────────

list_containers() {
    local filter="${1:-all}"
    local format="table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

    if [[ "$filter" == "running" ]]; then
        docker ps --format "$format" 2>/dev/null
    elif [[ "$filter" == "stopped" ]]; then
        docker ps -a --filter "status=exited" --format "$format" 2>/dev/null
    else
        docker ps -a --format "$format" 2>/dev/null
    fi
}

container_details() {
    local container_id="$1"
    if [[ -z "$container_id" ]]; then
        read -rp "Container ID or name: " container_id
    fi

    local inspect
    inspect=$(docker inspect "$container_id" 2>/dev/null)
    if [[ -z "$inspect" ]]; then
        error "Container not found: $container_id"
        return 1
    fi

    echo -e "${BOLD}Container Details:${NC}"
    echo "$inspect" | python3 -c "
import json, sys
data = json.load(sys.stdin)[0]
print(f\"  ID:           {data['Id'][:12]}\")
print(f\"  Name:         {data['Name']}\")
print(f\"  Image:        {data['Config']['Image']}\")
print(f\"  Status:       {data['State']['Status']}\")
print(f\"  Running:      {data['State']['Running']}\")
print(f\"  Started:      {data['State']['StartedAt']}\")
print(f\"  RestartCount: {data['RestartCount']}\")
print(f\"  Platform:     {data['Platform']}\")
print(f\"  Memory:       {data['HostConfig']['Memory']}\")
print(f\"  CPU Shares:   {data['HostConfig']['CpuShares']}\")
print(f\"  NetworkMode:  {data['HostConfig']['NetworkMode']}\")
ports = data['NetworkSettings'].get('Ports', {})
if ports:
    print(f\"  Ports:\")
    for k, v in ports.items():
        if v:
            for p in v:
                print(f\"    {p.get('HostIp','')}:{p.get('HostPort','')} -> {k}\")
env_vars = data['Config'].get('Env', [])
if env_vars:
    print(f\"  Env ({len(env_vars)} vars)\")
mounts = data.get('Mounts', [])
if mounts:
    print(f\"  Mounts:\")
    for m in mounts:
        print(f\"    {m.get('Source','')} -> {m.get('Destination','')} ({m.get('Mode','')})\")
" 2>/dev/null || echo "$inspect" | head -50
}

start_container() {
    local container_id="$1"
    if [[ -z "$container_id" ]]; then
        read -rp "Container ID or name: " container_id
    fi
    info "Starting container: $container_id"
    docker start "$container_id" 2>/dev/null && print_success "Started" || print_failure "Failed to start"
}

stop_container() {
    local container_id="$1"
    if [[ -z "$container_id" ]]; then
        read -rp "Container ID or name: " container_id
    fi
    info "Stopping container: $container_id"
    docker stop "$container_id" 2>/dev/null && print_success "Stopped" || print_failure "Failed to stop"
}

restart_container() {
    local container_id="$1"
    if [[ -z "$container_id" ]]; then
        read -rp "Container ID or name: " container_id
    fi
    info "Restarting container: $container_id"
    docker restart "$container_id" 2>/dev/null && print_success "Restarted" || print_failure "Failed to restart"
}

remove_container() {
    local container_id="$1"
    if [[ -z "$container_id" ]]; then
        read -rp "Container ID or name: " container_id
    fi
    if ! confirm "Remove container $container_id?" "n"; then
        warn "Cancelled"
        return
    fi
    info "Removing container: $container_id"
    docker rm -f "$container_id" 2>/dev/null && print_success "Removed" || print_failure "Failed to remove"
}

container_logs() {
    local container_id="$1"
    if [[ -z "$container_id" ]]; then
        read -rp "Container ID or name: " container_id
    fi
    local lines="${2:-100}"
    info "Showing last $lines lines of logs for $container_id"
    docker logs --tail "$lines" -f "$container_id" 2>/dev/null
}

container_exec() {
    local container_id="$1"
    if [[ -z "$container_id" ]]; then
        read -rp "Container ID or name: " container_id
    fi
    local shell="${2:-/bin/sh}"
    info "Executing $shell in $container_id"
    docker exec -it "$container_id" "$shell" 2>/dev/null
}

container_stats() {
    local container_id="$1"
    if [[ -z "$container_id" ]]; then
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}" 2>/dev/null
    else
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}" "$container_id" 2>/dev/null
    fi
}

create_container() {
    echo -e "${BOLD}Create Container${NC}"
    print_separator

    local name image ports volumes env_vars network restart_policy
    read -rp "Container name (optional): " name
    read -rp "Image (e.g., nginx:latest): " image
    [[ -z "$image" ]] && { error "Image is required"; return 1; }

    read -rp "Port mappings (e.g., 8080:80,443:443, optional): " ports
    read -rp "Volume mappings (e.g., /host:/container, optional): " volumes
    read -rp "Environment variables (e.g., KEY=val,KEY2=val2, optional): " env_vars
    read -rp "Network (optional): " network
    read -rp "Restart policy (no/on-failure/always/unless-stopped, default=unless-stopped): " restart_policy
    restart_policy="${restart_policy:-unless-stopped}"

    local cmd="docker run -d"
    [[ -n "$name" ]] && cmd+=" --name $name"
    [[ -n "$ports" ]] && IFS=',' read -ra port_arr <<< "$ports" && for p in "${port_arr[@]}"; do cmd+=" -p $p"; done
    [[ -n "$volumes" ]] && IFS=',' read -ra vol_arr <<< "$volumes" && for v in "${vol_arr[@]}"; do cmd+=" -v $v"; done
    [[ -n "$env_vars" ]] && IFS=',' read -ra env_arr <<< "$env_vars" && for e in "${env_arr[@]}"; do cmd+=" -e $e"; done
    [[ -n "$network" ]] && cmd+=" --network $network"
    cmd+=" --restart $restart_policy"
    cmd+=" $image"

    info "Running: $cmd"
    eval "$cmd" 2>/dev/null && print_success "Container created" || print_failure "Failed to create container"
}

# ── Image Management ────────────────────────────────────────────────────

list_images() {
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}" 2>/dev/null
}

pull_image() {
    local image="$1"
    if [[ -z "$image" ]]; then
        read -rp "Image name (e.g., nginx:latest): " image
    fi
    [[ -z "$image" ]] && { error "Image name is required"; return 1; }
    info "Pulling image: $image"
    docker pull "$image" 2>/dev/null && print_success "Pulled" || print_failure "Failed to pull"
}

remove_image() {
    local image_id="$1"
    if [[ -z "$image_id" ]]; then
        read -rp "Image ID or name: " image_id
    fi
    if ! confirm "Remove image $image_id?" "n"; then
        warn "Cancelled"
        return
    fi
    info "Removing image: $image_id"
    docker rmi -f "$image_id" 2>/dev/null && print_success "Removed" || print_failure "Failed to remove"
}

prune_images() {
    if ! confirm "Remove all unused images?" "n"; then
        warn "Cancelled"
        return
    fi
    info "Pruning unused images..."
    docker image prune -f 2>/dev/null && print_success "Pruned" || print_failure "Failed"
}

search_image() {
    local query="$1"
    if [[ -z "$query" ]]; then
        read -rp "Search query: " query
    fi
    [[ -z "$query" ]] && { error "Query is required"; return 1; }
    info "Searching Docker Hub for: $query"
    docker search --format "table {{.Name}}\t{{.Description}}\t{{.Stars}}\t{{.Official}}\t{{.Automated}}" "$query" 2>/dev/null | head -20
}

# ── Volume Management ───────────────────────────────────────────────────

list_volumes() {
    docker volume ls --format "table {{.Driver}}\t{{.Name}}\t{{.Scope}}" 2>/dev/null
}

create_volume() {
    local name="$1"
    if [[ -z "$name" ]]; then
        read -rp "Volume name: " name
    fi
    [[ -z "$name" ]] && { error "Volume name is required"; return 1; }
    local driver="${2:-local}"
    info "Creating volume: $name (driver: $driver)"
    docker volume create --driver "$driver" "$name" 2>/dev/null && print_success "Created" || print_failure "Failed to create"
}

remove_volume() {
    local name="$1"
    if [[ -z "$name" ]]; then
        read -rp "Volume name: " name
    fi
    if ! confirm "Remove volume $name?" "n"; then
        warn "Cancelled"
        return
    fi
    info "Removing volume: $name"
    docker volume rm "$name" 2>/dev/null && print_success "Removed" || print_failure "Failed to remove"
}

volume_details() {
    local name="$1"
    if [[ -z "$name" ]]; then
        read -rp "Volume name: " name
    fi
    docker volume inspect "$name" 2>/dev/null || error "Volume not found: $name"
}

# ── Network Management ──────────────────────────────────────────────────

list_networks() {
    docker network ls --format "table {{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}" 2>/dev/null
}

create_network() {
    local name="$1"
    if [[ -z "$name" ]]; then
        read -rp "Network name: " name
    fi
    [[ -z "$name" ]] && { error "Network name is required"; return 1; }
    local driver="${2:-bridge}"
    info "Creating network: $name (driver: $driver)"
    docker network create --driver "$driver" "$name" 2>/dev/null && print_success "Created" || print_failure "Failed to create"
}

remove_network() {
    local name="$1"
    if [[ -z "$name" ]]; then
        read -rp "Network name: " name
    fi
    if ! confirm "Remove network $name?" "n"; then
        warn "Cancelled"
        return
    fi
    info "Removing network: $name"
    docker network rm "$name" 2>/dev/null && print_success "Removed" || print_failure "Failed to remove"
}

network_details() {
    local name="$1"
    if [[ -z "$name" ]]; then
        read -rp "Network name: " name
    fi
    docker network inspect "$name" 2>/dev/null || error "Network not found: $name"
}

# ── Compose Management ──────────────────────────────────────────────────

compose_up() {
    local file="${1:-docker-compose.yml}"
    local compose_cmd
    compose_cmd=$(check_docker_compose)
    if [[ "$compose_cmd" == "none" ]]; then
        error "Docker Compose is not installed"
        return 1
    fi
    info "Starting compose stack from $file"
    if [[ "$compose_cmd" == "plugin" ]]; then
        docker compose -f "$file" up -d 2>/dev/null && print_success "Stack started" || print_failure "Failed"
    else
        docker-compose -f "$file" up -d 2>/dev/null && print_success "Stack started" || print_failure "Failed"
    fi
}

compose_down() {
    local file="${1:-docker-compose.yml}"
    local compose_cmd
    compose_cmd=$(check_docker_compose)
    if [[ "$compose_cmd" == "none" ]]; then
        error "Docker Compose is not installed"
        return 1
    fi
    if ! confirm "Stop and remove compose stack from $file?" "n"; then
        warn "Cancelled"
        return
    fi
    info "Stopping compose stack from $file"
    if [[ "$compose_cmd" == "plugin" ]]; then
        docker compose -f "$file" down 2>/dev/null && print_success "Stack stopped" || print_failure "Failed"
    else
        docker-compose -f "$file" down 2>/dev/null && print_success "Stack stopped" || print_failure "Failed"
    fi
}

compose_ps() {
    local file="${1:-docker-compose.yml}"
    local compose_cmd
    compose_cmd=$(check_docker_compose)
    if [[ "$compose_cmd" == "none" ]]; then
        error "Docker Compose is not installed"
        return 1
    fi
    if [[ "$compose_cmd" == "plugin" ]]; then
        docker compose -f "$file" ps 2>/dev/null
    else
        docker-compose -f "$file" ps 2>/dev/null
    fi
}

compose_logs() {
    local file="${1:-docker-compose.yml}"
    local compose_cmd
    compose_cmd=$(check_docker_compose)
    if [[ "$compose_cmd" == "none" ]]; then
        error "Docker Compose is not installed"
        return 1
    fi
    if [[ "$compose_cmd" == "plugin" ]]; then
        docker compose -f "$file" logs -f 2>/dev/null
    else
        docker-compose -f "$file" logs -f 2>/dev/null
    fi
}

# ── System / Cleanup ────────────────────────────────────────────────────

system_prune() {
    if ! confirm "Remove all unused Docker data (containers, images, networks, build cache)?" "n"; then
        warn "Cancelled"
        return
    fi
    info "Pruning Docker system..."
    docker system prune -f 2>/dev/null && print_success "Pruned" || print_failure "Failed"
}

system_prune_all() {
    if ! confirm "Remove ALL Docker data including volumes? This is destructive!" "n"; then
        warn "Cancelled"
        return
    fi
    info "Pruning all Docker data..."
    docker system prune -a -f --volumes 2>/dev/null && print_success "Pruned" || print_failure "Failed"
}

show_docker_info() {
    echo -e "${BOLD}Docker System Info:${NC}"
    print_separator
    docker info 2>/dev/null | head -30
    echo
    echo -e "${BOLD}Docker Version:${NC}"
    docker version 2>/dev/null | head -20
}

show_dashboard() {
    print_header
    echo -e "${BOLD}Dashboard${NC}"
    print_separator
    echo -e "  ${CYAN}Containers:${NC}  $(get_container_count) total, $(get_running_count) running"
    echo -e "  ${CYAN}Images:${NC}      $(get_image_count)"
    echo -e "  ${CYAN}Volumes:${NC}     $(get_volume_count)"
    echo -e "  ${CYAN}Networks:${NC}    $(get_network_count)"
    echo
    echo -e "${BOLD}Disk Usage:${NC}"
    get_docker_stats
    echo
    echo -e "${BOLD}Running Containers:${NC}"
    list_containers "running"
}

# ── Interactive Menus ───────────────────────────────────────────────────

container_menu() {
    while true; do
        print_header
        echo -e "${BOLD}Container Management${NC}"
        print_separator
        print_menu_item 1 "List all containers"
        print_menu_item 2 "List running containers"
        print_menu_item 3 "List stopped containers"
        print_menu_item 4 "Container details"
        print_menu_item 5 "Start container"
        print_menu_item 6 "Stop container"
        print_menu_item 7 "Restart container"
        print_menu_item 8 "Remove container"
        print_menu_item 9 "View container logs"
        print_menu_item 10 "Execute command in container"
        print_menu_item 11 "Container stats"
        print_menu_item 12 "Create container"
        print_menu_item 0 "Back to main menu"
        print_separator
        read -rp "Select option: " choice

        case "$choice" in
            1) list_containers "all"; pause ;;
            2) list_containers "running"; pause ;;
            3) list_containers "stopped"; pause ;;
            4) container_details; pause ;;
            5) start_container; pause ;;
            6) stop_container; pause ;;
            7) restart_container; pause ;;
            8) remove_container; pause ;;
            9) container_logs; pause ;;
            10) container_exec; pause ;;
            11) container_stats; pause ;;
            12) create_container; pause ;;
            0) return ;;
            *) warn "Invalid option"; sleep 1 ;;
        esac
    done
}

image_menu() {
    while true; do
        print_header
        echo -e "${BOLD}Image Management${NC}"
        print_separator
        print_menu_item 1 "List images"
        print_menu_item 2 "Pull image"
        print_menu_item 3 "Remove image"
        print_menu_item 4 "Prune unused images"
        print_menu_item 5 "Search Docker Hub"
        print_menu_item 0 "Back to main menu"
        print_separator
        read -rp "Select option: " choice

        case "$choice" in
            1) list_images; pause ;;
            2) pull_image; pause ;;
            3) remove_image; pause ;;
            4) prune_images; pause ;;
            5) search_image; pause ;;
            0) return ;;
            *) warn "Invalid option"; sleep 1 ;;
        esac
    done
}

volume_menu() {
    while true; do
        print_header
        echo -e "${BOLD}Volume Management${NC}"
        print_separator
        print_menu_item 1 "List volumes"
        print_menu_item 2 "Create volume"
        print_menu_item 3 "Remove volume"
        print_menu_item 4 "Volume details"
        print_menu_item 0 "Back to main menu"
        print_separator
        read -rp "Select option: " choice

        case "$choice" in
            1) list_volumes; pause ;;
            2) create_volume; pause ;;
            3) remove_volume; pause ;;
            4) volume_details; pause ;;
            0) return ;;
            *) warn "Invalid option"; sleep 1 ;;
        esac
    done
}

network_menu() {
    while true; do
        print_header
        echo -e "${BOLD}Network Management${NC}"
        print_separator
        print_menu_item 1 "List networks"
        print_menu_item 2 "Create network"
        print_menu_item 3 "Remove network"
        print_menu_item 4 "Network details"
        print_menu_item 0 "Back to main menu"
        print_separator
        read -rp "Select option: " choice

        case "$choice" in
            1) list_networks; pause ;;
            2) create_network; pause ;;
            3) remove_network; pause ;;
            4) network_details; pause ;;
            0) return ;;
            *) warn "Invalid option"; sleep 1 ;;
        esac
    done
}

compose_menu() {
    while true; do
        print_header
        echo -e "${BOLD}Compose Management${NC}"
        print_separator
        print_menu_item 1 "Start stack (up -d)"
        print_menu_item 2 "Stop stack (down)"
        print_menu_item 3 "List services (ps)"
        print_menu_item 4 "View logs"
        print_menu_item 0 "Back to main menu"
        print_separator
        read -rp "Select option: " choice

        case "$choice" in
            1) compose_up; pause ;;
            2) compose_down; pause ;;
            3) compose_ps; pause ;;
            4) compose_logs; pause ;;
            0) return ;;
            *) warn "Invalid option"; sleep 1 ;;
        esac
    done
}

system_menu() {
    while true; do
        print_header
        echo -e "${BOLD}System${NC}"
        print_separator
        print_menu_item 1 "Docker info"
        print_menu_item 2 "Dashboard"
        print_menu_item 3 "Prune unused data"
        print_menu_item 4 "Prune ALL data (destructive)"
        print_menu_item 0 "Back to main menu"
        print_separator
        read -rp "Select option: " choice

        case "$choice" in
            1) show_docker_info; pause ;;
            2) show_dashboard; pause ;;
            3) system_prune; pause ;;
            4) system_prune_all; pause ;;
            0) return ;;
            *) warn "Invalid option"; sleep 1 ;;
        esac
    done
}

# ── Main Menu ───────────────────────────────────────────────────────────

main_menu() {
    while true; do
        print_header
        echo -e "${BOLD}Main Menu${NC}"
        print_separator
        print_menu_item 1 "Dashboard"
        print_menu_item 2 "Container Management"
        print_menu_item 3 "Image Management"
        print_menu_item 4 "Volume Management"
        print_menu_item 5 "Network Management"
        print_menu_item 6 "Compose Management"
        print_menu_item 7 "System"
        print_menu_item 0 "Exit"
        print_separator
        read -rp "Select option: " choice

        case "$choice" in
            1) show_dashboard; pause ;;
            2) container_menu ;;
            3) image_menu ;;
            4) volume_menu ;;
            5) network_menu ;;
            6) compose_menu ;;
            7) system_menu ;;
            0) info "Goodbye!"; exit 0 ;;
            *) warn "Invalid option"; sleep 1 ;;
        esac
    done
}

# ── CLI Mode ────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Docker Panel v${VERSION} - Lightweight Docker Management Tool

Usage: $(basename "$0") [command] [options]

Commands:
  dashboard                     Show dashboard
  container list [all|running|stopped]  List containers
  container inspect <id>        Show container details
  container start <id>          Start container
  container stop <id>           Stop container
  container restart <id>        Restart container
  container rm <id>             Remove container
  container logs <id> [lines]   View container logs
  container exec <id> [shell]   Execute command in container
  container stats [id]          Show container stats
  container create              Create container interactively
  image list                    List images
  image pull <name>             Pull image
  image rm <id>                 Remove image
  image prune                   Prune unused images
  image search <query>          Search Docker Hub
  volume list                   List volumes
  volume create <name>          Create volume
  volume rm <name>              Remove volume
  volume inspect <name>         Show volume details
  network list                  List networks
  network create <name>         Create network
  network rm <name>             Remove network
  network inspect <name>        Show network details
  compose up [file]             Start compose stack
  compose down [file]           Stop compose stack
  compose ps [file]             List compose services
  compose logs [file]           View compose logs
  system info                   Show Docker info
  system prune                  Prune unused data
  system prune-all              Prune ALL data (destructive)
  help                          Show this help

Options:
  -d, --debug                   Enable debug mode
  -h, --help                    Show help
  -v, --version                 Show version
EOF
}

cli_mode() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        dashboard) show_dashboard ;;
        container)
            local sub="${1:-list}"
            shift || true
            case "$sub" in
                list) list_containers "${1:-all}" ;;
                inspect) container_details "$1" ;;
                start) start_container "$1" ;;
                stop) stop_container "$1" ;;
                restart) restart_container "$1" ;;
                rm) remove_container "$1" ;;
                logs) container_logs "$1" "${2:-100}" ;;
                exec) container_exec "$1" "${2:-/bin/sh}" ;;
                stats) container_stats "$1" ;;
                create) create_container ;;
                *) error "Unknown container subcommand: $sub"; return 1 ;;
            esac
            ;;
        image)
            local sub="${1:-list}"
            shift || true
            case "$sub" in
                list) list_images ;;
                pull) pull_image "$1" ;;
                rm) remove_image "$1" ;;
                prune) prune_images ;;
                search) search_image "$1" ;;
                *) error "Unknown image subcommand: $sub"; return 1 ;;
            esac
            ;;
        volume)
            local sub="${1:-list}"
            shift || true
            case "$sub" in
                list) list_volumes ;;
                create) create_volume "$1" ;;
                rm) remove_volume "$1" ;;
                inspect) volume_details "$1" ;;
                *) error "Unknown volume subcommand: $sub"; return 1 ;;
            esac
            ;;
        network)
            local sub="${1:-list}"
            shift || true
            case "$sub" in
                list) list_networks ;;
                create) create_network "$1" ;;
                rm) remove_network "$1" ;;
                inspect) network_details "$1" ;;
                *) error "Unknown network subcommand: $sub"; return 1 ;;
            esac
            ;;
        compose)
            local sub="${1:-ps}"
            shift || true
            case "$sub" in
                up) compose_up "$1" ;;
                down) compose_down "$1" ;;
                ps) compose_ps "$1" ;;
                logs) compose_logs "$1" ;;
                *) error "Unknown compose subcommand: $sub"; return 1 ;;
            esac
            ;;
        system)
            local sub="${1:-info}"
            shift || true
            case "$sub" in
                info) show_docker_info ;;
                prune) system_prune ;;
                prune-all) system_prune_all ;;
                *) error "Unknown system subcommand: $sub"; return 1 ;;
            esac
            ;;
        help|--help|-h) usage ;;
        version|--version|-v) echo "Docker Panel v${VERSION}" ;;
        *) error "Unknown command: $cmd"; usage; return 1 ;;
    esac
}

# ── Init ────────────────────────────────────────────────────────────────

init() {
    mkdir -p "$CONFIG_DIR"
    touch "$LOG_FILE" "$HISTORY_FILE"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
# Docker Panel Configuration
DEBUG=0
DEFAULT_COMPOSE_FILE=docker-compose.yml
EOF
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
}

# ── Main Entry ──────────────────────────────────────────────────────────

main() {
    init

    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--debug) DEBUG=1; shift ;;
            -h|--help) usage; exit 0 ;;
            -v|--version) echo "Docker Panel v${VERSION}"; exit 0 ;;
            *) break ;;
        esac
    done

    if ! check_docker; then
        error "Docker check failed. Please ensure Docker is installed and running."
        exit 1
    fi

    if [[ $# -eq 0 ]]; then
        main_menu
    else
        cli_mode "$@"
    fi
}

main "$@"
