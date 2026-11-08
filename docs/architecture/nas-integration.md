# NAS integration and startup dependencies

## Boot dependency chain

The NAS-dependent startup path is:

1. The host network reaches `network-online.target`.
2. `/etc/fstab` generates systemd automount units for the three NFS paths.
3. Docker starts.
4. Enabled `nas-apps.service` runs as part of `docker.service` startup.
5. `check-nas-mounts.sh` triggers and validates the `data` and `nextcloud`
   mounts and their exact NFS sources.
6. The unit verifies `/mnt/nas/nextcloud/data/.ncdata`.
7. Docker starts `jellyfin`, `nextcloud`, `immich_server`, `radarr`, `sonarr`,
   and `bazarr`.

The unit files and scripts are mirrored under [`infra/`](../../infra/).

## Verified live configuration (8 November 2026)

- `nas-apps.service` is enabled and active (`exited`) with a successful result.
- The service successfully ran at boot on 7 November 2026.
- All three NFS automount units are active.
- All three mounted sources match the expected NAS exports.
- `nfs-common` is installed.
- The six application containers use Docker restart policy `on-failure`.
- qBittorrent uses restart policy `no` and is intentionally not started.
- Gluetun is not part of `nas-apps.service`.

## `check-nas-mounts.sh`

The script depends on:

- POSIX `/bin/sh`
- `timeout` and `ls` from coreutils
- `findmnt` from util-linux
- Working systemd automounts and NFS client support

For each required application export it:

1. accesses the directory with a 20-second timeout to trigger automount;
2. verifies that the path is an NFS/NFSv4 mount;
3. compares the actual source with the exact expected export.

It currently validates `/mnt/nas/data` and `/mnt/nas/nextcloud`. It does not
validate `/mnt/nas/backups`, because that export is not required to start the
six applications. Backup monitoring must check it separately if NAS-hosted
backup workflows begin depending on it.

## `nas-apps.service`

The unit depends on Docker and orders itself after network-online and the two
application automounts. It is a `Type=oneshot` unit with
`RemainAfterExit=yes`, retries failures every 30 seconds, and has a 120-second
start timeout.

Its `ExecStart` uses `docker start`, so the six named containers must already
exist. On a fresh machine, create them with Compose first while keeping them
stopped, then enable/start the unit after validating storage.

## Safeguard limitations

This is a startup guard, not a full availability controller:

- It checks mounts only before its one-shot `docker start` command.
- It does not continuously monitor NFS health after startup.
- A later NAS outage does not automatically stop the containers.
- `hard` NFS mounts can leave application processes blocked in I/O.
- Manual `docker start`, `docker compose up`, Dockge actions, Docker API calls,
  and some other restart paths can bypass the systemd pre-check.
- Docker's restart policy is independent from this unit; a container failure
  after startup can cause Docker to retry it without rerunning the mount check.
- `RemainAfterExit=yes` reports the one-shot unit active after a successful
  start; that status is not proof that the NAS remains reachable.
- The `.ncdata` marker verifies the expected Nextcloud directory, but does not
  prove file/database consistency or NAS health.

Operators must verify mounts before any manual start/recreate of a
NAS-dependent application.

## Safe verification

Read-only checks:

```bash
sudo /usr/local/sbin/check-nas-mounts.sh
findmnt -M /mnt/nas/data
findmnt -M /mnt/nas/nextcloud
findmnt -M /mnt/nas/backups
systemctl status nas-apps.service
journalctl -u nas-apps.service -b
```

Check the expected mount marker:

```bash
test -f /mnt/nas/nextcloud/data/.ncdata
```

Do not use a successful `ls` alone as proof: an unmounted local directory can
exist at the same path. Always confirm the filesystem source with `findmnt`.

## Host file deployment

See [`infra/README.md`](../../infra/README.md) for destinations, permissions,
installation, and enablement commands. Unit or script changes require an
explicit host deployment and, for unit changes, `systemctl daemon-reload`.
Committing a mirror does not alter the live system.
