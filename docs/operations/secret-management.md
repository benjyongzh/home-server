# Secret management

## Policy

Real secrets must never be committed. Git tracks `.env.example` contracts;
the live `shared/.env` and `stacks/*/.env` files are ignored. Back up real
values separately in an encrypted password manager or encrypted recovery
bundle with tested access procedures.

Do not paste rendered `docker compose config` output into issues or logs: the
rendered model can contain interpolated secrets.

## Required secret inventory

| Stack/system | Variable or item | Purpose |
|---|---|---|
| Beszel Agent | `BESZEL_AGENT_KEY` | Hub-generated agent public/authentication key material |
| Beszel Agent | `BESZEL_AGENT_TOKEN` | Hub/agent enrollment token |
| Homepage | `HOMEPAGE_VAR_JELLYFIN_KEY` | Jellyfin widget API key |
| Homepage | `HOMEPAGE_VAR_IMMICH_KEY` | Immich widget API key |
| Homepage | `HOMEPAGE_VAR_QBITTORRENT_PASSWORD` | qBittorrent widget password |
| Homepage | `HOMEPAGE_VAR_RADARR_KEY` | Radarr API key |
| Homepage | `HOMEPAGE_VAR_SONARR_KEY` | Sonarr API key |
| Homepage | `HOMEPAGE_VAR_PROWLARR_KEY` | Prowlarr API key |
| Homepage | `HOMEPAGE_VAR_BAZARR_KEY` | Bazarr API key |
| Homepage | `HOMEPAGE_VAR_NEXTCLOUD_PASSWORD` | Nextcloud widget password/app password |
| Homepage | `HOMEPAGE_VAR_BESZEL_PASSWORD` | Beszel widget password |
| Homepage | `HOMEPAGE_VAR_BESZEL_SYSTEM_ID` | Beszel system identifier; treat as sensitive metadata |
| Homepage | `HOMEPAGE_VAR_ADGUARD_PASSWORD` | AdGuard widget password |
| Immich | `DB_PASSWORD` | Immich PostgreSQL password |
| Nextcloud | `POSTGRES_PASSWORD` | Nextcloud database-role password |
| Nextcloud | `REDIS_PASSWORD` | Nextcloud Redis password |
| Nextcloud | `NEXTCLOUD_ADMIN_PASSWORD` | Initial Nextcloud administrator password |
| PostgreSQL | `POSTGRES_PASSWORD` | Shared PostgreSQL administrative password |
| Torrent | `WIREGUARD_PRIVATE_KEY` | ProtonVPN WireGuard private key |
| Former legacy SMB | Old credentials file, if retained locally | The `/mnt/media` fstab entry is commented out; these credentials are not needed by the NAS-backed stacks and must stay out of Git |

Usernames, email addresses, hostnames, LAN/Tailscale addresses, and paths are
not passwords but can be sensitive deployment metadata. Keep real values in
private `.env` files where examples use safe placeholders.

## Secret-bearing backup artifacts

Treat these as secrets even though their filenames do not imply credentials:

- database dumps;
- application config archives;
- qBittorrent config/torrent-state archives;
- Nextcloud migration directories containing `.env` files;
- Docker application state and API-key databases;
- VPN state/configuration;
- rendered Compose output.

Use restrictive permissions, encrypted transport/storage, and an explicit
retention policy. Never use `git add -f` to override ignore rules for them.

## Rotation after exposure

If a secret enters Git:

1. rotate/revoke it immediately;
2. assess GitHub forks, clones, caches, Actions logs, and artifacts;
3. remove it from history with an approved history-rewrite procedure;
4. force-push only after coordinating all clones/collaborators;
5. document the incident without reproducing the secret.

History rewriting does not make a leaked secret safe; rotation is mandatory.

## Repository history audit

On 8 November 2026 all Git refs were scanned. The repository contained one
commit. No current private-environment secret value was found in that history,
and a generic scan found no non-placeholder sensitive assignments. No secret
finding was identified.

This was a targeted local audit; dedicated scanners such as Gitleaks or
TruffleHog were not installed. Run a maintained secret scanner in CI and
enable GitHub secret scanning where available for defense in depth.
