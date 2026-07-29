# Home Server Docker Stacks

This repository is a portable, Docker Compose-based home-server deployment.
Each application lives in its own stack under `stacks/`, while settings shared
by the whole machine live in `shared/`.

The repository currently provides:

- Local DNS and filtering with AdGuard Home
- Local reverse proxy routes with Caddy
- A Homepage dashboard
- Docker stack management with Dockge
- System monitoring with Beszel and Beszel Agent
- Media streaming with Jellyfin
- Photo management with Immich
- File sync and cloud storage with Nextcloud
- A shared PostgreSQL server
- A VPN-isolated torrent and media-automation stack

## How the repository works

Configuration is split into two levels:

1. `shared/.env` contains machine-wide settings such as the server IP,
   local domain, timezone, storage roots, Docker network name, user IDs, and
   host port allocations.
2. `stacks/<name>/.env` contains credentials and settings used only by that
   service.

Neither real `.env` file is committed. Safe `.env.example` templates document
every required variable.

All Compose commands should go through `shared/compose.sh`. The launcher loads
the shared environment first, then the selected stack environment:

```bash
./shared/compose.sh <stack-name> <docker-compose-arguments>
```

For example:

```bash
./shared/compose.sh homepage up -d
./shared/compose.sh homepage logs -f
./shared/compose.sh homepage down
```

Do not normally run plain `docker compose` inside a stack directory. Plain
Compose does not automatically load `shared/.env`.

## Repository structure

```text
/opt
├── README.md                       # This guide
├── .gitignore                      # Excludes secrets and runtime data
├── shared/
│   ├── .env                        # Real machine-wide configuration; ignored
│   ├── .env.example                # Safe machine-wide configuration template
│   ├── compose.sh                  # Shared Compose command launcher
│   └── README.md                   # Short shared-config reference
└── stacks/
    ├── adguard/                    # DNS filtering
    ├── beszel/                     # Monitoring hub
    ├── beszel-agent/               # Host monitoring agent
    ├── caddy/                      # Local reverse proxy
    ├── dockge/                     # Compose stack management UI
    ├── homepage/                   # Service dashboard
    ├── immich/                     # Photo management
    ├── jellyfin/                   # Media streaming
    ├── nextcloud/                  # File sync and cloud storage
    ├── postgres/                   # Shared PostgreSQL server
    └── torrent/                    # VPN, torrents, and media automation
```

Directories such as `stacks/homeassistant`, `stacks/mqtt`, and
`stacks/watchtower` may exist locally, but they contain no tracked Compose
configuration and are not currently deployable services in this repository.

Other local paths may also appear below `/opt`:

| Path | Purpose |
|---|---|
| `backups/` | Local backup destination; ignored by Git |
| `containerd/` | Container runtime state; ignored and not part of the deployment definitions |
| `docs/` | Optional local documentation workspace |
| `scripts/` | Optional location for host-level helper scripts |
| `passwords.txt` | Ignored local credential notes; not required by any Compose stack |
| `.agents/`, `.codex/` | Local development/assistant tooling, not homelab services |

## Included services

| Stack | Containers | Purpose |
|---|---|---|
| `adguard` | AdGuard Home | DNS server, filtering, and local DNS management |
| `beszel` | Beszel | Central monitoring dashboard and metrics storage |
| `beszel-agent` | Beszel Agent | Collects metrics from this Docker host |
| `caddy` | Caddy | Routes local `*.LOCAL_DOMAIN` names to containers |
| `dockge` | Dockge | Web interface for managing Compose stacks |
| `homepage` | Homepage | Dashboard, links, Docker status, and service widgets |
| `immich` | Immich Server, machine learning, Valkey, PostgreSQL | Photo upload, indexing, search, and machine learning |
| `jellyfin` | Jellyfin | Media library and streaming server |
| `nextcloud` | Nextcloud, Redis | File storage, synchronization, and web access |
| `postgres` | PostgreSQL 17 | Shared database server, currently used by Nextcloud |
| `torrent` | Gluetun, qBittorrent, Radarr, Sonarr, Prowlarr, Bazarr, FlareSolverr | VPN-isolated downloading and media automation |

Immich uses its own PostgreSQL and Valkey containers. It does not use the
shared `postgres` stack.

## Network model

`SHARED_NETWORK` in `shared/.env` names an external Docker network used by
Caddy and the applications it proxies. Its default name is `home-server`.

The following stacks join that network:

