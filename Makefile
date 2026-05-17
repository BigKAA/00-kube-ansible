# ============================================================
# Kube-Ansible Makefile
# ============================================================
# Использование:
#   make install ENV=homelab
#   make reset ENV=homelab
#   make upgrade ENV=homelab
#   make utils ENV=homelab
#
# Переменные:
#   ENV   — окружение (homelab, production). По умолчанию: homelab
#   EXTRA — дополнительные флаги ansible-playbook (например, -v, --limit)
# ============================================================

ENV ?= homelab
EXTRA ?=

INVENTORY := hosts-$(ENV).yaml

ANSIBLE_PLAYBOOK = ansible-playbook -i $(INVENTORY) $(EXTRA)

.PHONY: help install reset upgrade utils prepare ha master workers ping debug poweroff check-syntax

help: ## Показать справку
	@echo "Kube-Ansible — Управление Kubernetes кластером"
	@echo ""
	@echo "Использование:"
	@echo "  make install [ENV=homelab] [EXTRA=-v]    — установить кластер"
	@echo "  make reset [ENV=homelab]                  — удалить кластер"
	@echo "  make upgrade [ENV=homelab]                — обновить кластер"
	@echo "  make utils [ENV=homelab]                  — установить утилиты (Helm, cert-manager, ...)"
	@echo "  make prepare [ENV=homelab]                — подготовить хосты"
	@echo "  make ha [ENV=homelab]                     — установить HA (HAProxy + Keepalived)"
	@echo "  make master [ENV=homelab]                 — установить первый control plane"
	@echo "  make workers [ENV=homelab]                — установить worker ноды"
	@echo "  make ping [ENV=homelab]                   — проверить доступность хостов"
	@echo "  make debug [ENV=homelab]                  — отладочная информация"
	@echo "  make poweroff [ENV=homelab]               — выключить все ноды"
	@echo "  make check-syntax                         — проверить синтаксис playbook'ов"
	@echo ""
	@echo "Окружения:"
	@echo "  ENV=homelab     — homelab (по умолчанию)"
	@echo "  ENV=production  — production"
	@echo ""
	@echo "Примеры:"
	@echo "  make install ENV=homelab EXTRA=-v"
	@echo "  make reset ENV=production"
	@echo "  make upgrade ENV=homelab EXTRA='--limit r1.kryukov.lan'"

install: ## Установить кластер
	$(ANSIBLE_PLAYBOOK) install-cluster.yaml $(EXTRA)

reset: ## Удалить кластер
	$(ANSIBLE_PLAYBOOK) reset.yaml $(EXTRA)

upgrade: ## Обновить кластер
	$(ANSIBLE_PLAYBOOK) upgrade.yaml $(EXTRA)

utils: ## Установить утилиты (Helm, cert-manager, MetalLB, ...)
	$(ANSIBLE_PLAYBOOK) services/06-utils.yaml $(EXTRA)

prepare: ## Подготовить хосты (CRI, пакеты, sysctl)
	$(ANSIBLE_PLAYBOOK) services/01-prepare-hosts.yaml $(EXTRA)

ha: ## Установить HA (HAProxy + Keepalived)
	$(ANSIBLE_PLAYBOOK) services/02-install-ha.yaml $(EXTRA)

master: ## Установить первый control plane
	$(ANSIBLE_PLAYBOOK) services/03-install-1st-control.yaml $(EXTRA)

workers: ## Установить worker ноды
	$(ANSIBLE_PLAYBOOK) services/05-install-workers.yaml $(EXTRA)

ping: ## Проверить доступность хостов
	$(ANSIBLE_PLAYBOOK) services/ping.yaml $(EXTRA)

debug: ## Отладочная информация
	$(ANSIBLE_PLAYBOOK) services/debug.yaml $(EXTRA)

poweroff: ## Выключить все ноды
	$(ANSIBLE_PLAYBOOK) services/poweroff.yaml $(EXTRA)

check-syntax: ## Проверить синтаксис playbook'ов
	ansible-playbook --syntax-check -i $(INVENTORY) install-cluster.yaml
	ansible-playbook --syntax-check -i $(INVENTORY) reset.yaml
	ansible-playbook --syntax-check -i $(INVENTORY) upgrade.yaml
