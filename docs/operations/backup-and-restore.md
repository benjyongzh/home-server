# Backup and restore

## Coverage summary

| Asset | Current protection | Location | Main gap |
|---|---|---|---|
| Nextcloud PostgreSQL database | Daily validated custom archive, about 30 days | `/var/backups/nextcloud-db` plus verified copy under `/mnt/nas/backups/nextcloud-db` | Mini-PC copy shares host failure domain; NAS copy shares NAS disk failure domain |
| Nextcloud user files | NAS Btrfs snapshots weekly, 6 retained | NAS `nextcloud-data` | One physical NAS disk; snapshots are not independent backups |
| Immich PostgreSQL database | Built-in daily SQL gzip dump, 14 retained | `/srv/immich/library/backups` | Same VM root filesystem as Immich library |
| Immich managed files | No independent backup verified | `/srv/immich/library` | VM root disk is a single failure domain |
| Immich external Nextcloud photos | Covered only with Nextcloud NAS files/snapshots | NAS `nextcloud-data` | Same single NAS disk |
| Media/download data | Monthly NAS Btrfs snapshots, 6 retained | NAS `data` | One physical NAS disk |
| Compose/IaC | Git repository | GitHub after push | Private `.env` files are intentionally absent |
| Private configuration/secrets | Local `.env` files | Mini PC | Requires a separate encrypted secret backup |

## Nextcloud database backup

### Actual implementation

The mirrored script is
[`infra/scripts/backup-nextcloud-db.sh`](../../infra/scripts/backup-nextcloud-db.sh)
and deploys to `/usr/local/sbin/backup-nextcloud-db.sh`.

It:

1. creates `/var/backups/nextcloud-db` with mode `0700`;
2. uses `umask 077` and a temporary file;
3. runs `pg_dump -U nextcloud -d nextcloud -Fc` in container `postgres`;
4. verifies the file is non-empty;
5. runs `pg_restore --list`;
6. runs a full `pg_restore --file=/dev/null` decompression/read test;
7. atomically renames the verified file;
8. verifies `/mnt/nas/backups` is mounted from the expected export, copies the
   archive to a temporary NAS file, byte-compares it, and atomically renames
   the verified copy;
9. deletes `nextcloud-*.dump` files older than 29 days from both destinations.

The backup service loads `/opt/shared/.env` through systemd's
`EnvironmentFile=`. The script requires `NAS_HOST`, `NAS_BACKUP_ROOT`, and
`NEXTCLOUD_DB_BACKUP_DIR`; it verifies the configured NAS export before
creating or writing a backup directory there. Changing `/etc/fstab` remains a
separate host administration step.

`-mtime +29` gives approximately 30 days of retention based on whole-day age.

The systemd timer is actually configured as:

```ini
OnCalendar=*-*-* 02:00:00
Persistent=true
AccuracySec=1min
```

`Persistent=true` causes a missed run to execute after the host returns.

### Verified history

On 8 November 2026 the timer was enabled and active. It triggered at
02:00:11 Asia/Singapore, the service exited successfully at 02:00:15, and the
next run was scheduled for 9 November at 02:00. The directory contained a
manual/initial archive from 00:17 and the scheduled 02:00 archive, each about
18 MB.

This is a short execution history because the timer was newly introduced.
Continue monitoring it until several daily runs and retention cleanup have
been observed.

The successful 02:00 service result alone did not establish that a NAS copy
existed: none was found during the later preflight. A manual run at 13:13 on
8 November 2026 succeeded with the updated script and produced a matching
local and NAS archive; this is the first verified NAS copy.

### Operational checks

```bash
systemctl status nextcloud-db-backup.timer
systemctl list-timers nextcloud-db-backup.timer --all
journalctl -u nextcloud-db-backup.service
sudo ls -lh /var/backups/nextcloud-db
```

Periodically perform a restore rehearsal into an isolated PostgreSQL instance.
Archive validation is valuable, but only a real restore test proves the whole
recovery process.

### Restore outline

1. Confirm the dump predates the incident and is readable with
   `pg_restore --list`.
2. Put Nextcloud in maintenance mode or stop the Nextcloud application
   container to prevent writes.