- Beszel
- Caddy
- Homepage
- Immich
- Jellyfin
- Nextcloud and its Redis container
- Gluetun, Radarr, Sonarr, Prowlarr, and Bazarr

Nextcloud also reaches the shared PostgreSQL container through this network.
The current `postgres` Compose file does not declare `SHARED_NETWORK`; the
PostgreSQL container must therefore be connected manually after it is first
created or recreated. The first-time deployment steps include the command.

The torrent stack also has a private `torrent-backend` network for its internal
application traffic.

qBittorrent has no independent network interface. It uses
`network_mode: service:gluetun`, so its traffic passes through the VPN
container. Gluetun publishes the qBittorrent Web UI.

Beszel Agent uses host networking so the Beszel hub can reach its configured
listen port directly.

## Ports and local addresses

Host ports are allocated centrally in `shared/.env`.

| Service | Default host port | Notes |
|---|---:|---|
| AdGuard DNS | `53/tcp`, `53/udp` | DNS clients should use the server's `LOCAL_IP` |
| AdGuard Web UI | `8080` | Direct management interface |
| Beszel Agent | `45876` | Host-network listen port |
| Beszel | `8090` | Also available through Caddy |
| Caddy | `80`, `443` | Current routes use HTTP; port 443 is reserved/published |
| Dockge | `5001` | Direct management interface |
| Homepage | `3000` | Also available through Caddy |
| Immich | `2283` | Also available through Caddy |
| Jellyfin | `8096` | Also available through Caddy |
| Nextcloud | `8081` | Also available through Caddy |
| PostgreSQL | `5432` | Protect with host firewall rules |
| qBittorrent | `8091` | Bound to `LOCAL_IP`, routed through Gluetun |
| Radarr | `7878` | Bound to `LOCAL_IP`, also available through Caddy |
| Sonarr | `7879` | Bound to `LOCAL_IP`, also available through Caddy |
| Prowlarr | `7880` | Bound to `LOCAL_IP` |
| Bazarr | `7881` | Bound to `LOCAL_IP` |

Caddy currently defines these local routes:

| Local URL | Upstream |
|---|---|
| `http://jellyfin.<LOCAL_DOMAIN>` | Jellyfin |
| `http://nextcloud.<LOCAL_DOMAIN>` | Nextcloud |
| `http://beszel.<LOCAL_DOMAIN>` | Beszel |
| `http://homepage.<LOCAL_DOMAIN>` | Homepage |
| `http://immich.<LOCAL_DOMAIN>` | Immich |
| `http://qbittorrent.<LOCAL_DOMAIN>` | qBittorrent through Gluetun |
| `http://radarr.<LOCAL_DOMAIN>` | Radarr |
| `http://sonarr.<LOCAL_DOMAIN>` | Sonarr |

For these names to work, DNS must resolve each name to `LOCAL_IP`. Configure
the records in AdGuard Home, another local DNS server, or client hosts files.

## Requirements

Install or provide:

- Linux with Docker Engine
- Docker Compose v2
- A working `/dev/net/tun` device for Gluetun
- Storage paths configured by `DATA_ROOT` and `MEDIA_ROOT`
- Correct ownership and permissions for the configured `PUID` and `PGID`
- A local DNS setup for the Caddy hostnames
- A Proton VPN WireGuard key before starting the torrent stack

The repository is designed to live under `/opt`, but `shared/compose.sh`
detects its actual checkout location and overrides `INSTALL_ROOT` when it runs.
External storage locations are still controlled explicitly by `DATA_ROOT` and
`MEDIA_ROOT`.

## First-time deployment

### 1. Create the shared configuration

```bash
cd /opt
cp shared/.env.example shared/.env
chmod 600 shared/.env
```

Edit `shared/.env` and review every section:

- Machine identity: `LOCAL_IP`, `LOCAL_DOMAIN`, `LOCAL_HOSTNAME`, and
  `TAILSCALE_IP`
- Primary user: `PRIMARY_USER`, `PRIMARY_EMAIL`, `PUID`, and `PGID`
- Host defaults: `TZ`, installation and storage roots, and network name
- Host port allocation

`LOCAL_IP` must be the LAN address of the machine running Docker.

### 2. Create each stack's private configuration

Create the private environment file for every stack you plan to run:

```bash
for stack in \
  adguard beszel-agent beszel caddy dockge homepage \
  immich jellyfin nextcloud postgres torrent
do
  cp "stacks/$stack/.env.example" "stacks/$stack/.env"
  chmod 600 "stacks/$stack/.env"
done
```

Some stack files contain only comments because all of that stack's current
settings are machine-wide. Keep the file in place because the shared launcher
checks for it.

