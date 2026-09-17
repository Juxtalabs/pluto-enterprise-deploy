# Pluto Enterprise server runbook

This runbook is for the company developer or infrastructure maintainer who operates Pluto Enterprise on the company's own VPS. Pluto does not need SSH access to the VPS.

The normal server flow never clones, forks, or downloads the private application source repository. The VPS pulls two private, versioned container images from GitHub Container Registry (GHCR) and uses the public `Juxtalabs/pluto-enterprise-deploy` installer.

## Responsibilities

Pluto's side:

- Creates the company, company administrator, standalone installation, and entitlements in the central dashboard.
- Gives the maintainer the standalone sync key and the pull credential through a secure channel.
- Publishes approved server releases as private API and dashboard images.
- Maintains one shared read-only registry credential (a classic GitHub token with only `read:packages`) and supplies its username and token to each maintainer.
- Supplies the approved deployment CLI version and application release, such as `v1.0.0` and `app-v0.9.25`.
- Builds the company-specific browser with the company's Pluto Enterprise HTTPS origin compiled into it.
- Publishes browser updates in that company's separate public browser-release repository.

The Enterprise company's side:

- Owns the VPS, operating system, firewall, DNS, TLS reverse proxy, sudo access, monitoring, and backups.
- Stores the Pluto-supplied pull credential in the company's approved secrets manager.
- Runs the documented `pluto` commands during an approved maintenance window.
- Protects `/opt/pluto/.env`, the database backups, and root's Docker registry credential.
- Tests restoration and keeps the handoff record current.

## What is public and what is private

| Item | Access |
|---|---|
| `Juxtalabs/pluto-enterprise-deploy` | Public installer and deployment tooling; no application source or credentials |
| `ghcr.io/juxtalabs/pluto-enterprise-api` | Private image; approved package readers only |
| `ghcr.io/juxtalabs/pluto-enterprise-web` | Private image; approved package readers only |
| Private application repository | Pluto only; not cloned to the Enterprise VPS |
| Company browser-release repository | Public release artifacts for that company's browser updater |

Private images prevent normal source-repository access. They cannot make runtime artifacts secret from a root operator on a customer-controlled VPS. Root can inspect containers, application files, memory, the database, and all local secrets. A company that cannot accept that self-hosting trust boundary should use the SaaS option.

## Information Pluto sends before installation

Do not start until Pluto has supplied all of these:

- Approved deployment CLI release, for example `v1.0.0`.
- Approved application release, for example `app-v0.9.25`.
- Exact public dashboard origin, for example `https://exam.company.example`.
- The standalone sync key: a single long string generated in the central dashboard for this
  installation. Keep it secret.
- The Pluto pull credential: a GitHub username and a read-only token (see below).
- The company administrator credentials through an agreed secure channel.

The sync key must come from a **New key (standalone — their own server)** installation. Never use a shared SaaS key for an Enterprise VPS.

Only continue after Pluto confirms that the named CLI and application releases are published and
approved. The version numbers in this runbook are examples. A GitHub `404` at one of the example
release URLs means the release is not available; do not substitute an unapproved version.

## VPS requirements

Use a current x86-64 Ubuntu LTS VPS. A dedicated VPS is the recommended topology; a shared
host also works as long as the default local port 18080 is free, or an alternative port is
chosen at the installer prompt.

| Resource | Minimum |
|---|---:|
| CPU | 2 vCPU |
| RAM | 4 GiB |
| SSD | 40 GB |
| Swap | 2 GiB |

These are provisioning floors, not a capacity promise. Load-test the company's expected simultaneous sessions, event volume, retention, exports, and backup window.

Required software and connectivity:

- Docker Engine and the Docker Compose plugin.
- `curl`, `jq`, `openssl`, `gzip`, `sha256sum`, `flock`, `awk`, `sed`, `grep`, `sort`, `df`,
  `stat`, `mktemp`, `install`, `head`, and `tr`.
- UTC/NTP-synchronized system time.
- Outbound TCP 443 to `github.com`, `objects.githubusercontent.com`, `ghcr.io`, GitHub's container storage endpoints, and `sejati-admin.juxtalabs.io`.
- Outbound TCP 443 to `auth.docker.io`, `registry-1.docker.io`, and Docker Hub's download CDN so the first install can pull PostgreSQL and Redis.
- Public DNS and HTTPS termination for the exact dashboard origin.
- A reverse proxy or tunnel that sends the public origin to `http://127.0.0.1:18080`.