3. Back up the current database before replacing it when possible.
4. Recreate an empty `nextcloud` database owned by the `nextcloud` role.
5. Pipe the custom archive to `pg_restore` inside the `postgres` container.
6. Restore the matching Nextcloud file/config state.
7. Start Nextcloud, run required version-specific maintenance commands, and
   validate users/files before reopening access.

Example archive validation (read-only):

```bash
docker exec -i postgres pg_restore --list \
  < /var/backups/nextcloud-db/nextcloud-YYYY-MM-DD_HH-MM-SS.dump \
  > /dev/null
```

Database replacement is destructive. Adapt the restore commands to the
PostgreSQL/Nextcloud versions and rehearse them before an emergency.

### Consistency limitation

The timer backs up the database independently of the NAS file tree. It does
not put Nextcloud in maintenance mode or coordinate a filesystem snapshot.
Restoring a database and files from different points in time can leave missing
or orphaned file records. A stronger design would coordinate maintenance mode,
database dump, and a corresponding immutable file snapshot.

## Immich database backup

Immich's backup is an application-level feature, not a systemd service in this
repository.

The observed destination is:

```text
/srv/immich/library/backups
```

This is the host side of Immich's `/data/backups` directory. On 8 November
2026 it contained 14 consecutive files named like
`immich-db-backup-...sql.gz`, dated daily at 02:00 and covering 26 October
through 8 November. This confirms the intended daily 02:00 schedule and
14-backup retention were producing the expected artifacts at inspection time.

The schedule/retention are managed in Immich's administrative settings. They
must be recreated manually after an application rebuild and checked after
upgrades. A separate systemd timer/script to replicate these dumps to NAS is
still missing; add independent replication before relying on the local Immich
dumps for disaster recovery.

These dumps protect the Immich database only. They do not protect uploaded
assets, thumbnails, profiles, encoded videos, or the external Nextcloud photo
library. Because the dumps live inside the same mini-PC library tree, a disk
loss can destroy both data and backups.

For recovery, restore the managed Immich library and a compatible database
dump, use the matching Immich/PostgreSQL version, and follow the restore
procedure for that pinned Immich release. Treat the read-only Nextcloud Photos
library as a separate dependency restored from the NAS file backup.

## NAS snapshots

Manual UGOS Pro settings:

| Shared folder | Schedule | Retention |
|---|---|---:|
| `nextcloud-data` | Sunday at 12:00 noon (12 PM) | 6 |
| `data` | First day of month at 12:00 noon (12 PM) | 6 |

Review these settings after NAS firmware resets, share recreation, or disaster
recovery. They cannot be restored from files in this repository.

Snapshots on the NAS's single 8 TB disk are not independent backups. Establish
an encrypted external/offsite copy for irreplaceable Nextcloud files, photos,
Immich managed assets, private configuration, and at least one recent validated
database archive.

## Migration artifacts

These pre/post-migration recovery sets currently exist:

- `/opt/stacks/nextcloud/migration-backup-20261107/`
- `/opt/stacks/torrent/backups/qbittorrent-pre-nas.tar.gz`
- `/mnt/nas/backups/nextcloud-migration-20261107/`

The Nextcloud sets contain database dumps, configuration archives, Compose
configuration, and a private `.env`. The qBittorrent archive may contain
credentials, API/session data, torrent metadata, and paths. They are excluded
from Git and must never be committed.

Retention recommendation:

1. Keep them until the NAS deployment, scheduled backups, and at least one
   restore rehearsal are verified.
2. Record an owner and review/expiry date.
3. Store retained copies with restrictive ACLs and encryption.
4. Maintain at least one independent copy outside both the mini PC and the
   single-disk NAS.
5. Remove obsolete copies through an approved, deliberate process after the
   retention decision; do not leave credential-bearing archives indefinitely.

At inspection time the NAS migration directory was broadly writable through
the current NFS mapping. Its `.env` was mode `0600`, but other artifacts and
directories had permissive modes. Review NAS ACLs and the all-users squash
policy.

Older temporary `pre-nas` configuration copies were reported cleaned up and
are not reconstruction dependencies. The three explicitly listed migration
sets above are the remaining artifacts covered by this retention guidance.
