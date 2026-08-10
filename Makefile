# ============================================================
# Kube-Ansible Makefile
# ============================================================
# Использование:
#   make install ENV=homelab
#   make reset ENV=homelab
#   make upgrade ENV=homelab
#
# Переменные:
#   ENV   — окружение (homelab, curs, production). По умолчанию: homelab
#   EXTRA — дополнительные флаги ansible-playbook (например, -v, --limit)
# ============================================================

ENV ?= homelab
EXTRA ?=

INVENTORY := hosts-$(ENV).yaml

ANSIBLE_PLAYBOOK = ansible-playbook -i $(INVENTORY) $(EXTRA)

.PHONY: help install reset upgrade ping debug poweroff check-syntax download-artifacts

help: ## Показать справку
	@echo "Kube-Ansible — Управление Kubernetes кластером"
	@echo ""
	@echo "Использование:"
	@echo "  make install [ENV=homelab] [EXTRA=-v]    — установить кластер (с утилитами и CLI)"
	@echo "  make reset [ENV=homelab]                  — удалить кластер (полная очистка)"
	@echo "  make upgrade [ENV=homelab]                — обновить кластер (ноды + CNI + утилиты)"
	@echo "  make ping [ENV=homelab]                   — проверить доступность хостов"
	@echo "  make debug [ENV=homelab]                  — отладочная информация"
	@echo "  make poweroff [ENV=homelab]               — выключить все ноды"
	@echo "  make check-syntax                         — проверить синтаксис playbook'ов"
	@echo "  make download-artifacts                   — скачать артефакты для offline-установки"
	@echo ""
	@echo "Окружения:"
	@echo "  ENV=homelab  — homelab (по умолчанию)"
	@echo "  ENV=curs     — curs"
	@echo ""
	@echo "Примеры:"
	@echo "  make install ENV=homelab EXTRA=-v"
	@echo "  make install ENV=curs EXTRA='-e k8s_install_mode=offline'"
	@echo "  make upgrade ENV=homelab EXTRA='--limit r1.kryukov.lan'"

install: ## Установить кластер (с утилитами и CLI)
	$(ANSIBLE_PLAYBOOK) install-cluster.yaml $(EXTRA)

reset: ## Удалить кластер (полная очистка)
	$(ANSIBLE_PLAYBOOK) reset.yaml $(EXTRA)

upgrade: ## Обновить кластер (ноды + CNI + утилиты)
	$(ANSIBLE_PLAYBOOK) upgrade.yaml $(EXTRA)

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

download-artifacts: ## Скачать артефакты для offline-установки
	@echo "Скачивание offline-артефактов..."
	./scripts/download-offline-artifacts.sh --output tmp/offline
