# Shared machine configuration

`shared/.env` is the single source of truth for values that apply across
multiple stacks: machine addresses, the local domain, user identity, timezone,
host paths, the shared Docker network, and host port allocations.

The current deployment uses UGREEN NAS NFS mounts for shared media and
Nextcloud user data. Start with `MEDIA_ROOT=/mnt/nas/data` and review the NAS
variables in `.env.example`. The host automount and guarded-start files live
under `../infra/`; see
[`../docs/architecture/nas-integration.md`](../docs/architecture/nas-integration.md).

Service credentials and service-only settings remain in each stack's `.env`.
Both real files are ignored by Git; their `.env.example` counterparts are safe
templates.

For a new machine:

1. Copy `shared/.env.example` to `shared/.env` and edit the machine values.
2. Copy each required `stacks/<name>/.env.example` to
   `stacks/<name>/.env` and enter that service's credentials.
3. Create the external Docker network named by `SHARED_NETWORK`.
4. Run stacks through the shared launcher:

   ```sh
   ./shared/compose.sh homepage up -d
   ```

The launcher loads `shared/.env` first and the selected stack's `.env` second,
so service-specific settings can override shared defaults when necessary.

Dockge receives the equivalent `COMPOSE_ENV_FILES` setting and can resolve the
same two files when it manages stacks.
