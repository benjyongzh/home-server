# Storage architecture

## Overview

Persistent file storage is split between the Ubuntu VM's mini-PC disk and a
UGREEN DH4300 Plus NAS at `192.168.0.220`. The Ubuntu VM is currently
`192.168.0.240`.

The migration deliberately preserved container-side paths so applications did
not need library or data-directory reconfiguration.

## Storage map

| Host path | Backing storage | Container consumers | Container path | Access |
|---|---|---|---|---|
| `/mnt/nas/data` | NAS export `/volume1/data` | Jellyfin | `/media` | Read-only |
| `/mnt/nas/data` | NAS export `/volume1/data` | qBittorrent, Radarr, Sonarr, Bazarr | `/data` | Read-write |
| `/mnt/nas/nextcloud/data` | NAS export `/volume1/nextcloud-data` | Nextcloud | `/var/www/html/data` | Read-write |
| `/mnt/nas/nextcloud/data/<user>/files/Photos` | NAS export `/volume1/nextcloud-data` | Immich external library | `/mnt/external/nextcloud-photos` | Read-only |
| `/mnt/nas/backups` | NAS export `/volume1/backups` | Migration/operator backups | No application mount | Operator-managed |
| `/mnt/home-server-data/immich/library` | Mini-PC disk | Immich Server | `/data` | Read-write |
| `/mnt/home-server-data/immich/postgres` | Mini-PC disk | Immich PostgreSQL | `/var/lib/postgresql/data` | Read-write |
| `/opt/stacks/postgres/data` | Mini-PC disk | Shared PostgreSQL | `/var/lib/postgresql/data` | Read-write |
| `/opt/stacks/<stack>/data` or `config` | Mini-PC disk | Stack-specific configuration/state | Application-specific | Read-write |

The shared PostgreSQL container holds Nextcloud's database. Nextcloud's files
are on the NAS, but its database remains on the mini PC.

Immich's database, managed files, thumbnails, encoded video, profiles, uploads,
and built-in database dumps remain under its mini-PC library root. Only the
Nextcloud Photos external library is read from the NAS.

## NFS exports

| NAS export | Ubuntu mount point | Purpose |
|---|---|---|
| `192.168.0.220:/volume1/data` | `/mnt/nas/data` | Media, downloads, movies, and TV |
| `192.168.0.220:/volume1/nextcloud-data` | `/mnt/nas/nextcloud` | Nextcloud user data and Immich external Photos source |
| `192.168.0.220:/volume1/backups` | `/mnt/nas/backups` | NAS-hosted backup artifacts |

The deployed mounts currently negotiate NFSv3 over TCP. `/etc/fstab` specifies
`rw,hard,_netdev,nofail,x-systemd.automount`. The reproducible lines live in
[`infra/examples/fstab.nas.example`](../../infra/examples/fstab.nas.example).

`hard` protects against silently failing writes, but an application doing I/O
may block for an unbounded period while the NAS is unavailable. See
[NAS troubleshooting](../operations/nas-troubleshooting.md).

## Legacy SMB storage

`/mnt/media` was the former Windows-hosted CIFS media share. Its `/etc/fstab`
entry is now commented out on the source host, and the reproducible fstab
example intentionally omits it. Jellyfin, qBittorrent, Radarr, Sonarr, and
Bazarr use `/mnt/nas/data` instead. Do not re-enable `/mnt/media` when
reconstructing this homelab; assess any unrelated external consumers
separately.

## NFS identity and permissions

The NAS `nextcloud-data` export currently squashes all NFS users to the NAS
administrator. This allows Nextcloud's `www-data` process (UID 33) to write,
but it broadens effective authority and weakens per-user attribution.

Future improvement should evaluate a dedicated NAS service identity, aligned
UID/GID ownership, and a least-privilege export/ACL policy. Any change must be
tested against Nextcloud upgrades, background jobs, file locking, and Immich's
read-only external library before production rollout.

## NAS snapshots

These schedules are configured manually in UGOS Pro and are not represented by
Ubuntu files:

| Shared folder | Schedule | Retention |
|---|---|---:|
| `nextcloud-data` | Every Sunday at 12:00 noon (12 PM) | 6 snapshots |
| `data` | First day of every month at 12:00 noon (12 PM) | 6 snapshots |

The NAS currently contains one 8 TB IronWolf HDD. Btrfs snapshots share the
same disk and filesystem; they protect against some logical mistakes but not
disk failure, NAS loss, theft, fire, destructive administrator access, or all
forms of corruption/ransomware. Important data requires an independent,
preferably offsite, backup.

## Source-of-truth matrix

| Asset | Source of truth | Git-tracked? |
|---|---|---|
| Compose definitions | `stacks/*/compose.y*ml` | Yes |
| Safe variable contracts | `.env.example` files | Yes |
| Real secrets/deployment values | `shared/.env`, `stacks/*/.env` | No |
| NFS mount definition | `/etc/fstab` | Example only |
| Host startup/backup automation | `/etc/systemd/system`, `/usr/local/sbin` | Mirrored under `infra/` |
| NAS snapshot schedules and NFS permissions | UGOS Pro | Documentation only |
| Application data and databases | Mini-PC/NAS paths above | No |