### 3. Enter service credentials

At minimum, review these stack environments:

| File | Required information |
|---|---|
| `stacks/beszel-agent/.env` | Agent SSH public key and token generated by Beszel |
| `stacks/homepage/.env` | Widget API keys, passwords, and Beszel system ID |
| `stacks/immich/.env` | Database name, user, password, version, and storage paths |
| `stacks/nextcloud/.env` | PostgreSQL and Redis credentials and admin password |
| `stacks/postgres/.env` | Shared PostgreSQL user, password, and database |
| `stacks/torrent/.env` | Proton WireGuard private key and server country |

Do not place real credentials in `.env.example`.

### 4. Create the external Docker network

Load the shared settings and create the network if it does not already exist:

```bash
set -a
. ./shared/.env
set +a

docker network inspect "$SHARED_NETWORK" >/dev/null 2>&1 ||
  docker network create "$SHARED_NETWORK"
```

### 5. Prepare storage

Ensure these configured locations exist and are writable where required:

- `${DATA_ROOT}/immich/library`
- `${DATA_ROOT}/immich/postgres`
- `${DATA_ROOT}/nextcloud/data`
- `${MEDIA_ROOT}`

Immich also mounts the existing Nextcloud photo directory:

```text
${DATA_ROOT}/nextcloud/data/${PRIMARY_USER}/files/Photos
```

That path must exist before starting Immich. Change the Compose mount if a
different external-library path is required.

Stack-local application data is created below each stack's `data/`,
`config/`, or `gluetun/` directory and is excluded from Git.

### 6. Prepare the shared Nextcloud database

Start PostgreSQL first:

```bash
./shared/compose.sh postgres up -d
```

Connect the PostgreSQL container to the shared network:

```bash
set -a
. ./shared/.env
set +a

docker network connect "$SHARED_NETWORK" postgres
```

Run the network-connect command after any PostgreSQL container recreation. If
Docker reports that the endpoint already exists, PostgreSQL is already
connected and no change is needed.

Nextcloud expects the database, role, and password named in
`stacks/nextcloud/.env`.

`stacks/postgres/initdb/01-init.sql` is currently empty. It is a placeholder
for initial SQL and does not create the Nextcloud role or database. Before a
fresh Nextcloud deployment, either:

- Add an appropriate initialization mechanism before PostgreSQL initializes
  an empty data directory, or
- Create the role and database manually after starting PostgreSQL.

PostgreSQL initialization scripts run only when its data directory is empty.
Do not commit a real database password in `01-init.sql`.

To open a PostgreSQL shell using the configured administrative user:

```bash
./shared/compose.sh postgres exec postgres \
  sh -c 'psql -U "$POSTGRES_USER"'
```

Create the Nextcloud role and database using the names and password from
`stacks/nextcloud/.env`. Enter secrets interactively; do not save them in
tracked documentation or templates.

### 7. Start the services

A sensible dependency order is:

```bash
for stack in \
  postgres adguard beszel beszel-agent immich jellyfin \
  nextcloud torrent homepage caddy dockge
do
  ./shared/compose.sh "$stack" up -d
done
```

If the VPN credentials are not ready, omit `torrent`.

## Everyday commands

### Start or reconcile a stack

```bash
./shared/compose.sh jellyfin up -d
```

`up -d` creates missing containers and recreates only containers whose
configuration changed.

### Stop and remove a stack's containers

```bash
./shared/compose.sh jellyfin down
```

Named volumes and bind-mounted data remain unless explicitly removed.

### Restart an unchanged container

```bash
./shared/compose.sh jellyfin restart
```

Use `up -d`, not `restart`, after changing Compose files or environment
variables. `restart` does not apply new Compose configuration.

### View status

```bash
./shared/compose.sh jellyfin ps
```

### Follow logs

```bash
./shared/compose.sh jellyfin logs -f
```

For one container in a multi-container stack:

```bash
./shared/compose.sh torrent logs -f gluetun
```

### Validate rendered configuration

```bash
./shared/compose.sh nextcloud config --quiet
```

To inspect the complete rendered model:

```bash
./shared/compose.sh nextcloud config
```

The rendered model can contain secrets. Do not paste or commit its output.

### Preview changes without applying them

```bash
./shared/compose.sh nextcloud --dry-run up -d
```

### Pull images and apply updates

```bash
./shared/compose.sh jellyfin pull
./shared/compose.sh jellyfin up -d
```

Images tagged `latest` or `release` are not updated until pulled.

