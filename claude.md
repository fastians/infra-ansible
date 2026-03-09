# Claude AI Context

Ansible infrastructure automation: monitoring, provisioning, deployment, configuration management.

## Core Capabilities
1. **Provisioning**: Deploy servers from scratch (`site.yml` or `./provision` with provision-* playbooks)
2. **Deployment**: Update applications with branch selection (`./deploy`)
3. **Configuration**: Modular roles for `python_app`, `nginx`, and monitoring
4. **Monitoring**: Dedicated monitor server (brain + probe); Prometheus, Grafana, Loki, Alertmanager, Blackbox Exporter; Promtail and Node Exporter on app servers

## Structure
- `inventories/prod/hosts.ini`: Inventory (backend-server, salome-server, monitoring-server)
- `inventories/prod/group_vars/`: all/all.yml, all/secrets.yml, backend.yml, salome.yml, monitoring.yml
- `roles/`: python_app, nginx, common; prometheus, grafana, loki, alertmanager, blackbox_exporter (monitor); promtail, node_exporter (app servers + monitor)
- `playbooks/`: provision-*.yml, deploy.yml, sync-scripts.yml, manage-services.yml, verify-servers.yml, open-firewall-ports.yml, salome-debug.yml, test-api-docs.yml; app units come from site.yml (single source of truth)
- `docs/`: ARCHITECTURE.md, OPERATIONS.md, CONFIGURATION.md

## Quick Commands
```bash
# Provisioning (short names → provision-*.yml; full names → site.yml --limit)
./provision monitor             # or monitoring-server
./provision backend             # or backend-server
./provision salome              # or salome-server
./provision verify              # Verify all servers
./provision open-firewall-ports

# Deployment
./deploy <service> <branch>     # Deploy application
./sync                         # Push local deployment_scripts/ to servers
./pull                         # Pull deployment scripts from servers to local

# Management
ansible-playbook -i inventories/prod/hosts.ini site.yml
ansible-playbook -i inventories/prod/hosts.ini playbooks/manage-services.yml
```

## Infrastructure Model
- **monitoring-server** (brain + probe): Prometheus, Grafana, Loki, Alertmanager, Blackbox Exporter; Node Exporter, Promtail
- **backend-server** (api.mek-lab.com): **One machine**, three FastAPI apps — backendserver:8000, geoserver:8001, llmserver:8002; Promtail, Node Exporter, Nginx + Certbot
- **salome-server** (salome.mek-lab.com): FastAPI salomeserver:8000; Promtail, Node Exporter, Nginx + Certbot

## Standard Service Names & Ports
- `backendserver` (8000), `geoserver` (8001), `llmserver` (8002), `salomeserver` (8000)

## Documentation
- `README.md`: Entry point & quick reference
- `docs/ARCHITECTURE.md`: Technical overview & data flows
- `docs/OPERATIONS.md`: Provisioning & deployment
- `docs/CONFIGURATION.md`: Secrets, env files, Nginx
