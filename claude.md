# CLAUDE.md - Infra Ansible Engineering Standard

This document is the operating contract for `infra_ansible`.

## Goals

- Keep provisioning deterministic and repeatable.
- Minimize production risk during updates.
- Keep host targeting explicit and auditable.
- Keep secrets out of git-tracked plaintext files.

## Source of Truth

- Inventory: `inventories/prod/hosts.ini`
- Host-specific overrides: `inventories/prod/host_vars/*.yml`
- Shared environment config: `inventories/prod/group_vars/**/*.yml`
- Main orchestration: `site.yml`
- Day-2 wrapper: `./scripts/provision`

## Required Runtime Pattern

- Always run via `./scripts/provision` (or `make`) for routine operations.
- Use `--limit <host>` when targeting a single server.
- Use `--tags` for narrow changes.
- Prefer idempotent re-runs over one-off manual server edits.

Examples:

```bash
./scripts/provision monitoring-server
./scripts/provision backend-server --tags nginx
./scripts/provision verify
```

## Security Standard

- Never commit plaintext credentials/tokens.
- Use environment variables or Ansible Vault for secret values.
- Keep runtime files in `infra_ansible/.ansible/` (gitignored).
- If a secret is exposed, rotate it immediately.

## Inventory and Host Standards

- Keep host connection details in `host_vars/<host>.yml` when possible.
- Use simple host names in `hosts.ini`; avoid long inline connection strings.
- If a host should not be scraped by monitoring, set:

```yaml
monitoring_enabled: false
```

## Monitoring/Alerting Standards

- Prometheus target generation must be inventory-driven.
- Alert rules should identify service and target clearly.
- Alertmanager routing should degrade safely when optional integrations are unset.
- Any false-positive flood should be fixed in config/templates, not muted manually.

## Change Checklist

- [ ] `ansible-inventory --host <host>` resolves expected vars.
- [ ] `./scripts/provision <host> --check` passes for touched area when practical.
- [ ] Real run uses minimal scope (`--limit` / `--tags`).
- [ ] Docs/README updated when behavior changes.