The first supported deployment uses the Docker project `pluto`, network `pluto-net`, subnet `10.88.0.0/24`, volumes `pluto-postgres-data` and `pluto-redis-data`, and host binding `127.0.0.1:18080`. The installer refuses known collisions. Do not use Docker prune commands to make room.

Before downloading the installer, run this prerequisite gate:

```bash
uname -s
uname -m
sudo -v
sudo docker version
sudo docker compose version
for command in curl jq openssl gzip sha256sum flock awk sed grep sort df stat mktemp install head tr; do
  command -v "$command" || exit 1
done
```

Expected operating system and architecture are `Linux` and `x86_64`. Every other command must
succeed. Stop and have the company's infrastructure maintainer install or repair the missing
prerequisite before continuing.

## The Pluto pull credential

The VPS pulls the two private image packages with one read-only credential that Pluto creates and maintains. The company does not need a GitHub account.

Pluto supplies two values through a secure channel:

- The GitHub username that owns the credential.
- The classic GitHub token with only the `read:packages` scope.

The token can pull the two private image packages:

```text
ghcr.io/juxtalabs/pluto-enterprise-api
ghcr.io/juxtalabs/pluto-enterprise-web
```

It grants no repository access. It can never clone, read, or list any source repository, including the private application repository. Do not request or expect wider scopes such as `repo`, `write:packages`, or `delete:packages`.

Store both values in the company's approved password or secrets manager. Record the token expiry date that Pluto states. Never put the token itself in a ticket, runbook, shell command, screenshot, or handoff document.

### Where the token lives on the VPS

During `pluto install`, the token is entered through a hidden prompt and passed to `docker login ghcr.io` over standard input. It is not written to `/opt/pluto/.env` and is not passed into any application container.

Docker stores the login for the root account, normally in `/root/.docker/config.json` or through the configured Docker credential helper. A root operator can read or use that credential. Restrict sudo and root access accordingly.

## Install the deployment CLI once

Use the exact CLI version supplied by Pluto. The example below installs `v1.0.1`:

```bash
curl -fLO \
  https://github.com/Juxtalabs/pluto-enterprise-deploy/releases/download/v1.0.2/install.sh
curl -fLO \
  https://github.com/Juxtalabs/pluto-enterprise-deploy/releases/download/v1.0.2/install.sh.sha256
sha256sum --check install.sh.sha256
sudo sh install.sh
pluto version
```

Expected final lines:

```text
Pluto deployment CLI v1.0.2 is installed.
Next: sudo pluto install app-vX.Y.Z
pluto 1.0.1
```

The bootstrap installs:

```text
/usr/local/bin/pluto
/opt/pluto/compose.yaml
/opt/pluto/release.schema.json
```

It does not configure or start the application. This bootstrap is normally run once. Use `sudo pluto self-update vX.Y.Z` only when Pluto says an application release requires a newer CLI.

## Install the application

Run the exact application release supplied by Pluto:

```bash
sudo pluto install app-v0.9.25
```

The command asks for:

1. The exact public HTTPS origin, with no path or trailing slash.
2. The standalone sync key. Input is hidden; paste only the key value Pluto supplied.
3. The GHCR username supplied by Pluto.
4. The GHCR token. Input is hidden.

If TCP port 18080 is already in use on the VPS, the installer asks for an alternative local
port instead of failing. Enter any free port (for example 18081) and use that same port in
your reverse proxy route (section "DNS and HTTPS").

The central endpoint and the minimum browser version are fixed by the installer. It rejects a malformed sync key and image manifests outside Pluto's two allowlisted package names.

It then:

