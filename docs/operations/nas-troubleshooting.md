# NAS troubleshooting

## Safety rules

- Do not start NAS-dependent containers until mount sources are verified.
- Do not treat an existing mount-point directory as proof that NFS is mounted.
- Do not let Docker write application data into an unmounted local directory.
- Do not start qBittorrent while the VPN is inactive or unverified.
- Preserve logs and backup artifacts before making destructive changes.

Compose uses long-form NAS bind mounts with `create_host_path: false` where
appropriate. This prevents Compose from silently creating a missing source
directory, but it does not replace mount-source validation.

## Check mount identity

```bash
findmnt -rn -M /mnt/nas/data -t nfs,nfs4 -o SOURCE,TARGET,FSTYPE,OPTIONS
findmnt -rn -M /mnt/nas/nextcloud -t nfs,nfs4 -o SOURCE,TARGET,FSTYPE,OPTIONS
findmnt -rn -M /mnt/nas/backups -t nfs,nfs4 -o SOURCE,TARGET,FSTYPE,OPTIONS
```

Expected sources:

```text
192.168.0.220:/volume1/data
192.168.0.220:/volume1/nextcloud-data
192.168.0.220:/volume1/backups
```

Run the application-mount validator:

```bash
sudo /usr/local/sbin/check-nas-mounts.sh
```

It intentionally does not check the backups export.

## Automount does not activate

Inspect generated units and logs:

```bash
systemctl status mnt-nas-data.automount mnt-nas-data.mount
systemctl status mnt-nas-nextcloud.automount mnt-nas-nextcloud.mount
systemctl status mnt-nas-backups.automount mnt-nas-backups.mount
journalctl -b -u mnt-nas-data.mount
```

Check:

- NAS reachability at `192.168.0.220`
- export paths and client authorization in UGOS Pro
- `nfs-common` installation
- mount-point directories
- `/etc/fstab` syntax
- firewall/routing/VLAN rules
- NFS version compatibility

Use `sudo mount -av` only in a controlled maintenance context: hard mounts and
network failures can block commands.

## `nas-apps.service` fails

```bash
systemctl status nas-apps.service
journalctl -u nas-apps.service -b
sudo /usr/local/sbin/check-nas-mounts.sh
test -f /mnt/nas/nextcloud/data/.ncdata
```

Also confirm all six named containers exist:

```bash
docker inspect jellyfin nextcloud immich_server radarr sonarr bazarr \
  >/dev/null
```

The unit retries failures every 30 seconds. Avoid repeated starts while the NAS
state is unknown.

## NAS becomes unreachable while applications run

With `hard` NFS mounts, processes attempting I/O commonly block and may enter
uninterruptible sleep. Symptoms can include frozen requests, stalled scans,
timeouts, stuck container stops, and hung host commands that traverse the
mount. The containers are not automatically stopped by `nas-apps.service`.

Response:

1. Confirm the incident is NAS/network related without recursively scanning
   the affected mounts.
2. Stop new user/application writes at the edge when possible.
3. Restore NAS/network availability first; hard-mounted I/O may resume.
4. Avoid forced unmounts or container kills until filesystem/database impact
   is understood.
5. After recovery, check application and kernel logs, validate mount sources,
   and run application-level consistency checks.
6. Verify Nextcloud database/file consistency and inspect any download/media
   operations interrupted mid-write.

The exact response to an unrecoverable hard-mount outage can be disruptive and
should be rehearsed during a maintenance window.

## Permissions failures

The `nextcloud-data` export currently maps all users to the NAS administrator.
If Nextcloud reports permission errors, verify UGOS Pro squash/ACL settings and
the effective ownership seen from Ubuntu. Do not solve the issue by applying
recursive world-writable permissions without understanding the data exposure.

For media applications, confirm configured `PUID`/`PGID` and NAS ACLs. Jellyfin
needs read access; qBittorrent/Radarr/Sonarr/Bazarr need the intended write
access.

## Prevent legacy SMB regression

Check rendered mounts before applying Compose changes:

```bash
./shared/compose.sh jellyfin config
./shared/compose.sh torrent config
```

The migrated sources must resolve to `/mnt/nas/data`, not `/mnt/media`.

## Backup timer problems

```bash
systemctl status nextcloud-db-backup.timer
systemctl list-timers nextcloud-db-backup.timer --all
journalctl -u nextcloud-db-backup.service
docker inspect postgres
```

The script requires a running container named `postgres`, a database and role
named `nextcloud`, sufficient local space under `/var/backups`, and working
`pg_dump`/`pg_restore` binaries inside the container.

Do not interpret a successful timer unit alone as backup success. Confirm the
service result, journal completion message, artifact size/timestamp, and
periodic restore tests.
