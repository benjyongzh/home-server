# Host infrastructure

This directory mirrors non-secret host files that are required outside the
repository. The deployed files on the Ubuntu VM remain the runtime source of
truth; the copies here make disaster reconstruction possible.

Host dependencies are systemd, Docker Engine/CLI, Bash, a POSIX shell,
coreutils (`timeout`, `install`, `mktemp`, `mv`), findutils, util-linux
(`findmnt`), and `nfs-common`. The PostgreSQL container must provide `pg_dump`
and `pg_restore`.

Both systemd services read `/opt/shared/.env` using `EnvironmentFile=`. Configure
`NAS_HOST`, `NAS_DATA_ROOT`, `NAS_NEXTCLOUD_ROOT`, `NAS_BACKUP_ROOT`,
`NEXTCLOUD_DATA_PATH`, and `NEXTCLOUD_DB_BACKUP_DIR` before enabling them.
Systemd does not expand references such as `${INSTALL_ROOT}` inside that file;
the NAS scripts use only the literal values of the six variables above. Keep
the live file private. `/etc/fstab` is separate and must still be updated if
the NAS address or mount paths change.

See [NAS integration](../docs/architecture/nas-integration.md) for the exact
dependency chain, limitations, and verification commands.

## Deployment destinations

| Repository file | Host destination | Recommended mode |
|---|---|---:|
| `scripts/check-nas-mounts.sh` | `/usr/local/sbin/check-nas-mounts.sh` | `0755 root:root` |
| `scripts/backup-nextcloud-db.sh` | `/usr/local/sbin/backup-nextcloud-db.sh` | `0700 root:root` |
| `systemd/nas-apps.service` | `/etc/systemd/system/nas-apps.service` | `0644 root:root` |
| `systemd/nextcloud-db-backup.service` | `/etc/systemd/system/nextcloud-db-backup.service` | `0644 root:root` |
| `systemd/nextcloud-db-backup.timer` | `/etc/systemd/system/nextcloud-db-backup.timer` | `0644 root:root` |
| `examples/fstab.nas.example` | Merge into `/etc/fstab` | `0644 root:root` |

Live inspection initially found the deployed scripts and units owned by
`nobody:nogroup`. During the approved 8 November 2026 maintenance, the two
scripts and two changed service units were redeployed as `root:root` with the
modes above. Verify ownership again after future deployments.

Install the scripts and units on a reconstructed host:

```bash
sudo install -o root -g root -m 0755 \
  infra/scripts/check-nas-mounts.sh /usr/local/sbin/check-nas-mounts.sh
sudo install -o root -g root -m 0700 \
  infra/scripts/backup-nextcloud-db.sh /usr/local/sbin/backup-nextcloud-db.sh
sudo install -o root -g root -m 0644 infra/systemd/*.service \
  infra/systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable nas-apps.service
sudo systemctl enable --now nextcloud-db-backup.timer
```

After a unit-file change, `daemon-reload` is required. Changes to
`shared/.env` are read on the next service invocation; they do not change
already-running containers or rerun an active one-shot `nas-apps.service`.

Do not start `nas-apps.service` until the NFS mounts, existing Docker
containers, and Nextcloud `.ncdata` marker have been verified. The unit uses
`docker start`; it does not create containers.

## Synchronization policy

When changing a deployed host file, update its repository copy in the same
change. Compare them without modifying either side:

```bash
sudo diff -u infra/scripts/check-nas-mounts.sh \
  /usr/local/sbin/check-nas-mounts.sh
sudo diff -u infra/scripts/backup-nextcloud-db.sh \
  /usr/local/sbin/backup-nextcloud-db.sh
sudo diff -u infra/systemd/nas-apps.service \
  /etc/systemd/system/nas-apps.service
```