### Stop all stacks

Stop dependent applications before their databases or infrastructure:

```bash
for stack in \
  dockge caddy homepage torrent nextcloud jellyfin immich \
  beszel-agent beszel adguard postgres
do
  ./shared/compose.sh "$stack" down
done
```

## Changing machine-wide settings

Edit `shared/.env` when changing:

- The server IP, hostname, or local domain
- Timezone or host user IDs
- Storage roots
- Shared Docker network name
- Any published host port

Then apply the affected stacks with `up -d`. For a broad shared change such as
`LOCAL_IP`, `LOCAL_DOMAIN`, or `SHARED_NETWORK`, reconcile every stack:

```bash
for stack in \
  adguard beszel-agent beszel caddy dockge homepage \
  immich jellyfin nextcloud postgres torrent
do
  ./shared/compose.sh "$stack" up -d
done
```

## Stack-specific notes

### AdGuard Home

- Publishes DNS on TCP and UDP port 53.
- Stores working data under `stacks/adguard/data/`.
- Local DNS rewrites can be used to resolve the Caddy hostnames.
- Changing the host's existing DNS listener may be necessary if port 53 is
  already occupied.

### Beszel and Beszel Agent

- Beszel is the central monitoring hub.
- Beszel Agent uses host networking and reads the Docker socket.
- Generate the agent key and token in Beszel, then place them in
  `stacks/beszel-agent/.env`.
- The hub URL is derived from `LOCAL_IP` and `BESZEL_HOST_PORT`.

### Caddy

- `stacks/caddy/Caddyfile` contains the local reverse-proxy routes.
- `LOCAL_DOMAIN` is expanded when Caddy parses the file.
- Upstreams use container names on `SHARED_NETWORK`.
- Current routes use HTTP site addresses. Publishing port 443 alone does not
  enable HTTPS.

### Dockge

- Has read/write access to the Docker socket.
- Mounts `STACKS_ROOT` so it can manage these Compose projects.
- Receives `COMPOSE_ENV_FILES`, allowing it to load `shared/.env` followed by
  each stack's `.env`.
- Recreate Dockge after changing its own Compose environment or mounts.

### Homepage

- Reads Docker state through a read-only socket mount.
- Service URLs and common usernames are derived from shared configuration.
- API keys and passwords stay in `stacks/homepage/.env`.
- `services.yaml` uses `{{HOMEPAGE_VAR_*}}` placeholders.

### Immich

- Runs its own database and Valkey containers.
- Stores the photo library and database under `DATA_ROOT`.
- Mounts Nextcloud photos read-only as an external library.
- Keep the Immich Compose file compatible with the chosen Immich release.

### Jellyfin

- Stores configuration and cache below `stacks/jellyfin/data/`.
- Mounts `MEDIA_ROOT` read-only at `/media`.
- Confirm the container can read the media files using the host's permissions.

### Nextcloud

- Uses the shared `postgres` stack and its own Redis container.
- Stores application files below `stacks/nextcloud/data/html/`.
- Stores user data under `${DATA_ROOT}/nextcloud/data`.
- Trusted domains are derived from the shared LAN IP, Tailscale IP, hostname,
  and local domain.

### PostgreSQL

- Provides a shared PostgreSQL 17 server.
- Persists data below `stacks/postgres/data/`.
- Exposes port 5432; restrict access using the host firewall.
- Files in `initdb/` execute only during first initialization of an empty data
  directory.

### Torrent and media automation

- Gluetun establishes the Proton VPN connection.
- qBittorrent shares Gluetun's network namespace.
- Radarr, Sonarr, Prowlarr, Bazarr, and FlareSolverr communicate over
  `torrent-backend`.
- Media applications mount `MEDIA_ROOT` at `/data`.
- `scripts/update-qbit-port.sh` receives Proton's forwarded port from Gluetun
  and applies it to qBittorrent through its local API.
- Gluetun must become healthy before qBittorrent starts.

## File reference

### Repository files

| File | Purpose |
|---|---|
| `README.md` | Main installation and operations guide |
| `.gitignore` | Prevents secrets, runtime state, databases, logs, and backups from entering Git |
| `shared/.env.example` | Safe template for machine-wide configuration |
| `shared/.env` | Real machine-wide configuration; ignored and mode `600` |
| `shared/compose.sh` | Loads shared and stack environments before invoking Compose |
| `shared/README.md` | Concise shared-configuration reference |

### Files common to each stack

