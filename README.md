# Pluto Enterprise Deploy

This public repository contains the installer, deployment CLI, Compose definition, and customer-facing runbook for Pluto Enterprise. It does not contain the private application source code or application images.

Pluto Enterprise application images are private packages in GitHub Container Registry. Each enterprise receives a read-only package identity from Pluto. The enterprise never needs access to the private `sejati-app` repository.

## Enterprise VPS quick start

Use only the exact published CLI and application versions supplied by Pluto. The versions below
are examples, not a statement that those releases already exist. Do not run these commands until
Pluto confirms both releases are published and approved.

Use a dedicated Ubuntu VPS with Docker Engine and the Docker Compose plugin installed. Download the
pinned installer release, verify it, and install the CLI:

```bash
curl -fL -o install.sh \
  https://github.com/Juxtalabs/pluto-enterprise-deploy/releases/download/v1.0.0/install.sh
curl -fL -o install.sh.sha256 \
  https://github.com/Juxtalabs/pluto-enterprise-deploy/releases/download/v1.0.0/install.sh.sha256
sha256sum --check install.sh.sha256
sudo sh install.sh
```

Install the exact application release provided by Pluto:

```bash
sudo pluto install app-v0.9.25
```

The installer asks for the enterprise dashboard origin, the standalone sync key supplied by Pluto, and the Pluto pull credentials (a GitHub username and a read-only token). It generates the local database and application secrets on the VPS.

For later application updates:

```bash
sudo pluto update app-v0.9.26
```

The persistent configuration is `/opt/pluto/.env`. Back it up together with the database. The GHCR token is stored by Docker under root's Docker configuration and is not written into `/opt/pluto/.env`.

See [the enterprise maintainer runbook](docs/MAINTAINER_RUNBOOK.md) for prerequisites, first installation, updates, backup and restore, troubleshooting, and credential handling.

## Repository roles

- `sejati-app` remains private and is the source of application releases.
- This repository remains public and contains only generic deployment tooling and signed-off release metadata.
- `ghcr.io/juxtalabs/pluto-enterprise-api` and `ghcr.io/juxtalabs/pluto-enterprise-web` remain private.
- Image pulls use one read-only credential supplied by Pluto (a classic GitHub token with only `read:packages`; it grants no repository access).
- Pluto builds each enterprise browser separately with that enterprise's API endpoint.

## CLI commands

```text
pluto install <app-vX.Y.Z>
pluto update <app-vX.Y.Z>
pluto status
pluto doctor
pluto backup [directory]
pluto configure central
pluto registry-check
pluto self-update <vX.Y.Z>
pluto version
```

Application releases and deployment-tool releases use different namespaces: application releases start with `app-v`; CLI releases start with `v`.
