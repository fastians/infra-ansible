.PHONY: help monitor backend salome verify check open-firewall deploy seed sync pull syntax

SERVICE ?=
BRANCH ?= main
HOST ?= monitoring-server

help:
	@echo "infra_ansible Make targets"
	@echo ""
	@echo "Provisioning:"
	@echo "  make monitor                # ./provision monitoring-server"
	@echo "  make backend                # ./provision backend-server"
	@echo "  make salome                 # ./provision salome-server"
	@echo "  make verify                 # ./provision verify"
	@echo "  make check HOST=backend-server"
	@echo "  make open-firewall          # ./provision open-firewall-ports"
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
	./provision monitoring-server

backend:
	./provision backend-server

salome:
	./provision salome-server

verify:
	./provision verify

check:
	./provision check "$(HOST)"

open-firewall:
	./provision open-firewall-ports

deploy:
	@if [ -z "$(SERVICE)" ]; then echo "SERVICE is required"; exit 1; fi
	./deploy "$(SERVICE)" "$(BRANCH)"

seed:
	@if [ -z "$(SERVICE)" ]; then echo "SERVICE is required"; exit 1; fi
	./seed "$(SERVICE)"

sync:
	./sync

pull:
	./pull

syntax:
	ANSIBLE_LOCAL_TEMP="$(CURDIR)/.ansible/tmp" ANSIBLE_SSH_CONTROL_PATH_DIR="$(CURDIR)/.ansible/cp" ansible-playbook -i inventories/prod/hosts.ini site.yml --syntax-check
