# Ansible playbook для установки Kubernetes кластера

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.28–v1.36-blue)](https://kubernetes.io/releases/)
[![Ansible](https://img.shields.io/badge/Ansible-13.6-green)](https://www.ansible.com/)

Playbook для установки и управления тестовым кластером Kubernetes.
Проверен на наборе [приложений](https://github.com/BigKAA/youtube/tree/master/1.36).

## Возможности

- **Kubernetes** v1.28 — v1.36
- **CRI**: containerd, CRI-O
- **CNI**: Calico (с eBPF), Flannel, Cilium (с eBPF kube-proxy replacement)
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

Playbook автоматически:

- Проверяет доступность etcd-нод (SSH, Python3, порты 2379/2380)
- Устанавливает Docker на etcd-ноды (RedHat и Debian)
- Разворачивает etcd-кластер в контейнере

Версия etcd определяется автоматически по `kube_version`.
Матрица совместимости: [roles/etcd/defaults/main.yaml](roles/etcd/defaults/main.yaml)

#### Подключение к существующему кластеру etcd

Если etcd-кластер уже установлен и управляется отдельно, можно подключиться к нему без повторной установки:

```yaml
# group_vars/k8s_cluster
etcd_mode: "external"
etcd_use_existing: true

# Пути к сертификатам на Ansible control node
etcd_existing_ca_cert: "/path/to/etcd-ca.crt"
etcd_existing_client_cert: "/path/to/apiserver-etcd-client.crt"
etcd_existing_client_key: "/path/to/apiserver-etcd-client.key"
```

При `etcd_use_existing: true` playbook:

1. Проверяет health всех etcd-нод через HTTPS API
2. Проверяет совместимость версии etcd с `kube_version`
3. Распределяет клиентские сертификаты на control plane ноды

Если версия etcd несовместима с Kubernetes — playbook завершится с ошибкой и рекомендацией.

## Конфигурация

### Основные параметры

| Переменная                  | По умолчанию      | Описание                                                         |
| --------------------------- | ----------------- | ---------------------------------------------------------------- |
| `kube_version`              | `1.36.1`          | Версия Kubernetes (1.28 — 1.36.1)                                |
| `cri`                       | `containerd`      | Container Runtime: `containerd` или `crio`                       |
| `cni`                       | `calico`          | Container Network: `calico` или `flannel`                        |
| `service_cidr`              | `10.233.0.0/18`   | CIDR для сервисов                                                |
| `pod_network_cidr`          | `10.233.64.0/18`  | CIDR для подов                                                   |
| `etcd_mode`                 | `stacked`         | Режим etcd: `stacked` или `external`                             |
| `etcd_use_existing`         | `false`           | Подключиться к существующему etcd кластеру                       |
| `etcd_existing_ca_cert`     | `""`              | CA сертификат существующего etcd (при `etcd_use_existing: true`) |
| `etcd_existing_client_cert` | `""`              | Клиентский сертификат apiserver для существующего etcd           |
| `etcd_existing_client_key`  | `""`              | Ключ клиентского сертификата для существующего etcd              |
| `ha_cluster_virtual_ip`     | `192.168.218.130` | Virtual IP для HA (убрать для отключения HA)                     |
| `ha_cluster_virtual_port`   | `7443`            | Порт для HA (не должен быть 6443)                                |

Полный список переменных: [group_vars/k8s_cluster](group_vars/k8s_cluster)

### Выбор CRI

```yaml
cri: containerd # или crio
```

`cri_socket` вычисляется автоматически.

### Выбор CNI

```yaml
cni: calico # calico, flannel или cilium
```

Для Calico с eBPF раскомментируйте `enableBPF: yes` в `group_vars/k8s_cluster`.

Для Cilium с заменой kube-proxy на eBPF-датаплейн установите
`cilium_kube_proxy_replacement: true` в `group_vars/k8s_cluster`.

Подробное описание установки и особенностей Cilium
(включая NodeLocal DNS через CiliumLocalRedirectPolicy) — в [CILIUM.md](CILIUM.md).

## Режимы установки

Playbook поддерживает три режима установки пакетов Kubernetes, управляемых
переменной `k8s_install_mode` в `group_vars/k8s_cluster`.

### Online (по умолчанию)

```yaml
k8s_install_mode: "online"
```

Пакеты Kubernetes (`kubeadm`, `kubelet`, `kubectl`) и CRI (`containerd.io`)
скачиваются из официальных репозиториев `pkgs.k8s.io` и `download.docker.com`.
Образы контейнеров тянутся из `registry.k8s.io`.

**Требование:** стабильный доступ к `pkgs.k8s.io` и `registry.k8s.io`.

### Предзагруженные пакеты (гибридный режим)

Если репозиторий `pkgs.k8s.io` недоступен или медленный (типично для
некоторых регионов), RPM/DEB-пакеты можно скачать заранее и разместить
локально. Этот режим работает **поверх `k8s_install_mode: "online"`** —
образы контейнеров по-прежнему тянутся из сети, а бинарные пакеты — из
локального каталога.

```text
tmp/offline/
└── packages/
    ├── kubeadm-<version>.x86_64.rpm
    ├── kubelet-<version>.x86_64.rpm
    ├── kubectl-<version>.x86_64.rpm
    ├── kubernetes-cni-<version>.x86_64.rpm
    └── cri-tools-<version>.x86_64.rpm
```

Playbook автоматически:

1. Проверяет наличие `*.rpm` / `*.deb` в `tmp/offline/packages/`
2. Копирует их на каждую ноду в `/tmp/k8s-packages/`
3. Устанавливает через `dnf install` / `apt install` из локальных файлов

Если каталог `packages/` пуст — выполняется стандартная установка из
репозиториев.

**Когда использовать:**

- `pkgs.k8s.io` недоступен или отдаёт RPM на низкой скорости
- Нужно установить конкретную версию пакета, отсутствующую в кэше зеркала
- Корпоративный файрвол блокирует `pkgs.k8s.io`, но разрешает `registry.k8s.io`

### Offline (полный air-gap)

```yaml
k8s_install_mode: "offline"
```

Все артефакты (пакеты **и** образы контейнеров) загружаются из локального
каталога `tmp/offline/`. Используется для изолированных сетей без доступа
в интернет.

```text
tmp/offline/
├── packages/          # RPM/DEB пакеты k8s
├── cri/
│   ├── containerd/    # Пакеты containerd
│   └── crio/           # Пакеты CRI-O
├── cni/
│   ├── tigera-operator.yaml
│   └── calico-install.yaml
└── images/
    ├── k8s-images.tar    # Архив образов registry.k8s.io
    └── calico-images.tar # Архив образов Calico
```

Скрипт загрузки: [`scripts/download-offline.sh`](scripts/download-offline.sh)

### Где взять RPM-пакеты

Список пакетов для Kubernetes `<version>` (пример для 1.36.1, x86_64):

| Пакет          | URL                                                                                             |
| -------------- | ----------------------------------------------------------------------------------------------- |
| kubeadm        | `https://pkgs.k8s.io/core:/stable:/v1.36/rpm/x86_64/kubeadm-1.36.1-150500.1.1.x86_64.rpm`       |
| kubelet        | `https://pkgs.k8s.io/core:/stable:/v1.36/rpm/x86_64/kubelet-1.36.1-150500.1.1.x86_64.rpm`       |
| kubectl        | `https://pkgs.k8s.io/core:/stable:/v1.36/rpm/x86_64/kubectl-1.36.1-150500.1.1.x86_64.rpm`       |
| kubernetes-cni | `https://pkgs.k8s.io/core:/stable:/v1.36/rpm/x86_64/kubernetes-cni-1.9.1-150500.1.1.x86_64.rpm` |
| cri-tools      | `https://pkgs.k8s.io/core:/stable:/v1.36/rpm/x86_64/cri-tools-1.36.0-150500.1.1.x86_64.rpm`     |

Полный список доступных версий:
`https://pkgs.k8s.io/core:/stable:/v<MAJOR>.<MINOR>/rpm/x86_64/`

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

| Команда             | Описание                                |
| ------------------- | --------------------------------------- |
| `make install`      | Полный цикл установки кластера          |
| `make reset`        | Удаление кластера                       |
| `make upgrade`      | Обновление кластера                     |
| `make utils`        | Установка утилит                        |
| `make prepare`      | Подготовка хостов (CRI, пакеты, sysctl) |
| `make ha`           | Установка HA (HAProxy + Keepalived)     |
| `make master`       | Установка первого control plane         |
| `make workers`      | Установка worker нод                    |
| `make ping`         | Проверка доступности хостов             |
| `make debug`        | Отладочная информация                   |
| `make poweroff`     | Выключение всех нод                     |
| `make check-syntax` | Проверка синтаксиса playbook'ов         |

Переключайте окружение через `ENV`:

```shell
make install ENV=homelab
make install ENV=production
```

## Сетевые требования

### Порты между нодами

| Порт      | Протокол | Направление                   | Описание                            |
| --------- | -------- | ----------------------------- | ----------------------------------- |
| 6443      | TCP      | Все → Control plane           | Kubernetes API server               |
| 2379–2380 | TCP      | Control plane ↔ Control plane | etcd client и peer                  |
| 10250     | TCP      | Control plane → Все           | Kubelet API                         |
| 10259     | TCP      | Control plane → Control plane | kube-scheduler                      |
| 10257     | TCP      | Control plane → Control plane | kube-controller-manager             |
| 179       | TCP      | Все → Все                     | Calico BGP (при использовании)      |
| 4789      | UDP      | Все → Все                     | Calico VXLAN / Flannel VXLAN        |
| 5473      | TCP      | Все → Все                     | Calico Typha (опционально)          |
| 8472      | UDP      | Все → Все                     | Cilium VXLAN (при cni: cilium)      |
| 4244      | TCP      | Все → Все                     | Cilium agent metrics (Hubble Relay) |
| 4240      | TCP      | Все → Все                     | Cilium health checks (опционально)  |

### External etcd (дополнительно)

| Порт | Протокол | Направление          | Описание    |
| ---- | -------- | -------------------- | ----------- |
| 2379 | TCP      | Control plane → etcd | etcd client |
| 2380 | TCP      | etcd ↔ etcd          | etcd peer   |

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

- Количество etcd нод нечётное
- Порты 2379/2380 открыты между etcd нодами и control plane
- Docker будет установлен автоматически; при ручной установке проверьте: `docker --version`

### Ошибка совместимости версий etcd

При `etcd_use_existing: true` playbook проверяет совместимость. Пример ошибки:

```text
etcd 3.5.9 несовместим с Kubernetes 1.36.1. Требуется etcd >= 3.6.6.
Обновите etcd или используйте совместимую версию Kubernetes.
```

Список поддерживаемых комбинаций: [roles/etcd/defaults/main.yaml](roles/etcd/defaults/main.yaml)

## Совместимость

| k8s ver         | Distributive     | CRI                  | Статус |
| --------------- | ---------------- | -------------------- | ------ |
| 1.35.0 → 1.36.1 | Rocky Linux 10.1 | containerd           | **OK** |
| 1.31.2          | Rocky Linux 9.4  | containerd 1.7.23    | **OK** |
| 1.31            | Rocky Linux 8.10 | containerd 1.6.32    | **OK** |
| 1.30            | Rocky Linux 8.10 | containerd 1.6.32    | **OK** |
| 1.30            | Debian 12        | containerd.io 1.7.21 | **OK** |

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
