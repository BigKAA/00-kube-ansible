# Ansible playbook для установки Kubernetes кластера

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35+-blue)](https://kubernetes.io/releases/)
[![Ansible](https://img.shields.io/badge/Ansible-13.6-green)](https://www.ansible.com/)
[![Distributives](https://img.shields.io/badge/OS-RedHat%20family-red)](https://rockylinux.org/)

Playbook для установки и управления тестовым кластером Kubernetes
на RedHat-семействе дистрибутивов (Rocky/Alma/RHEL).

## Возможности

- **Kubernetes** v1.35+ (stacked etcd)
- **CRI**: containerd
- **CNI**: Flannel, Cilium (с kube-proxy replacement через eBPF)
- **HA**: HAProxy + Keepalived (virtual IP для API server)
- **LoadBalancer**: Cilium L2-анонсы (при cni=cilium) или MetalLB (при cni=flannel)
- **Утилиты** (ставятся автоматически на первую control node):
  Helm, NFS CSI Driver, cert-manager, Metrics Server,
  Envoy Gateway (Gateway API), Stakater Reloader, ArgoCD
- **CLI на первой control node**: kubectl, helm, cilium CLI, yq, jq, stern
- **Offline-установка**: полный air-gap через предзагруженные артефакты
- **Управление**: установка, обновление, полное удаление кластера

## Быстрый старт

### 1. Подготовка

**Требования к Ansible control node:**

- Python 3.10+
- Ansible 13.6 (ansible-core 2.20.5)
- SSH-ключ для доступа к нодам
- Docker, helm, git, yq (для offline-подготовки артефактов)

**Требования к нодам кластера:**

- RedHat-семейство: Rocky Linux 9/10, AlmaLinux, RHEL
- Минимум 2 CPU, 2 GB RAM (control plane)
- Минимум 2 CPU, 4 GB RAM (worker)
- 20 GB свободного диска
- Доступ в интернет (для online-режима)
- Открытые порты между нодами (см. [Сетевые требования](#сетевые-требования))

### 2. Установка Ansible

```shell
python3 -m venv venv
. venv/bin/activate
pip3 install ansible==13.6.0 cryptography kubernetes docker passlib jmespath
ansible-galaxy collection install community.crypto community.general ansible.posix kubernetes.core
```

Или используйте Docker-образ (предустановленные коллекции и Python-модули):

```shell
docker build -f Dockerfile.ansible -t ansible-custom:13.6 .
alias ansible-playbook="docker run -ti --rm -u root -e HOME=/root -v ~/.ssh:/root/.ssh:ro -v $(pwd):/workspace ansible-custom:13.6 ansible-playbook"
```

### 3. Настройка SSH

```shell
ssh-keygen
ssh-copy-id artur@<IP-адрес-ноды>
```

### 4. Конфигурация

Скопируйте шаблон инвентори и настройте под своё окружение:

```shell
cp hosts.template.yaml hosts.yaml
```

Отредактируйте `hosts.yaml` — укажите IP-адреса нод.
Отредактируйте `group_vars/k8s_cluster` — установите версию Kubernetes, CNI,
утилиты и параметры окружения.

### 5. Запуск

`make install` устанавливает кластер, утилиты и CLI одной командой:

```shell
make install              # ENV=homelab → hosts-homelab.yaml
make install ENV=curs     # → hosts-curs.yaml
```

Готовые примеры инвентори лежат в [`examples/`](examples/):

```shell
ansible-playbook -i examples/single-node/hosts.yaml install-cluster.yaml
ansible-playbook -i examples/ha-stacked/hosts.yaml install-cluster.yaml
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

### HA кластер (несколько control plane)

Несколько control plane нод с HAProxy + Keepalived (virtual IP).
**Количество control plane нод должно быть нечётным** (1, 3, 5...).

В `group_vars/k8s_cluster` укажите виртуальный IP:

```yaml
ha_cluster_virtual_ip: 192.168.1.100
ha_cluster_virtual_port: 7443   # НЕ 6443
```

## Конфигурация

Все параметры — в `group_vars/k8s_cluster`.
Canonical-источник версий — [`scripts/versions.yaml`](scripts/versions.yaml).

### Основные параметры

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `kube_version` | `1.36.2` | Версия Kubernetes (>= 1.35) |
| `cni` | `cilium` | CNI: `cilium` или `flannel` |
| `imageRepository` | `registry.k8s.io` | Registry образов Kubernetes |
| `pod_network_cidr` | `10.233.64.0/18` | Подсеть подов |
| `service_cidr` | `10.233.0.0/18` | Подсеть сервисов |

### CNI

```yaml
# Cilium с kube-proxy replacement (eBPF) — по умолчанию
cni: cilium
cilium_kube_proxy_replacement: true
cilium_nodelocaldns: true

# или Flannel
cni: flannel
```

Подробнее о Cilium — в [CILIUM.md](CILIUM.md).

### LoadBalancer (для сервисов типа LoadBalancer)

Выбор зависит от CNI:

- **Cilium** (`cni: cilium` + `cilium_kube_proxy_replacement: true`):
  L2-анонсы Cilium (замена MetalLB). IP-пул задаётся через
  `CiliumLoadBalancerIPPool`. MetalLB не устанавливается.
- **Flannel** (`cni: flannel`): MetalLB. Включается через `metallbEnable: true`.

Пул IP-адресов — в переменной `loadBalancerAddresses` (для обоих вариантов).

### HA

HA включается заданием виртуального IP:

```yaml
ha_cluster_virtual_ip: 192.168.1.100
ha_cluster_virtual_port: 7443   # НЕ 6443
```

Для single-node уберите `ha_cluster_virtual_ip`.

## Режимы установки

### Online (по умолчанию)

```yaml
k8s_install_mode: "online"
```

Все пакеты и образы скачиваются из интернет-репозиториев.

### Предзагруженные пакеты (гибридный режим)

Если RPM-пакеты Kubernetes уже лежат в `tmp/offline/packages/`,
они будут установлены локально, без обращения к интернет-репозиторию.
Это полезно при медленном/нестабильном канале.

Подготовка пакетов:

```shell
make download-artifacts
```

### Offline (полный air-gap)

```yaml
k8s_install_mode: "offline"
```

Все артефакты берутся из `tmp/offline/`. Подготовка:

```shell
make download-artifacts
make install ENV=curs EXTRA='-e "k8s_install_mode=offline"'
```

Скрипт `scripts/download_offline_artifacts.py` скачивает:
- Kubernetes RPM (kubeadm, kubelet, kubectl, cri-tools, kubernetes-cni)
- Containerd RPM
- Образы контейнеров (отдельные `.tar` на каждый образ: `images/k8s/`, `images/cilium/`)
- Helm-чарты утилит и Cilium
- CLI-инструменты (helm, cilium CLI, yq, stern) — обе архитектуры
- Helm-плагин helm-diff

Версии читаются из [`scripts/versions.yaml`](scripts/versions.yaml).

## Управление кластером

```shell
make install ENV=curs     # установить кластер + утилиты + CLI
make reset ENV=curs       # полное удаление (кластер + утилиты + CNI + пакеты)
make upgrade ENV=curs     # обновление k8s + CNI + утилит (serial: 1)
make ping ENV=curs        # проверка доступности хостов
make check-syntax         # проверка синтаксиса playbook'ов
make download-artifacts   # скачать offline-артефакты
```

### Структура playbooks

- `install-cluster.yaml` — установка кластера (prepare → HA → master → workers → utils)
- `reset.yaml` — полное удаление (2 play: утилиты+CNI → сброс нод)
- `upgrade.yaml` — обновление (2 play: ноды serial:1 → CNI+utils)

## Сетевые требования

### Порты между нодами

| Порт | Протокол | Назначение |
|------|----------|------------|
| 6443 | TCP | Kubernetes API server |
| 2379-2380 | TCP | etcd (внутри control plane) |
| 10250 | TCP | kubelet API |
| 10259 | TCP | kube-scheduler |
| 10257 | TCP | kube-controller-manager |
| 30000-32767 | TCP | NodePort сервисы |
| 4789 | UDP | Flannel VXLAN |
| 8472 | UDP | Cilium VXLAN |
| 4240 | TCP | Cilium health checks |

## Структура проекта

```text
├── install-cluster.yaml     # Установка кластера + утилиты + CLI
├── reset.yaml               # Полное удаление кластера
├── upgrade.yaml             # Обновление кластера
├── Makefile                 # Управление через make
├── ansible.cfg              # Конфигурация Ansible
├── Dockerfile.ansible       # Docker-образ с Ansible
├── hosts.template.yaml      # Шаблон инвентори
├── group_vars/
│   ├── all.yaml             # Общие переменные (kube_version)
│   ├── all/hooks.yaml       # Точки расширения (pre/post hooks)
│   └── k8s_cluster          # Переменные кластера
├── examples/                # Примеры: single-node, ha-stacked
├── scripts/
│   ├── versions.yaml        # Canonical-источник версий
│   └── download_offline_artifacts.py  # Скачивание offline-артефактов
├── roles/
│   ├── prepare-hosts/       # Подготовка хостов (containerd, пакеты)
│   ├── ha/                  # HAProxy + Keepalived
│   ├── master/              # Первая control plane (kubeadm init + CNI)
│   ├── second_controls/     # Дополнительные control plane
│   ├── workers/             # Worker ноды
│   ├── upgrade-cluster/     # Обновление кластера
│   └── utils/               # Утилиты и CLI (10 task-файлов)
└── services/                # Служебные playbooks (ping, debug, poweroff)
```

## Troubleshooting

### Playbook падает с ошибкой SSH

Проверьте:
- SSH-ключ скопирован: `ssh-copy-id artur@<IP>`
- Нода доступна: `ssh artur@<IP> hostname`
- `host_key_checking = False` в `ansible.cfg`

### kubeadm init завершается с ошибкой

- Проверьте, что swap отключён (`swapoff -a`)
- Проверьте модули ядра: `lsmod | grep -E 'br_netfilter|overlay'`
- Проверьте sysctl: `sysctl net.bridge.bridge-nf-call-iptables`
- Проверьте порты: `ss -tlnp | grep 6443`

### Ноды не подключаются к кластеру

- Проверьте CNI: `kubectl get pods -n kube-system | grep -E 'cilium|flannel'`
- При Cilium: `cilium status` на ноде
- Проверьте подключение к API server: `nc -zv <API_IP> 6443`

## Совместимость

| Kubernetes | Дистрибутив | CRI | Статус |
|------------|-------------|-----|--------|
| 1.35–1.36 | Rocky Linux 10 | containerd | OK |
| 1.35 | Rocky Linux 9 | containerd | OK |