1. Downloads and checksum-verifies the public release manifest.
2. Checks the fixed Docker project, port, volumes, network, and subnet for known collisions.
3. Authenticates Docker to GHCR.
4. Generates independent database, JWT, password-encryption, and face-binding secrets locally.
5. Writes `/opt/pluto/.env` as `root:root` with mode `0600`.
6. Uses the staged sync key to make an authenticated central grant request without exposing the key in process arguments or a response file.
7. Pulls the private API and dashboard images by immutable digest.
8. Starts PostgreSQL 17 and Redis 7.
9. Refuses a restored database whose company IDs differ from the companies assigned to the key.
10. Runs `alembic upgrade head` from the new API image before starting the application.
11. Confirms the expected database revision.
12. Starts and health-checks the API and dashboard.
13. Requires the locally verified active company-grant set to match the companies assigned to that key.
14. Records the installed release only after acceptance succeeds.

The command does not build source on the VPS, does not contact the SaaS server, and does not change the customer's browser.

The local `http://127.0.0.1:18080/ping` check is a hard installation gate. The public-origin check
is a warning because DNS and TLS may still be in progress during first installation. Finish DNS and
reverse-proxy configuration, then require `sudo pluto doctor` to pass before handoff.

## DNS and HTTPS

Create the DNS record for the exact origin supplied to the installer. Terminate TLS at the company's reverse proxy or approved tunnel, and send requests to the local bind shown by `sudo pluto status`:

```text
http://127.0.0.1:18080    # default; the installer prints it if it differs
```

Minimal nginx upstream shape:

```nginx
server {
    listen 443 ssl;
    server_name exam.company.example;

    location / {
        proxy_pass http://127.0.0.1:18080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

TLS certificate paths and HTTP-to-HTTPS redirection depend on the company's proxy. Do not expose PostgreSQL, Redis, or the API container directly to the internet.

Verify the public path:

```bash
curl -i https://exam.company.example/ping
```

Expected status: `204 No Content`.

## Configuration and secrets

The complete application environment lives here:

```text
/opt/pluto/.env
```

Expected protection:

```bash
sudo stat -c '%U:%G %a %n' /opt/pluto/.env
```

Expected output:

```text
root:root 600 /opt/pluto/.env
```

The file contains:

- Digest-pinned API and dashboard image names.
- The public dashboard origin and Docker network settings.
- Locally generated `POSTGRES_PASSWORD`, `JWT_SECRET`, `PASSWORD_ENC_KEY`, and `FACE_BINDING_KEY`.
- `API_PROFILE=operational`.
- `PUBLIC_APP_URL`, `CORS_ORIGINS`, `TRUSTED_PROXY_IPS`, and `MIN_CLIENT_VERSION`.
- The fixed central endpoint and the standalone sync key supplied by Pluto.
- Empty central-only signing values. The Enterprise VPS never receives central's private signing key.

A root operator can inspect the file when necessary:

```bash
sudo cat /opt/pluto/.env
```

Do not copy its output into chat, screenshots, tickets, or logs. Do not manually `source` it. The file is Compose input, not a shell script.

The GHCR token is deliberately not in this file. It belongs to Docker's root registry configuration.

## Routine status and diagnostics

Show the installed release, database revision, non-secret endpoints, last backup, and container state:

```bash
sudo pluto status
```

Run read-only diagnostics:

```bash
sudo pluto doctor
```

`doctor` checks required commands, Docker, Compose, `.env` ownership and mode, Compose validity,
local and public dashboard reachability, central HTTPS reachability, disk space, and service state.
It does not restart or repair services.

Test private-package access without printing the token:

```bash
sudo pluto registry-check
```

## Back up the database and `.env` together

The database and `/opt/pluto/.env` form one recovery point:

- `PASSWORD_ENC_KEY` in `.env` is required to reveal credentials encrypted in that database.
- `FACE_BINDING_KEY`, JWT configuration, central sync identity, and the database password also belong to that installation.
- A database-only backup is incomplete.
- An `.env`-only backup contains secrets but no operational data.

Use an encrypted, access-controlled, off-host destination mounted on the VPS. The destination must
already exist and be writable. The CLI refuses a missing destination instead of creating a local
directory that only looks like a mounted backup target.

```bash
sudo pluto backup /secure/off-host/pluto
```

The command creates a timestamped directory containing:

```text
database.sql.gz
.env
metadata.json
SHA256SUMS
```

It fails if `pg_dump` fails, tests the compressed dump, checks for the expected schema marker, copies `.env` with mode `0600`, and writes checksums. It never deletes older backups.

Verify a copied bundle:

```bash
sudo sh -c 'cd /secure/off-host/pluto/pluto-app-v0.9.25-YYYYMMDDTHHMMSSZ && sha256sum --check SHA256SUMS'
```

The bundle contains production credentials. Encrypt the destination, limit access, include it in the company's retention policy, and test restoration before handoff and at the agreed interval.

## Restore test on an isolated VPS

Never test restoration over the live production database. Use a clean isolated VPS with no existing Pluto Docker project, volumes, network, or port binding.

1. Install the same or a compatible `pluto` CLI release.
2. Copy the complete recovery bundle to the test VPS.
3. Verify `SHA256SUMS` inside the bundle.
4. Restore the environment with root-only permissions:

```bash
sudo install -o root -g root -m 0600 /path/to/backup/.env /opt/pluto/.env
```

5. Authenticate root's Docker client to GHCR. This form prompts for the token without putting it in shell history:

```bash
sudo docker login ghcr.io --username <username-pluto-supplied>
```

Use the `read:packages` token as the password.

6. Start only the empty PostgreSQL and Redis services:

```bash
sudo docker compose \
  --project-directory /opt/pluto \
  --env-file /opt/pluto/.env \
  -f /opt/pluto/compose.yaml \
  up -d --wait postgres redis
