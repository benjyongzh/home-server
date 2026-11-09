# Disaster recovery runbook

This runbook reconstructs the homelab after loss of the Ubuntu VM. It assumes
the NAS survives. If the NAS is also lost, restore its shares from the
independent backup that still needs to be implemented.

## Recovery inputs

Gather before starting:

- This Git repository at the desired commit
- An encrypted copy of `shared/.env` and every required stack `.env`
- UGREEN NAS address, share/export definitions, NFS squash/ACL settings, and
  snapshot schedules
- Nextcloud database custom archive
- Nextcloud application config (`stacks/nextcloud/data/html`) and NAS user data
- Immich managed library and database backup/data
- Stack-local application state for services that must retain configuration
- Proton WireGuard credentials only when the subscription/VPN is active
- DNS and Tailscale configuration

Git alone is insufficient: it intentionally excludes secrets, databases,
application state, photos, and media.

## 1. Build the Ubuntu VM

1. Install a supported Ubuntu release.
2. Assign the intended static/reserved LAN address.
3. Install Docker Engine, Docker Compose v2, `nfs-common`, `util-linux`, and
   coreutils.
4. Confirm time zone and time synchronization.
5. Create the primary user/UID/GID expected by the stack environments.
6. Enable Docker at boot.

Do not start NAS-dependent application containers yet.

## 2. Restore repository and secrets

Clone to `/opt` (or another location supported by `shared/compose.sh`), then:

```bash
cp shared/.env.example shared/.env
cp stacks/<stack>/.env.example stacks/<stack>/.env
chmod 600 shared/.env stacks/*/.env
```

Restore real values from the encrypted secret backup. Never recover secrets by
putting them into Git history.

## 3. Recreate NAS integration

1. Recreate `/mnt/nas/data`, `/mnt/nas/nextcloud`, and `/mnt/nas/backups`.
2. In `shared/.env`, set `NAS_HOST` to this installation's NAS address or
   hostname. Edit all three NFS source addresses in
   `infra/examples/fstab.nas.example` to match, then merge the adapted lines
   into `/etc/fstab`. Adjust export paths and mount points if they differ from
   the example, and keep the corresponding `NAS_*_ROOT` and
   `NEXTCLOUD_DATA_PATH` values in `shared/.env` consistent. `/etc/fstab` does
   not read `.env` automatically.
3. Install the mirrored scripts and systemd units as described in
   [`infra/README.md`](../../infra/README.md).
4. Reload systemd.
5. Trigger each automount and verify with `findmnt` that all three NFS sources
   are the intended NAS exports before creating or starting containers.
6. Confirm `/mnt/nas/nextcloud/data/.ncdata` exists.
7. Reapply the NAS NFS export/ACL policy and UGOS Pro snapshot schedules.

Do not copy the example over the complete `/etc/fstab`; preserve the VM's root,
EFI, swap, and any still-required local mounts.

## 4. Restore mini-PC storage

Restore, with correct ownership and permissions:

- `/srv/immich/library`
- `/srv/immich/postgres`, or prepare an empty database directory
  for logical restore
- `/opt/stacks/nextcloud/data/html`
- `/opt/stacks/postgres/data`, or prepare an empty shared PostgreSQL volume for
  logical restore
- Other required stack `data/`, `config/`, and `gluetun/` directories

Prefer application-consistent database restoration over copying a live
database directory. Never mix an arbitrary PostgreSQL data directory with a
different major server version.

## 5. Recreate Docker network and containers

Create the external shared network using `SHARED_NETWORK`, then validate every
selected Compose project:

```bash
./shared/compose.sh <stack> config --quiet
```

Create the six NAS-dependent containers without starting them:

```bash
./shared/compose.sh jellyfin create
./shared/compose.sh nextcloud create
./shared/compose.sh immich create
./shared/compose.sh torrent create radarr sonarr bazarr
```

The current `nas-apps.service` assumes these exact container names already
exist. It does not create them.

Create/start non-NAS infrastructure in dependency order, including the shared
PostgreSQL container, Redis dependencies, DNS, proxy, and monitoring as needed.

## 6. Restore Nextcloud

1. Restore `/opt/stacks/nextcloud/data/html`.
2. Confirm NAS user data is available at `/mnt/nas/nextcloud/data`.
3. Start/recreate the shared PostgreSQL container and attach it to
   `SHARED_NETWORK` if the Compose definition still requires the manual
   attachment.
4. Recreate the `nextcloud` role/database if necessary.
5. Restore the selected validated custom archive.
6. Start Nextcloud in maintenance mode first when practical.
7. Run version-appropriate Nextcloud upgrade/repair and file-scan steps only
   after consulting the matching Nextcloud documentation.
8. Validate users, apps, encryption state (if used), files, Redis locking,
   cron/background jobs, trusted domains, and external access.
9. Exit maintenance mode only after validation.

Database and file snapshots should represent compatible points in time. Keep
the original recovery material until acceptance testing is complete.

## 7. Restore Immich

Choose one database path:

- Restore the cold, version-compatible Immich PostgreSQL data directory, or
- Initialize an empty compatible database and restore a built-in SQL gzip dump
  from `/srv/immich/library/backups`.

Then:

1. Restore the full Immich library tree, not just its database dumps.
2. Confirm the read-only external library source at
   `/mnt/nas/nextcloud/data/<user>/files/Photos`.
3. Use an Immich version compatible with the dump/database schema.
4. Start the database and Valkey before Immich Server.
5. Validate login, asset counts, originals, thumbnails, videos, jobs, and the
   external library before allowing writes.
6. Recreate the application-level 02:00 database backup setting and retention
   of 14, then verify a new artifact appears.

## 8. Enable guarded startup and backups

After containers and mounts are verified:

```bash
sudo systemctl enable nas-apps.service
sudo systemctl enable --now nextcloud-db-backup.timer
sudo systemctl start nas-apps.service
```

Check journals and timer state. Starting `nas-apps.service` starts the six
named containers; do not run it until that action is intended.

Keep Gluetun and qBittorrent stopped while ProtonVPN is inactive. Before
starting either, verify subscription status, WireGuard credentials, Gluetun
health, kill-switch behavior, and the absence of any non-VPN network path for
qBittorrent.

## 9. Restore DNS and validate applications

Recreate local DNS records for Caddy hostnames, then test:

- mount sources and write access
- Docker restart policies
- Caddy routes
- Nextcloud file upload/download and background jobs
- Immich uploads and external library access
- Jellyfin scan/playback
- Radarr/Sonarr/Bazarr paths
- qBittorrent only after VPN safety approval
- scheduled database backups and NAS snapshots

## 10. Enable repository automation

GitHub Actions validates safe-example Compose renders, shell syntax, and
whitespace, and scans history with Gitleaks. Enable GitHub secret scanning and
push protection in repository settings as additional server-side controls.
CI does not replace restore rehearsals or runtime monitoring.

## 11. Close the recovery

Document:

- recovery date and restored versions
- backup artifacts used and validation results
- any skipped services or unresolved data gaps
- new secret locations/rotation
- next restore-test date

Do not delete recovery artifacts until the system has passed an agreed
observation period and independent backups have been refreshed.
