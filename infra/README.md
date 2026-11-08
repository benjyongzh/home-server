# Host infrastructure

This directory mirrors non-secret host files that are required outside the
repository. The deployed files on the Ubuntu VM remain the runtime source of
truth; the copies here make disaster reconstruction possible.

Host dependencies are systemd, Docker Engine/CLI, Bash, a POSIX shell,
coreutils (`timeout`, `install`, `mktemp`, `mv`), findutils, util-linux
(`findmnt`), and `nfs-common`. The PostgreSQL container must provide `pg_dump`
and `pg_restore`.

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

Live inspection on 8 November 2026 found the deployed scripts and units owned
by `nobody:nogroup` (with modes ranging from `0600` to `0755`). That ownership
is not the recommended steady state: a process running as `nobody` could own
and potentially modify critical startup/backup files. Correct ownership to
`root:root` during an approved maintenance change after verifying checksums;
this repository review deliberately did not alter the live host.

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
