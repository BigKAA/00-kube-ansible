# AGENTS.md

Этот файл содержит общие инструкции для всех ИИ-агентов, работающих с этим репозиторием.

## 📋 О проекте

Ansible playbook для установки и управления тестовым кластером Kubernetes.
Поддерживает установку single-node и HA кластеров с несколькими control plane нодами.

### Структура проекта

```text
├── ansible.cfg              # Конфигурация Ansible
├── hosts.yaml               # Инвентори хостов
├── hosts-homelab.yaml       # Инвентори для homelab
├── install-cluster.yaml     # Основной playbook установки
├── reset.yaml               # Playbook удаления кластера
├── upgrade.yaml             # Playbook обновления кластера
├── group_vars/
│   └── k8s_cluster/         # Общие переменные кластера
├── roles/
│   ├── prepare-hosts/       # Подготовка хостов (CRI, пакеты)
│   ├── ha/                  # HAProxy + Keepalived для HA
│   ├── master/              # Установка control plane нод
│   ├── second_controls/     # Дополнительные control plane
│   ├── workers/             # Установка worker нод
│   ├── upgrade-cluster/     # Обновление кластера
│   └── utils/               # Утилиты
├── services/                # Сервисные playbooks
├── k3s-playbook/            # Отдельный playbook для k3s (air-gap)
├── files/                   # Статические файлы
└── images/                  # Изображения для документации
```

### Поддерживаемые компоненты

- **Kubernetes**: v1.28 — v1.35.1
- **CRI**: containerd, CRI-O
- **CNI**: Calico (с поддержкой eBPF), Flannel
- **HA**: HAProxy + Keepalived (virtual IP)
- **Утилиты**: Helm, NFS provisioner, cert-manager,
  Metrics Server, MetalLB, Ingress Nginx, ArgoCD

### Протестированные дистрибутивы

| k8s ver | Distributive | CRI | Статус |
| --- | --- | --- | --- |
| 1.31.2 | Rocky Linux 9.4 | containerd 1.7.23 | OK |
| 1.30 | Rocky Linux 8.10 | containerd 1.6.32 | OK |
| 1.30 | Debian 12 | containerd.io 1.7.21 | OK |

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

### Работа с манифестами Kubernetes

1. Всегда проверяйте манифесты на валидность перед применением
2. Используйте `kubectl apply -f <файл>.yaml` для применения
3. Используйте `kubectl get <тип> -o wide` для проверки состояния
4. После применения манифеста — покажите вывод команды

### Playbooks

Основные playbooks:

- `install-cluster.yaml` — установка кластера
- `reset.yaml` — удаление кластера (очищает iptables!)
- `upgrade.yaml` — обновление кластера (последовательно, serial: 1)
- `services/06-utils.yaml` — установка утилит (Helm, NFS, cert-manager и др.)

### Тестирование

При тестировании примеров:

- Всегда используйте детальные версии образов
- Проверяйте ресурсы контейнеров
- Добавляйте health checks для продакшн-подобных сценариев
- Валидируйте labels и selectors

### Важные предупреждения

- `reset.yaml` удаляет **все** нестандартные iptables цепочки
- При HA кластере количество control plane нод должно быть **нечётным**
- Порт HA virtual IP (`ha_cluster_virtual_port`) не должен быть 6443

## 🔄 Обновление информации

Этот файл будет обновляться при необходимости. Агенты должны:

1. Проходить этот файл при первом подключении
2. Отдавать приоритет AGENTS.md для общих правил
