# Infrastructure Automation

A professional-grade infrastructure-as-code (IaC) project designed to automate the provisioning, configuration, and monitoring of high-performance lab environments. This repository serves as a showcase for modern DevOps practices, focusing on scalability, security, and observable systems.

## One-by-one setup (manual order)

Run by server name, one at a time; test, then the next:

```bash
./provision monitoring-server   # Monitor (Prometheus, Grafana, Loki, Alertmanager, Blackbox)
./provision backend-server      # Backend: one machine, three FastAPI apps (backendserver, geoserver, llmserver)
./provision salome-server      # Salome app server
```

Or use short names to run provision playbooks: `./provision monitor`, `./provision backend`, `./provision salome`. Use `./provision verify` to check all servers; `./provision help` for more.

### Vars from file (no long command line)

Use **`-e @extra_vars.yml`** to load vars (Telegram token, skip_apt_upgrade, etc.). **Do not use `-i extra_vars.yml`** — `-i` is for inventory and will break.

```bash
# Correct: -e = extra vars, -i = inventory (optional if in ansible.cfg)
ansible-playbook -i inventories/prod/hosts.ini site.yml --limit monitoring-server -e @extra_vars.yml
```

Edit `extra_vars.yml` (from `extra_vars.example.yml` if needed); it’s in `.gitignore` so it is not committed.

### Run only what changed (faster)

Use `--tags` so only the role you changed runs. **Alerts only (no Grafana):**

```bash
ansible-playbook -i inventories/prod/hosts.ini site.yml --limit monitoring-server -e @extra_vars.yml --tags alerts
```

Single role:

```bash
ansible-playbook -i inventories/prod/hosts.ini site.yml --limit monitoring-server -e @extra_vars.yml --tags alertmanager
ansible-playbook -i inventories/prod/hosts.ini site.yml --limit monitoring-server --tags prometheus
# Avoid re-running Grafana unless you changed it:
ansible-playbook -i inventories/prod/hosts.ini site.yml --limit monitoring-server --tags grafana
```

Tags: `alerts` (prometheus + alertmanager), `common`, `node_exporter`, `prometheus`, `loki`, `grafana`, `alertmanager`, `blackbox_exporter`.

## 🌟 Key Features

- **Automated Provisioning**: One-touch deployment for server clusters using Ansible (`./provision`, `site.yml`).
- **Microservices Orchestration**: Backend server runs three FastAPI apps (ports 8000, 8001, 8002); Salome runs one (8000).
- **Enterprise Monitoring**: Dedicated monitor server with **Prometheus**, **Grafana**, **Loki**, **Alertmanager**, **Blackbox Exporter**; **Promtail** and **Node Exporter** on app servers.
- **Secure by Design**: Secret management, automated SSL (Certbot), Nginx reverse proxy.
- **Scalable Architecture**: Modular roles; multi-environment inventories (prod, sample).

## 🛠️ Technology Stack

- **Infrastructure**: Ansible, Linux (Ubuntu/Debian)
- **Networking**: Nginx, Certbot, SSL/TLS
- **Monitoring**: Prometheus, Grafana, Loki, Promtail, Alertmanager, Blackbox Exporter, Node Exporter
- **Application**: Python (FastAPI), PostgreSQL
- **Security**: SSH key management, Ansible Vault, secret scan protection

## 📈 System Impact

- **Repeatable Setup**: Scripted server and app deployment.
- **Centralized Visibility**: One dashboard for metrics and logs (Grafana → Prometheus/Loki).
- **Developer Efficiency**: Simple replication and management via `./provision` and `./deploy`.

## Operations & reliability

| Doc | Purpose |
|-----|--------|
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Provisioning, deployment, monitoring, maintenance |
| [docs/portfolio.md](docs/portfolio.md) | Monitoring links (Grafana, Prometheus, etc.) |
| [docs/ALERTING.md](docs/ALERTING.md) | Alerts, Telegram setup, troubleshooting |
| [docs/RUNBOOKS.md](docs/RUNBOOKS.md) | **Per-alert runbooks** (what to do when an alert fires) |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | **Deploy and rollback** (safety) |
| [docs/INCIDENTS.md](docs/INCIDENTS.md) | **Incident process and ownership** |
| [docs/RESILIENCE.md](docs/RESILIENCE.md) | **Resilience patterns** (health checks, retries, SLO) |

Grafana includes an **SLO overview** dashboard (7d availability, error-budget visibility) after provisioning the monitor.

---

*For AI/automation context (structure, commands, service names), see [CLAUDE.md](CLAUDE.md). For operations and architecture, see `docs/`.*
