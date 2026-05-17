# Ansible playbook для установки Kubernetes кластера

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.28–v1.36-blue)](https://kubernetes.io/releases/)
[![Ansible](https://img.shields.io/badge/Ansible-13.6-green)](https://www.ansible.com/)

Playbook для установки и управления тестовым кластером Kubernetes.
Проверен на наборе [приложений](https://github.com/BigKAA/youtube/tree/master/1.31).

## Возможности

- **Kubernetes** v1.28 — v1.36
- **CRI**: containerd, CRI-O
- **CNI**: Calico (с eBPF), Flannel
- **HA**: HAProxy + Keepalived (virtual IP)
- **etcd**: stacked (встроенный) или external (отдельный кластер)
- **Утилиты**: Helm, NFS CSI Driver, cert-manager, Metrics Server,
  MetalLB, Ingress Nginx, Envoy Gateway (Gateway API), Stakater Reloader, ArgoCD
- **Управление**: установка, обновление, удаление кластера

## Быстрый старт

### 1. Подготовка

**Требования к Ansible control node:**

- Python 3.10+
- Ansible 13.6 (ansible-core 2.20.5)
- SSH-ключ для доступа к нодам

**Требования к нодам кластера:**

- Минимум 2 CPU, 2 GB RAM (control plane)
- Минимум 2 CPU, 4 GB RAM (worker)
- 20 GB свободного диска
- Доступ в интернет (для online-режима)
- Открытые порты между нодами (см. [Сетевые требования](#сетевые-требования))

### 2. Установка Ansible

```shell
python3 -m venv venv
. venv/bin/activate
pip3 install ansible==13.6.0
```

Или используйте Docker-образ (ansible-core 2.20.5, предустановленные коллекции):

```shell
docker build -f Dockerfile.ansible -t ansible-custom:13.6 .
alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/home/ansible/.ssh -v $(pwd):/workspace ansible-custom:13.6 ansible-playbook"
```

### 3. Настройка SSH

```shell
ssh-keygen
ssh-copy-id root@<IP-адрес-ноды>
```

### 4. Конфигурация

Скопируйте шаблон инвентори и настройте под своё окружение:

```shell
cp hosts.template.yaml hosts.yaml
```

Отредактируйте `hosts.yaml` — укажите IP-адреса нод.
Отредактируйте `group_vars/k8s_cluster` — установите версию Kubernetes и другие параметры.

### 5. Запуск

```shell
ansible-playbook install-cluster.yaml
```

Или через Makefile:

```shell
make install
```

## Установка

### Single-node кластер

Одна control plane нода, без HA. Минимальная конфигурация для тестирования.

В `hosts.yaml` укажите один хост в группе `k8s_masters`:

```yaml
k8s_masters:
  hosts:
    master1:
      ansible_host: 192.168.1.10
k8s_workers:
  hosts:
    worker1:
      ansible_host: 192.168.1.11
k8s_cluster:
  children:
    k8s_masters:
    k8s_workers:
```

```shell
ansible-playbook install-cluster.yaml
```

### HA кластер (несколько control plane)

**Важно:** количество control plane нод должно быть **нечётным** (1, 3, 5...).

В `hosts.yaml` укажите 3+ хоста в группе `k8s_masters`:

```yaml
k8s_masters:
  hosts:
    master1:
      ansible_host: 192.168.1.10
    master2:
      ansible_host: 192.168.1.11
    master3:
      ansible_host: 192.168.1.12
```

Для HA доступа к API настройте virtual IP в `group_vars/k8s_cluster`:

```yaml
ha_cluster_virtual_ip: 192.168.1.100
ha_cluster_virtual_port: 7443
```

![ha cluster](images/ha_cluster.jpg)

### External etcd

По умолчанию используется встроенный (stacked) etcd. Для выноса etcd на отдельные ноды:

1. В `group_vars/k8s_cluster` установите `etcd_mode: "external"`
2. В `hosts.yaml` добавьте группу `etcd_nodes` с **нечётным** количеством нод (рекомендуется 3):

```yaml
etcd_nodes:
  hosts:
    etcd1:
      ansible_host: 192.168.1.30
      etcd_short_name: etcd1
    etcd2:
      ansible_host: 192.168.1.31
      etcd_short_name: etcd2
    etcd3:
      ansible_host: 192.168.1.32
      etcd_short_name: etcd3
```

Версия etcd определяется автоматически по `kube_version`.
Матрица совместимости: [roles/etcd/defaults/main.yaml](roles/etcd/defaults/main.yaml)

## Конфигурация

### Основные параметры

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `kube_version` | `1.36.1` | Версия Kubernetes (1.28 — 1.36.1) |
| `cri` | `containerd` | Container Runtime: `containerd` или `crio` |
| `cni` | `calico` | Container Network: `calico` или `flannel` |
| `service_cidr` | `10.233.0.0/18` | CIDR для сервисов |
| `pod_network_cidr` | `10.233.64.0/18` | CIDR для подов |
| `etcd_mode` | `stacked` | Режим etcd: `stacked` или `external` |
| `ha_cluster_virtual_ip` | `192.168.218.130` | Virtual IP для HA (убрать для отключения HA) |
| `ha_cluster_virtual_port` | `7443` | Порт для HA (не должен быть 6443) |

Полный список переменных: [group_vars/k8s_cluster](group_vars/k8s_cluster)

### Выбор CRI

```yaml
cri: containerd  # или crio
```

`cri_socket` вычисляется автоматически.

### Выбор CNI

```yaml
cni: calico  # или flannel
```

Для Calico с eBPF раскомментируйте `enableBPF: yes` в `group_vars/k8s_cluster`.

## Управление кластером

### Установка

```shell
ansible-playbook install-cluster.yaml
# или
make install
```

### Удаление

```shell
ansible-playbook reset.yaml
# или
make reset
```

> **Внимание:** `reset.yaml` удаляет **все** нестандартные iptables цепочки.
> External etcd **не удаляется** по умолчанию. Для очистки установите `reset_etcd: true`.

### Обновление

Измените `kube_version` в `group_vars/k8s_cluster` и запустите:

```shell
ansible-playbook upgrade.yaml
# или
make upgrade
```

Обновление выполняется последовательно (serial: 1) — по одной ноде за раз.

### Утилиты

```shell
ansible-playbook services/06-utils.yaml
# или
make utils
```

Устанавливает: Helm, NFS CSI Driver, cert-manager, Metrics Server, MetalLB,
Ingress Nginx, Envoy Gateway, Stakater Reloader, ArgoCD.

### Сервисные playbook'и

| Команда | Описание |
|---------|----------|
| `make install` | Полный цикл установки кластера |
| `make reset` | Удаление кластера |
| `make upgrade` | Обновление кластера |
| `make utils` | Установка утилит |
| `make prepare` | Подготовка хостов (CRI, пакеты, sysctl) |
| `make ha` | Установка HA (HAProxy + Keepalived) |
| `make master` | Установка первого control plane |
| `make workers` | Установка worker нод |
| `make ping` | Проверка доступности хостов |
| `make debug` | Отладочная информация |
| `make poweroff` | Выключение всех нод |
| `make check-syntax` | Проверка синтаксиса playbook'ов |

Переключайте окружение через `ENV`:

```shell
make install ENV=homelab
make install ENV=production
```

## Сетевые требования

### Порты между нодами

| Порт | Протокол | Направление | Описание |
|------|----------|-------------|----------|
| 6443 | TCP | Все → Control plane | Kubernetes API server |
| 2379–2380 | TCP | Control plane ↔ Control plane | etcd client и peer |
| 10250 | TCP | Control plane → Все | Kubelet API |
| 10259 | TCP | Control plane → Control plane | kube-scheduler |
| 10257 | TCP | Control plane → Control plane | kube-controller-manager |
| 179 | TCP | Все → Все | Calico BGP (при использовании) |
| 4789 | UDP | Все → Все | Calico VXLAN |
| 5473 | TCP | Все → Все | Calico Typha (опционально) |

### External etcd (дополнительно)

| Порт | Протокол | Направление | Описание |
|------|----------|-------------|----------|
| 2379 | TCP | Control plane → etcd | etcd client |
| 2380 | TCP | etcd ↔ etcd | etcd peer |

## Примеры конфигураций

В директории `examples/` приведены готовые конфигурации для типичных сценариев:

- [`examples/single-node/`](examples/single-node/) — 1 master + 1 worker, без HA
- [`examples/ha-stacked/`](examples/ha-stacked/) — 3 masters + stacked etcd
- [`examples/ha-external-etcd/`](examples/ha-external-etcd/) — 3 masters + 3 external etcd

Также доступен шаблон инвентори: [`hosts.template.yaml`](hosts.template.yaml)

## Troubleshooting

### Playbook падает с ошибкой SSH

Проверьте доступность хостов:

```shell
make ping
```

Убедитесь, что SSH-ключ скопирован на все ноды.

### kubeadm init завершается с ошибкой

Проверьте, что порт 6443 не занят:

```shell
ss -tlnp | grep 6443
```

Проверьте, что swap отключён:

```shell
swapon --show
```

### Ноды не подключаются к кластеру

Проверьте, что все ноды доступны по сети и время синхронизировано:

```shell
# На каждой ноде
chronyc tracking  # для Rocky Linux
ntpq -p           # для Debian
```

### External etcd не запускается

Убедитесь, что:

- Docker установлен на etcd нодах
- Количество etcd нод нечётное
- Порты 2379/2380 открыты между etcd нодами и control plane

## Совместимость

| k8s ver | Distributive | CRI | Статус |
|---------|-------------|-----|--------|
| 1.35.0 → 1.36.1 | Rocky Linux 10.1 | containerd | **OK** |
| 1.31.2 | Rocky Linux 9.4 | containerd 1.7.23 | **OK** |
| 1.31 | Rocky Linux 8.10 | containerd 1.6.32 | **OK** |
| 1.30 | Rocky Linux 8.10 | containerd 1.6.32 | **OK** |
| 1.30 | Debian 12 | containerd.io 1.7.21 | **OK** |

## Структура проекта

```text
├── ansible.cfg              # Конфигурация Ansible
├── hosts.yaml               # Инвентори хостов
├── install-cluster.yaml     # Основной playbook установки
├── reset.yaml               # Playbook удаления кластера
├── upgrade.yaml             # Playbook обновления кластера
├── Makefile                 # Удобное управление через make
├── hosts.template.yaml      # Шаблон инвентори
├── group_vars/
│   ├── all.yaml             # Общие переменные для всех групп
│   ├── all/hooks.yaml       # Точки расширения (pre/post hooks)
│   ├── k8s_cluster/         # Конфигурация кластера
│   └── etcd_nodes/          # Переменные для external etcd
├── examples/                # Примеры конфигураций
│   ├── single-node/
│   ├── ha-stacked/
│   └── ha-external-etcd/
├── scripts/                 # Скрипты утилит (offline-артефакты)
├── roles/
│   ├── prepare-hosts/       # Подготовка хостов (CRI, пакеты)
│   ├── ha/                  # HAProxy + Keepalived
│   ├── etcd/                # External etcd кластер
│   ├── master/              # Установка control plane
│   ├── second_controls/     # Дополнительные control plane
│   ├── workers/             # Установка worker нод
│   ├── upgrade-cluster/     # Обновление кластера
│   └── utils/               # Утилиты
└── services/                # Сервисные playbook'и
```
