# Docker Panel

A lightweight Docker management panel written in Bash, inspired by 1Panel's Docker management logic.

## Features

- **Dashboard** — Overview of containers, images, volumes, networks, and disk usage
- **Container Management** — List, create, start, stop, restart, remove, inspect, logs, exec, stats
- **Image Management** — List, pull, remove, prune, search Docker Hub
- **Volume Management** — List, create, remove, inspect
- **Network Management** — List, create, remove, inspect
- **Compose Management** — Up, down, ps, logs
- **System** — Docker info, prune unused data, prune all data

## Requirements

- Bash 4.0+
- Docker (with proper permissions)
- `python3` (for container inspect formatting, optional — falls back to raw JSON)
- `curl` (for Docker Hub search)

## Installation

```bash
git clone https://github.com/tophyZH/docker-panel.git
cd docker-panel
chmod +x docker-panel.sh
sudo ln -sf "$(pwd)/docker-panel.sh" /usr/local/bin/docker-panel
```

## Usage

### Interactive Mode

```bash
docker-panel
```

### CLI Mode

```bash
# Dashboard
docker-panel dashboard

# Containers
docker-panel container list
docker-panel container list running
docker-panel container inspect <id>
docker-panel container start <id>
docker-panel container stop <id>
docker-panel container restart <id>
docker-panel container rm <id>
docker-panel container logs <id> [lines]
docker-panel container exec <id> [shell]
docker-panel container stats [id]
docker-panel container create

# Images
docker-panel image list
docker-panel image pull <name>
docker-panel image rm <id>
docker-panel image prune
docker-panel image search <query>

# Volumes
docker-panel volume list
docker-panel volume create <name>
docker-panel volume rm <name>
docker-panel volume inspect <name>

# Networks
docker-panel network list
docker-panel network create <name>
docker-panel network rm <name>
docker-panel network inspect <name>

# Compose
docker-panel compose up [file]
docker-panel compose down [file]
docker-panel compose ps [file]
docker-panel compose logs [file]

# System
docker-panel system info
docker-panel system prune
docker-panel system prune-all
```

## Configuration

Configuration is stored in `~/.docker-panel/config.conf`:

```bash
DEBUG=0
DEFAULT_COMPOSE_FILE=docker-compose.yml
```

## License

MIT