| File | Purpose |
|---|---|
| `compose.yaml` or `compose.yml` | Declares containers, images, ports, mounts, networks, healthchecks, and dependencies |
| `.env.example` | Safe template for that stack's service-only variables |
| `.env` | Real service-only values; ignored and mode `600` |
| `data/`, `config/`, or similar runtime directories | Persistent application state; ignored by Git |

### Unique stack files

| File | Purpose |
|---|---|
| `stacks/caddy/Caddyfile` | Local hostnames and reverse-proxy upstreams |
| `stacks/homepage/config/bookmarks.yaml` | Dashboard bookmark groups |
| `stacks/homepage/config/services.yaml` | Service cards, links, and API-backed widgets |
| `stacks/homepage/config/settings.yaml` | Dashboard title, theme, language, and layout settings |
| `stacks/homepage/config/widgets.yaml` | Resource, date/time, and search widgets |
| `stacks/homepage/config/docker.yaml` | Homepage Docker socket integration |
| `stacks/homepage/config/kubernetes.yaml` | Placeholder for Kubernetes integration |
| `stacks/homepage/config/proxmox.yaml` | Commented example for Proxmox integration |
| `stacks/homepage/config/custom.css` | Optional custom dashboard styles |
| `stacks/homepage/config/custom.js` | Optional custom dashboard JavaScript |
| `stacks/postgres/initdb/01-init.sql` | Placeholder for first-initialization SQL |
| `stacks/torrent/scripts/update-qbit-port.sh` | Synchronizes Proton's forwarded port into qBittorrent |

## Persistent data and backups

Git stores deployment definitions, not application data.

Back up at least:

- `shared/.env`
- Every `stacks/<name>/.env`
- Stack-local `data/`, `config/`, and `gluetun/` directories
- `DATA_ROOT`
- `MEDIA_ROOT` where the media itself must be protected
- PostgreSQL and Immich database data using application-consistent backup
  procedures

Copying only this Git repository to another machine does not copy databases,
photos, media, credentials, or application state.

Before backing up a live database directory at the filesystem level, stop the
database or use its supported logical backup tools.

## Git and secret safety

The root `.gitignore` excludes:

- Real `.env` files
- Password, credential, key, certificate, and VPN files
- Application runtime data and databases
- Logs, archives, backups, and temporary files
- Torrent application configuration and Gluetun state
- Container runtime state

Safe `.env.example` files are explicitly allowed.

Before committing:

```bash
git status
git diff --cached --check
```

Never use `git add -f` on a real `.env`, credential file, application data
directory, or database.

## Moving to another machine

For a transplant:

1. Copy or clone this repository.
2. Copy the private `.env` files securely, or recreate them from the examples.
3. Edit `shared/.env` for the new IP, hostname, domain, user IDs, storage
   roots, network name, and port availability.
4. Transfer the required persistent data separately.
5. Create the external Docker network.
6. Verify storage ownership and `/dev/net/tun`.
7. Validate every selected stack with `shared/compose.sh <stack> config`.
8. Start PostgreSQL, attach it to `SHARED_NETWORK`, and provision Nextcloud's
   role and database.
9. Start Nextcloud and the remaining stacks in dependency order.
10. Configure local DNS to point the new local names at the new `LOCAL_IP`.

## Troubleshooting

### Compose reports an unset variable

Use the shared launcher:

```bash
./shared/compose.sh <stack> config
```

Confirm both `shared/.env` and `stacks/<stack>/.env` exist.

### A local hostname does not resolve

Confirm:

- The name uses the configured `LOCAL_DOMAIN`
- DNS points the name to `LOCAL_IP`
- Caddy is running
- The target container is attached to `SHARED_NETWORK`

### Caddy returns a 502 response

The upstream application may be stopped, unhealthy, or absent from the shared
network:

```bash
./shared/compose.sh caddy logs
./shared/compose.sh <upstream-stack> ps
```

### Nextcloud cannot connect to PostgreSQL

Confirm:

- The `postgres` stack is running
- Both stacks use the same `SHARED_NETWORK`
- The Nextcloud role and database exist
- The credentials in `stacks/nextcloud/.env` match the provisioned role

### Torrent services cannot reach the Internet

Check Gluetun first:

```bash
./shared/compose.sh torrent ps
./shared/compose.sh torrent logs -f gluetun
```

Confirm `/dev/net/tun`, the WireGuard key, and the configured VPN server country.

### A configuration change did not take effect

Reconcile the stack:

```bash
./shared/compose.sh <stack> up -d
```

Do not rely on `restart` after changing Compose or environment files.
