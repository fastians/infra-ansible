.PHONY: help monitor backend salome verify check open-firewall deploy seed sync pull syntax

SERVICE ?=
BRANCH ?= main
HOST ?= monitoring-server

help:
	@echo "infra_ansible Make targets"
	@echo ""
	@echo "Provisioning:"
	@echo "  make monitor                # scripts/provision monitoring-server"
	@echo "  make backend                # scripts/provision backend-server"
	@echo "  make salome                 # scripts/provision salome-server"
	@echo "  make verify                 # scripts/provision verify"
	@echo "  make check HOST=backend-server"
	@echo "  make open-firewall          # scripts/provision open-firewall-ports"
	@echo ""
	@echo "Deploy/Seed:"
	@echo "  make deploy SERVICE=backendserver BRANCH=main"
	@echo "  make seed SERVICE=backendserver"
	@echo ""
	@echo "Scripts sync:"
	@echo "  make sync"
	@echo "  make pull"
	@echo ""
	@echo "Validation:"
	@echo "  make syntax                 # ansible-playbook --syntax-check"

monitor:
	bash ./scripts/provision monitoring-server

backend:
	bash ./scripts/provision backend-server

salome:
	bash ./scripts/provision salome-server

verify:
	bash ./scripts/provision verify

check:
	bash ./scripts/provision check "$(HOST)"

open-firewall:
	bash ./scripts/provision open-firewall-ports

deploy:
	@if [ -z "$(SERVICE)" ]; then echo "SERVICE is required"; exit 1; fi
	bash ./scripts/deploy "$(SERVICE)" "$(BRANCH)"

seed:
	@if [ -z "$(SERVICE)" ]; then echo "SERVICE is required"; exit 1; fi
	bash ./scripts/seed "$(SERVICE)"

sync:
	bash ./scripts/sync

pull:
	bash ./scripts/pull

syntax:
	ANSIBLE_LOCAL_TEMP="$(CURDIR)/.ansible/tmp" ANSIBLE_SSH_CONTROL_PATH_DIR="$(CURDIR)/.ansible/cp" ansible-playbook -i inventories/prod/hosts.ini site.yml --syntax-check
