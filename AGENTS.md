# AGENTS.md

Этот файл содержит общие инструкции для всех ИИ-агентов, работающих с этим репозиторием.

## 📋 О проекте

Ansible playbook для установки и управления тестовым кластером Kubernetes.
Поддерживает установку single-node и HA кластеров с несколькими control plane нодами.

### Структура проекта

```text
├── ansible.cfg              # Конфигурация Ansible
├── hosts.yaml               # Инвентори хостов
├── hosts.template.yaml      # Шаблон инвентори
├── Makefile                 # Удобное управление через make
├── install-cluster.yaml     # Основной playbook установки
├── reset.yaml               # Playbook удаления кластера
├── upgrade.yaml             # Playbook обновления кластера
├── group_vars/
│   ├── all.yaml             # Общие переменные для всех групп
│   ├── all/hooks.yaml       # Точки расширения (pre/post hooks)
│   ├── k8s_cluster/         # Общие переменные кластера
│   └── etcd_nodes/          # Переменные для external etcd нод
├── examples/                # Примеры конфигураций
│   ├── single-node/
│   ├── ha-stacked/
│   └── ha-external-etcd/
├── plans/                   # Планы разработки, тестирования
├── scripts/                 # Скрипты утилит (скачивание offline-артефактов)
├── roles/
│   ├── prepare-hosts/       # Подготовка хостов (CRI, пакеты)
│   ├── ha/                  # HAProxy + Keepalived для HA
│   ├── etcd/                # External etcd кластер
│   ├── master/              # Установка control plane нод
│   ├── second_controls/     # Дополнительные control plane
│   ├── workers/             # Установка worker нод
│   ├── upgrade-cluster/     # Обновление кластера
│   └── utils/               # Утилиты
├── services/                # Сервисные playbooks
├── k3s-playbook/            # Отдельный playbook для k3s (air-gap)
├── files/
│   └── etcd-pki/            # Сертификаты external etcd (генерируются автоматически)
└── images/                  # Изображения для документации
```

### Поддерживаемые компоненты

- **Kubernetes**: v1.28 — v1.36.1
- **CRI**: containerd, CRI-O
- **CNI**: Calico (с поддержкой eBPF), Flannel
- **HA**: HAProxy + Keepalived (virtual IP)
- **etcd**: stacked (встроенный) или external (отдельный кластер).
  Протестированы версии 3.5.x — 3.6.x
- **Утилиты**: Helm, NFS CSI Driver, cert-manager,
  Metrics Server, MetalLB, Ingress Nginx, Envoy Gateway (Gateway API),
  Stakater Reloader, ArgoCD

### Протестированные дистрибутивы

| k8s ver         | Distributive     | CRI                  | Статус |
| --------------- | ---------------- | -------------------- | ------ |
| 1.35.0 → 1.36.1 | Rocky Linux 10.1 | containerd           | OK     |
| 1.31.2          | Rocky Linux 9.4  | containerd 1.7.23    | OK     |
| 1.30            | Rocky Linux 8.10 | containerd 1.6.32    | OK     |
| 1.30            | Debian 12        | containerd.io 1.7.21 | OK     |

## 🗣️ Язык

- Общайтесь на русском языке
- Используйте русский язык в комментариях к коду
- Используйте русский язык в документации и примерах

## 🛠️ Доступные инструменты

- **kubectl** — кластер для тестов и проверки примеров
- **helm** — управление приложениями Kubernetes
- **jq** — работа с JSON
- **markdownlint-cli2** — проверка синтаксиса md файлов
- **docker** — учитывай архитектуру процессора и ОС.
  Разработка ведётся одновременно на
  Windows/amd64 и MacOS/arm
- **ansible-playbook** — основной инструмент развёртывания
- **ssh/ssh-copy-id** — доступ к нодам кластера

## Рекомендации по использованию Bash

## ВАЖНО: Избегайте команд, вызывающих проблемы с буферизацией вывода

- НЕ используйте конвейерную передачу вывода через `head`, `tail`, `less` или `more`
  при мониторинге или проверке вывода команд