```

7. Restore the dump into the clean database:

```bash
sudo gzip -cd /path/to/backup/database.sql.gz | sudo docker compose \
  --project-directory /opt/pluto \
  --env-file /opt/pluto/.env \
  -f /opt/pluto/compose.yaml \
  exec -T postgres psql -U pluto -d pluto
```

8. Resume installation using the release named in `metadata.json`:

```bash
sudo pluto install app-v0.9.25
```

Because `.env` already exists and no completed installation is recorded, `pluto install` uses the
restored configuration, refuses a central company-set mismatch, verifies migrations, starts the
application, and confirms the local active grant set.

9. Verify admin login, one browser login, reports, and encrypted credential reveal. Record the restore-test date and operator, but no secrets.

A live production restore is a destructive incident procedure. Stop and coordinate it with Pluto and the company's database owner; the CLI does not automatically overwrite a live database or run Alembic downgrade.

## Update the Enterprise server

Pluto sends a new approved application release. During the agreed maintenance window, run one command:

```bash
sudo pluto update app-v0.9.26
```

The updater:

1. Refuses the same release, an older release, or a malformed release.
2. Downloads and validates the new public manifest.
3. Authenticates the configured key directly with central and requires the local company-grant IDs
   to match the companies assigned to that key.
4. Pulls both private application images by digest while the current application remains selected.
5. Creates and verifies a database plus `.env` backup.
6. Runs the new image's Alembic migration out of band.
7. Confirms the exact migration revision declared by the release.
8. Starts the new API and dashboard and waits for health checks.
9. Requires local `/ping` and the matching locally verified active company-grant set. It warns if
   public `/ping` is unavailable; `pluto doctor` must pass after DNS and TLS are ready.
10. Records the previous and current release only after success.

Migrations are included in the API image. The maintainer does not download migration files separately. Migrations never run automatically in normal API startup.

If migration fails, the existing application remains selected and the command reports the verified
backup path. If the new application fails health or central-grant checks after migration, the CLI
redeploys the previous application images and runs Compose plus local health checks. It reports
whether that application rollback succeeded or failed. It does not reverse the database migration.
Pluto releases must therefore keep live migrations backward-compatible with the previous
application.

The updater never runs Docker prune, never deletes old images, never deletes backups, and never automatically restores a database.

## Renew the pull credential

An expired or revoked token does not stop already-running containers, but it blocks image pulls and updates.

Ask Pluto for a replacement token. Then log in interactively as root:

```bash
sudo docker login ghcr.io --username <username-pluto-supplied>
```

Paste the replacement token as the password, and verify both packages:

```bash
sudo pluto registry-check
```

Pluto revokes the old token and states the new expiry date for the handoff record.

## Rotate or replace the central sync key

Pluto rotates or reveals the standalone key in the central dashboard and sends the new key value securely. On the VPS, run:

```bash
sudo pluto configure central
```

Paste the new sync key; input is hidden. The command authenticates the new key directly with
central, and requires its company set to match the current local database before restarting the
API. It then checks local health and the locally verified active grant set before replacing
`/opt/pluto/.env`. If verification fails, it restores the previous API configuration and leaves
the production `.env` unchanged.

Take a fresh off-host backup after a successful key change.

## Update the deployment CLI

Application releases declare their minimum compatible CLI. Update only to the version supplied by Pluto:

```bash
sudo pluto self-update v1.1.0
pluto version
```

The command downloads the pinned public installer and checksum. It replaces the CLI and generic Compose/schema files but preserves `/opt/pluto/.env`, release state, database volumes, and backups.

## Browser delivery is separate

Pluto builds the browser; the Enterprise maintainer does not build it on the VPS.

For each company, Pluto's side compiles:

- The company's exact Enterprise HTTPS origin.
- The company's browser brand and identity.
- The company's public browser-release repository.

The browser updater reads only that company's release line. A server release and a browser release are independent unless Pluto changes the policy contract or raises `MIN_CLIENT_VERSION`. Test a real browser update from version N to N+1; installing N+1 fresh does not prove auto-update.

## Common failures

### `denied` or `unauthorized` while pulling an image

- Confirm the username and token are exactly the values Pluto supplied, and that the token has not expired.
- Run `sudo docker login ghcr.io --username <username-pluto-supplied>` with a fresh token, then `sudo pluto registry-check`.
- If it still fails, ask Pluto for a replacement token.

### No active grant after installation

- Confirm Pluto created a standalone installation for the correct company.
- Confirm the complete sync key value was pasted.
- Confirm outbound HTTPS to central works with `sudo pluto doctor`.
- Ask Pluto to confirm the installation is active and has current entitlements.
- Rerun the same `sudo pluto install app-vX.Y.Z` only when the first installation is incomplete. Once a current release exists, use `pluto update`.

### Public `/ping` fails but containers are healthy

Check DNS, the TLS certificate, firewall rules, and the reverse proxy route to `127.0.0.1:18080`. The CLI does not install or change the host proxy.

### Port, network, volume, or Compose-project collision

Stop and identify the owner. Pluto does not adopt, rename, stop, or remove unrelated Docker resources. The first supported topology is a dedicated VPS. A shared-host design needs a separately approved configuration.

### Migration failure during update

Do not run `alembic downgrade`, delete the database volume, or rerun random Compose commands. Keep the backup path printed by `pluto update`, collect `sudo pluto status` and relevant service logs, and contact Pluto.

## Handoff record

Keep one access-controlled record with:

- Company name/code, central company ID, installation ID, and installation label.
- Administrator recipient and confirmation of secure credential delivery, but not the password.
- Public origin, DNS/TLS owner, reverse-proxy route, VPS owner, and named maintainer.
- Pluto pull-credential username and its expiry date, but not the token.
- Confirmation that the pull credential is limited to `read:packages` with no repository access.
- Deployment CLI version, application release, API/web image digests, and Alembic revision.
- Compose project, host binding, network, subnet, and volume names.
- Statement that secrets live at `/opt/pluto/.env`, owned by root with mode `0600`.
- Backup destination, encryption/retention owner, last successful backup, and last tested restore.
- Maintenance window, monitoring owner, and escalation contact.
- Browser brand, compiled API origin, public release repository, installed version, and N to N+1 update evidence.
- Known warnings and the approved incident recovery procedure.

Never record the company-admin password, standalone sync key, GHCR token, database password, JWT secret, password-encryption key, or face-binding key in the handoff document.

## Security rules

- Never clone or fork the private application repository to an Enterprise VPS.
- Never put credentials on a command line or in shell history.
- Never give the pull credential scopes beyond `read:packages`, such as `repo`, `write:packages`, or `delete:packages`.
- Never copy `/opt/pluto/.env` without encrypting and access-controlling the destination.
- Never separate the database backup from its matching `.env`.
- Never run Docker prune as part of installation, update, or recovery.
- Never run an automatic Alembic downgrade.
- Never expose PostgreSQL, Redis, or the API container directly to the internet.
- Never reuse or move an application release tag.
- Never publish a screenshot containing a live sync key.