- НЕ используйте `|head -n X` или `|tail -n X` для усечения вывода — это вызывает проблемы с буферизацией
- Вместо этого, дайте командам завершиться полностью или используйте флаги `- -max-lines`, если команда их поддерживает
- Для мониторинга логов предпочтительнее читать файлы напрямую, а не передавать их через фильтры

## При проверке вывода команд

- По возможности запускайте команды напрямую без конвейерной передачи
- Если вам необходимо ограничить вывод, используйте флаги, специфичные для команды
  (например, `git log -n 10` вместо `git log | head -10`)
- Избегайте цепочек конвейеров, которые могут привести к бесконечной буферизации вывода

## 💡 Общие советы для агентов

### MCP

Используй доступные MCP:

- serena
- context7
- sequential-thinking

### Чтение и редактирование

1. Перед чтением или редактированием файла — найдите его полный путь
2. Никогда не угадывайте пути к файлам
3. Используйте информацию о структуре проекта для ограничения поиска `grep`
4. После изменения md файлов проверяй синтаксис при помощи markdownlint

### Работа с Ansible

1. Перед запуском playbook проверяй синтаксис:
   `ansible-playbook --check <playbook>.yaml`
2. Используй `--check` (dry-run) перед применением изменений
3. Для отладки используй `-v`, `-vv` или `-vvv`
4. Конфигурация Ansible в `ansible.cfg`

### Коллекции Ansible

Проект требует следующие коллекции Ansible:

- **community.crypto** — работа с SSL/TLS сертификатами
  (генерация CA, CSR, подпись сертификатов для etcd)
- **community.general** — общие модули (modprobe и др.)
- **ansible.posix** — POSIX-модули (sysctl, iptables и др.)
- **kubernetes.core** — работа с Kubernetes (Helm, helm_repository и др.)

Установка:

```bash
ansible-galaxy collection install \
    community.crypto \
    community.general \
    ansible.posix \
    kubernetes.core
```

Коллекции уже установлены в Docker-образе `Dockerfile.ansible`.

Требуемые Python-пакеты (помимо ansible):

```bash
pip install cryptography kubernetes docker
```

### Работа с манифестами Kubernetes

1. Всегда проверяйте манифесты на валидность перед применением
2. Используйте `kubectl apply -f <файл>.yaml` для применения
3. Используйте `kubectl get <тип> -o wide` для проверки состояния
4. После применения манифеста — покажите вывод команды

### Playbooks

Основные playbooks:

- `install-cluster.yaml` — установка кластера
  (включая external etcd при `etcd_mode: external`)
- `reset.yaml` — удаление кластера (очищает iptables!)
- `upgrade.yaml` — обновление кластера (последовательно, serial: 1)
- `services/06-utils.yaml` — установка утилит (Helm, NFS CSI Driver, cert-manager и др.)

Поддерживаются точки расширения (hooks) через `group_vars/all/hooks.yaml`:
pre/post задачи для подготовки хостов.

### Тестирование

При тестировании примеров:

- Всегда используйте детальные версии образов
- Проверяйте ресурсы контейнеров
- Добавляйте health checks для продакшн-подобных сценариев
- Валидируйте labels и selectors

### Git

- НЕ добавляйте `Co-Authored-By` в коммиты — ни от своего имени, ни от имени любых AI-моделей

### Важные предупреждения

- `reset.yaml` удаляет **все** нестандартные iptables цепочки
- При HA кластере количество control plane нод должно быть **нечётным**
- Порт HA virtual IP (`ha_cluster_virtual_port`) не должен быть 6443
- При external etcd количество etcd нод должно быть
  **нечётным** (рекомендуется 3)
- External etcd **не удаляется** при `reset.yaml` по умолчанию
  (установите `reset_etcd: true`)
- Сертификаты external etcd генерируются на Ansible control node
  в `files/etcd-pki/`

## 🔄 Обновление информации

Этот файл будет обновляться при необходимости. Агенты должны:

1. Проходить этот файл при первом подключении
2. Отдавать приоритет AGENTS.md для общих правил
