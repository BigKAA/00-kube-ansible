# План тестирования: Развёртывание и обновление кластера Kubernetes с external etcd

## 1. Инфраструктура тестирования

### 1.1. Целевые машины (hosts-homelab.yaml)

| Роль | Хост | IP | ОС |
|------|------|----|----------------------|
| Control Plane 1 | r1.kryukov.lan | 192.168.218.131 | Rocky Linux 10 |
| Control Plane 2 | r2.kryukov.lan | 192.168.218.132 | Rocky Linux 10 |
| Control Plane 3 | r3.kryukov.lan | 192.168.218.133 | Rocky Linux 10 |
| Worker 1 | r4.kryukov.lan | 192.168.218.134 | Rocky Linux 10 |
| Worker 2 | r5.kryukov.lan | 192.168.218.135 | Rocky Linux 10 |
| etcd 1 | e1.kryukov.lan | 192.168.218.141 | Rocky Linux 10 |
| etcd 2 | e2.kryukov.lan | 192.168.218.142 | Rocky Linux 10 |
| etcd 3 | e3.kryukov.lan | 192.168.218.143 | Rocky Linux 10 |

### 1.2. Сетевые параметры

| Параметр | Значение |
|----------|----------|
| Kubernetes API Virtual IP | 192.168.218.130 |
| HA Virtual Port | 7443 |
| Service CIDR | 10.233.0.0/18 |
| Pod Network CIDR | 10.233.64.0/18 |

### 1.3. Ansible Control Node

| Параметр | Значение |
|----------|----------|
| Платформа | MacOS (Orbstack) |
| Ansible | В Docker-контейнере |
| Рабочая директория | /Users/arturkryukov/Projects/personal/00-kube-ansible |
| Директория для RPM | `tmp/rpms/` (локальная) |

### 1.4. Доступ SSH

| Параметр | Значение |
|----------|----------|
| Пользователь | `artur` |
| Аутентификация | По SSH-ключу |
| sudo | Без пароля (`NOPASSWD`) |
| Ansible become | `--become-user=root --become` |

Пример проверки доступа:

```bash
ssh artur@e1.kryukov.lan "sudo whoami"  # должно вернуть root
```

---

## 2. Подготовка к тестированию

### 2.1. Предварительные требования

- [ ] Убедиться, что SSH-ключ добавлен для пользователя `artur` на всех целевых машинах
- [ ] Проверить доступ: `ssh artur@e1.kryukov.lan "sudo whoami"` (должно вернуть `root`)
- [ ] Убедиться, что на всех целевых машинах есть Python 3 (`/usr/bin/python3`)
- [ ] Убедиться, что Docker запущен на MacOS (Orbstack)
- [ ] Подготовить Docker-образ с Ansible для запуска playbooks

**Результаты проверки (2026-05-16):**

- SSH: все 8 нод доступны, sudo работает без пароля
- ОС: Rocky Linux 10.1 (Red Quartz) на всех нодах
- Python: 3.12.12 (`/usr/bin/python3`)
- Docker: v29.4.0 (Orbstack, MacOS)

> **Примечание:** Pre-flight проверки теперь встроены в `install-cluster.yaml`
> и запускаются автоматически (проверка SSH, Python3, портов, версий, CRI/CNI).

### 2.2. Настройка переменных для external etcd

Передать переменные через `-e` при запуске playbook:

```bash
ansible-playbook -i hosts-homelab.yaml install-cluster.yaml \
  -e "kube_version=1.35.0" \
  -e "etcd_mode=external" \
  -e "k8s_install_mode=offline"
```

Или использовать Makefile:

```bash
make install ENV=homelab EXTRA='-e "kube_version=1.35.0" -e "etcd_mode=external" -e "k8s_install_mode=offline"'
```

> **Примечание:** `cri_socket` и `crio_version` вычисляются автоматически
> на основе переменной `cri` и `kube_version`.

### 2.3. Подготовка offline-пакетов (RPM)

Поскольку пакеты Kubernetes недоступны с целевых машин, необходимо скачать их
заранее на Ansible Control Node (MacOS) и разместить в `tmp/rpms/`.

> **Важно:** Целевые машины работают на **Rocky Linux 10** (EL10).
> Пакеты должны быть собраны именно для этой платформы.
> Репозиторий k8s на `pkgs.k8s.io` использует openSUSE Build Service,
> и пакеты для EL10 могут иметь специфическое именование (release tag).

#### 2.3.1. Скачать пакеты Kubernetes v1.35 для Rocky Linux 10

> **СТАТУС: ✅ ВЫПОЛНЕНО (2026-05-16)**
>
> Скачанные файлы:
>
> - `tmp/rpms/kubeadm-1.35.0.rpm` (12.5 MB)
> - `tmp/rpms/kubelet-1.35.0.rpm` (13.0 MB)
> - `tmp/rpms/kubectl-1.35.0.rpm` (11.6 MB)
>
> Источник: `https://pkgs.k8s.io/core:/stable:/v1.35/rpm/x86_64/`
> Именование: SUSE OBS (`150500.1.1`) — совместимо с EL10
> Проверка зависимостей: ✅ совместимы (glibc, iptables, kubernetes-cni)

#### 2.3.2. Скачать пакеты для upgrade (v1.36) для Rocky Linux 10

> **СТАТУС: ✅ ВЫПОЛНЕНО (2026-05-16)**
>
> Скачанные файлы:
>
> - `tmp/rpms/kubeadm-1.36.1.rpm` (12.7 MB)
> - `tmp/rpms/kubelet-1.36.1.rpm` (13.5 MB)
> - `tmp/rpms/kubectl-1.36.1.rpm` (11.9 MB)
>
> Источник: `https://pkgs.k8s.io/core:/stable:/v1.36/rpm/x86_64/`
> Именование: SUSE OBS (`150500.1.1`) — совместимо с EL10

#### 2.3.3. Скачать дополнительные зависимости для Rocky Linux 10

Пакеты Kubernetes могут требовать дополнительные зависимости, которые также
необходимо скачать, если целевые машины не имеют доступа к интернету:

```bash
# Проверить зависимости скачанных пакетов
rpm -qp --requires tmp/rpms/kubelet-1.35.0.rpm
rpm -qp --requires tmp/rpms/kubeadm-1.35.0.rpm

# Типичные зависимости для kubelet:
# - kubernetes-cni >= 0.8.7
# - conntrack
# Если зависимости недоступны на целевых машинах — скачать их тоже
```

> **ПРИМЕЧАНИЕ:** Текущий код upgrade ожидает пакеты в `/tmp/k8s-rpms/` на целевых машинах
> с конкретным именованием. Необходимо адаптировать playbook под фактическое
> именование пакетов для Rocky Linux 10.

### 2.4. Подготовка Docker-контейнера с Ansible

#### 2.4.1. Структура директории `tmp/`

Директория `tmp/` используется для хранения данных, которые должны сохраняться
между запусками Docker-контейнера:

```text
tmp/
├── rpms/                  # Скачанные RPM-пакеты k8s (persistent)
│   ├── kubeadm-1.35.0.rpm
│   ├── kubelet-1.35.0.rpm
│   ├── kubectl-1.35.0.rpm
│   ├── kubeadm-1.36.1.rpm
│   ├── kubelet-1.36.1.rpm
│   └── kubectl-1.36.1.rpm
├── ansible-cache/         # Ansible facts, кэш (persistent)
├── ssh/                   # SSH-ключи и known_hosts (persistent)
└── logs/                  # Логи выполнения (persistent)
```

Создать структуру:

```bash
mkdir -p tmp/{rpms,ansible-cache,ssh,logs}
```

#### 2.4.2. Сборка Docker-образа

В репозитории уже есть готовый `Dockerfile.ansible` с предустановленными
коллекциями Ansible (community.crypto, community.general, ansible.posix,
kubernetes.core) и Python-модулями (cryptography, kubernetes, docker).

```bash
# Собрать образ
docker build -f Dockerfile.ansible -t ansible-custom:13.6 .
```

#### 2.4.3. Алиасы для команд Ansible

Чтобы не писать каждый раз полную команду `docker run`, определите алиасы:

```bash
alias ansible-playbook="docker run -ti --rm \
  -v ~/.ssh:/home/ansible/.ssh \
  -v $(pwd):/workspace \
  ansible-custom:13.6 ansible-playbook"

alias ansible="docker run -ti --rm \
  -v ~/.ssh:/home/ansible/.ssh \
  -v $(pwd):/workspace \
  ansible-custom:13.6 ansible"
```

> **Важно:** Все команды `ansible` и `ansible-playbook` в этом документе
> предполагают, что алиасы определены. SSH-ключи для подключения к
> `artur@<host>` должны быть доступны в `~/.ssh/` на хост-машине.
> Коллекции Ansible предустановлены в образе — монтировать
> `~/.ansible` не требуется.

---

## 3. Этап 1: Первичная установка кластера Kubernetes v1.35

### 3.1. Конфигурация

`ansible.cfg` уже настроен для работы через пользователя `artur`:

```ini
[defaults]
# inventory задаётся через Makefile или ключ -i
inventory = ./hosts-homelab.yaml
roles_path = ./roles
host_key_checking = False

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
```

**Pre-flight проверки** запускаются автоматически перед установкой:

- Проверка SSH connectivity
- Проверка Python3 на remote хостах
- Проверка занятости портов (6443, HA virtual port)
- Проверка нечётности control plane и etcd нод
- Проверка `kube_version` в диапазоне 1.28–1.36.1
- Проверка допустимых значений CRI и CNI

```bash
# Установить версию Kubernetes
export KUBE_VERSION="1.35.0"

# Проверить доступ ко всем нодам
ansible -i hosts-homelab.yaml all -u artur -m ping

# Проверить синтаксис playbook (dry-run)
ansible-playbook -i hosts-homelab.yaml install-cluster.yaml \
  -u artur --become \
  -e "kube_version=${KUBE_VERSION}" \
  -e "etcd_mode=external" \
  -e "k8s_install_mode=offline" \
  --check -vv
```

### 3.2. Запуск установки

**Через Makefile (рекомендуется):**

```bash
export KUBE_VERSION="1.35.0"

# Установка кластера с external etcd (offline)
make install ENV=homelab EXTRA='-e "kube_version=${KUBE_VERSION}" -e "etcd_mode=external" -e "k8s_install_mode=offline"' -vv

# Или с verbose выводом
make install ENV=homelab EXTRA='-e "kube_version=${KUBE_VERSION}" -e "etcd_mode=external" -e "k8s_install_mode=offline"' VERBOSE=2
```

**Напрямую через ansible-playbook:**

```bash
ansible-playbook -i hosts-homelab.yaml install-cluster.yaml \
  -u artur --become \
  -e "kube_version=${KUBE_VERSION}" \
  -e "etcd_mode=external" \
  -e "k8s_install_mode=offline" \
  -vv
```

> **Примечание:** Pre-flight проверки запускаются автоматически в начале playbook.
> Они проверят SSH, Python3, порты, версии, CRI/CNI перед установкой.

### 3.3. Проверки после установки

#### 3.3.1. Проверка external etcd кластера

```bash
# На любой etcd ноде (e1) через SSH:
ssh artur@e1.kryukov.lan "sudo docker exec etcd etcdctl \
  --cacert=/etc/etcd/pki/ca.crt \
  --cert=/etc/etcd/pki/server.crt \
  --key=/etc/etcd/pki/server.key \
  --endpoints=https://192.168.218.141:2379,https://192.168.218.142:2379,https://192.168.218.143:2379 \
  endpoint health"

# Проверить список членов
ssh artur@e1.kryukov.lan "sudo docker exec etcd etcdctl \
  --cacert=/etc/etcd/pki/ca.crt \
  --cert=/etc/etcd/pki/server.crt \
  --key=/etc/etcd/pki/server.key \
  --endpoints=https://192.168.218.141:2379 \
  member list -w table"

# Проверить статус endpoints
ssh artur@e1.kryukov.lan "sudo docker exec etcd etcdctl \
  --cacert=/etc/etcd/pki/ca.crt \
  --cert=/etc/etcd/pki/server.crt \
  --key=/etc/etcd/pki/server.key \
  --endpoints=https://192.168.218.141:2379 \
  endpoint status -w table"
```

**Критерии успеха:**

- [ ] Все 3 ноды etcd в состоянии `healthy`
- [ ] Кластер имеет 3 члена
- [ ] Версия etcd соответствует матрице совместимости для v1.35 (`registry.k8s.io/etcd:3.5.24-0`)

#### 3.3.2. Проверка Kubernetes кластера

```bash
# На первой control plane ноде (r1) через SSH:
ssh artur@r1.kryukov.lan "sudo kubectl get nodes -o wide"

# Проверить статус всех подов в kube-system
ssh artur@r1.kryukov.lan "sudo kubectl get pods -n kube-system -o wide"

# Проверить компоненты control plane
ssh artur@r1.kryukov.lan "sudo kubectl get pods -n kube-system | grep -E 'apiserver|controller|scheduler|etcd|proxy'"

# Проверить версию кластера
ssh artur@r1.kryukov.lan "sudo kubectl version -o yaml"

# Проверить конфигурацию cluster-info
ssh artur@r1.kryukov.lan "sudo kubectl cluster-info"
```

> **Совет:** Для удобства можно скопировать kubeconfig локально:
>
> ```bash
> scp artur@r1.kryukov.lan:/etc/kubernetes/admin.conf ~/.kube/config-homelab
> export KUBECONFIG=~/.kube/config-homelab
> # Теперь kubectl работает напрямую
> kubectl get nodes
> ```

**Критерии успеха:**

- [ ] Все 5 нод (3 control + 2 worker) в состоянии `Ready`
- [ ] Версия Kubernetes: `v1.35.0`
- [ ] Все поды в kube-system в состоянии `Running` (или `Completed` для jobs)
- [ ] API endpoint доступен по адресу `https://192.168.218.130:7443`

#### 3.3.3. Проверка HA (HAProxy + Keepalived)

```bash
# На каждой control plane ноде:
ssh artur@r1.kryukov.lan "sudo systemctl status haproxy --no-pager"
ssh artur@r1.kryukov.lan "sudo systemctl status keepalived --no-pager"

# Проверить что Virtual IP активен на одной из нод
ssh artur@r1.kryukov.lan "ip addr show | grep 192.168.218.130"
ssh artur@r2.kryukov.lan "ip addr show | grep 192.168.218.130"
ssh artur@r3.kryukov.lan "ip addr show | grep 192.168.218.130"

# Проверить доступность API через Virtual IP
curl -k https://192.168.218.130:7443/version
```

**Критерии успеха:**

- [ ] HAProxy запущен на всех control plane нодах
- [ ] Keepalived запущен на всех control plane нодах
- [ ] Virtual IP 192.168.218.130 активен на одной из нод
- [ ] API доступен через Virtual IP

#### 3.3.4. Проверка CNI (Calico)

```bash
# Проверить поды Calico
ssh artur@r1.kryukov.lan "sudo kubectl get pods -n calico-system"

# Проверить сетевую связность между подами
ssh artur@r1.kryukov.lan "sudo kubectl run test-pod-1 --image=busybox:1.36 --restart=Never -- sleep 3600"
ssh artur@r1.kryukov.lan "sudo kubectl run test-pod-2 --image=busybox:1.36 --restart=Never -- sleep 3600"
# Подождать запуска и проверить ping
ssh artur@r1.kryukov.lan "sudo kubectl exec test-pod-1 -- ping -c 3 <IP_test-pod-2>"
```

**Критерии успеха:**

- [ ] Все поды Calico в состоянии `Running`
- [ ] Поды на разных нодах могут общаться друг с другом

#### 3.3.5. Проверка CRI (containerd)

```bash
# На каждой ноде:
ssh artur@r1.kryukov.lan "sudo systemctl status containerd --no-pager"
ssh artur@r1.kryukov.lan "sudo crictl info"
ssh artur@r1.kryukov.lan "sudo crictl ps"
```

**Критерии успеха:**

- [ ] containerd запущен на всех нодах
- [ ] crictl показывает работающие контейнеры

#### 3.3.6. Проверка утилит (если установлены)

```bash
# Helm (устанавливается на 1-ю control plane ноду)
ssh artur@r1.kryukov.lan "helm version"

# cert-manager
ssh artur@r1.kryukov.lan "sudo kubectl get pods -n cert-manager"

# Metrics Server
ssh artur@r1.kryukov.lan "sudo kubectl top nodes"

# MetalLB
ssh artur@r1.kryukov.lan "sudo kubectl get pods -n metallb-system"

# Ingress Controller
ssh artur@r1.kryukov.lan "sudo kubectl get pods -n ingress-nginx"

# ArgoCD
ssh artur@r1.kryukov.lan "sudo kubectl get pods -n argocd"
```

---

## 4. Этап 2: Upgrade кластера Kubernetes до v1.36

### 4.1. Подготовка к upgrade

#### 4.1.1. Скачать и разместить RPM для v1.36

```bash
# Создать директорию на целевых машинах
ansible k8s_cluster -i hosts-homelab.yaml -u artur --become \
  -m file -a "path=/tmp/k8s-rpms state=directory mode=0755"

# Копирование RPM на все ноды k8s_cluster
ansible k8s_cluster -i hosts-homelab.yaml -u artur --become \
  -m copy \
  -a "src=tmp/rpms/kubeadm-1.36.1.rpm dest=/tmp/k8s-rpms/kubeadm-1.36.1.rpm"

ansible k8s_cluster -i hosts-homelab.yaml -u artur --become \
  -m copy \
  -a "src=tmp/rpms/kubelet-1.36.1.rpm dest=/tmp/k8s-rpms/kubelet-1.36.1.rpm"

ansible k8s_cluster -i hosts-homelab.yaml -u artur --become \
  -m copy \
  -a "src=tmp/rpms/kubectl-1.36.1.rpm dest=/tmp/k8s-rpms/kubectl-1.36.1.rpm"

# Проверить что файлы скопированы
ansible k8s_cluster -i hosts-homelab.yaml -u artur --become \
  -m shell -a "ls -la /tmp/k8s-rpms/"
```

#### 4.1.2. Обновить переменную версии

```bash
export KUBE_VERSION="1.36.1"
```

#### 4.1.3. Проверить матрицу совместимости etcd

Согласно обновлённой матрице совместимости:

- Для k8s v1.35 → etcd `3.5.24-0`
- Для k8s v1.36 → etcd `3.6.6-0`

> **Примечание:** Upgrade etcd обрабатывается автоматически в `upgrade.yaml`
> при `etcd_mode: external`. Версия etcd определяется автоматически
> на основе `kube_version`.

### 4.2. Запуск upgrade

**Через Makefile (рекомендуется):**

```bash
export KUBE_VERSION="1.36.1"

make upgrade ENV=homelab EXTRA='-e "kube_version=${KUBE_VERSION}" -e "etcd_mode=external"'
```

**Напрямую через ansible-playbook:**

```bash
# Проверить синтаксис (dry-run)
ansible-playbook -i hosts-homelab.yaml upgrade.yaml \
  -u artur --become \
  -e "kube_version=${KUBE_VERSION}" \
  -e "etcd_mode=external" \
  --check -vv

# Запустить upgrade
ansible-playbook -i hosts-homelab.yaml upgrade.yaml \
  -u artur --become \
  -e "kube_version=${KUBE_VERSION}" \
  -e "etcd_mode=external" \
  -vv
```

> **Примечание:** Upgrade использует общие задачи `_version-check.yaml`
> и `_update-repo.yaml` для проверки версий и обновления репозиториев.

### 4.3. Проверки после upgrade

#### 4.3.1. Проверка upgraded external etcd

```bash
# Проверить версию etcd
ssh artur@e1.kryukov.lan "sudo docker exec etcd etcdctl \
  --cacert=/etc/etcd/pki/ca.crt \
  --cert=/etc/etcd/pki/server.crt \
  --key=/etc/etcd/pki/server.key \
  --endpoints=https://192.168.218.141:2379 \
  version"

# Проверить health
ssh artur@e1.kryukov.lan "sudo docker exec etcd etcdctl \
  --cacert=/etc/etcd/pki/ca.crt \
  --cert=/etc/etcd/pki/server.crt \
  --key=/etc/etcd/pki/server.key \
  --endpoints=https://192.168.218.141:2379,https://192.168.218.142:2379,https://192.168.218.143:2379 \
  endpoint health"
```

**Критерии успеха:**

- [ ] Версия etcd: `3.6.6`
- [ ] Все 3 ноды healthy
- [ ] Кластер функционирует без потерь данных

#### 4.3.2. Проверка upgraded Kubernetes кластера

```bash
# Проверить версию кластера
ssh artur@r1.kryukov.lan "sudo kubectl version -o yaml"

# Проверить статус нод
ssh artur@r1.kryukov.lan "sudo kubectl get nodes -o wide"

# Проверить что все ноды на новой версии
ssh artur@r1.kryukov.lan "sudo kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{\"\t\"}{.status.nodeInfo.kubeletVersion}{\"\n\"}{end}'"

# Проверить статус всех подов
ssh artur@r1.kryukov.lan "sudo kubectl get pods --all-namespaces -o wide"

# Проверить компоненты control plane
ssh artur@r1.kryukov.lan "sudo kubectl get pods -n kube-system | grep -E 'apiserver|controller|scheduler'"
```

**Критерии успеха:**

- [ ] Версия Kubernetes: `v1.36.1`
- [ ] Все 5 нод в состоянии `Ready`
- [ ] Все ноды показывают версию `v1.36.1`
- [ ] Все поды в рабочем состоянии

#### 4.3.3. Проверка работоспособности приложений

```bash
# Создать тестовое приложение
ssh artur@r1.kryukov.lan "sudo kubectl create deployment nginx-test --image=nginx:1.25 --replicas=3"

# Проверить что поды распределены по разным нодам
ssh artur@r1.kryukov.lan "sudo kubectl get pods -o wide"

# Проверить Service
ssh artur@r1.kryukov.lan "sudo kubectl expose deployment nginx-test --port=80 --type=ClusterIP"
ssh artur@r1.kryukov.lan "sudo kubectl get svc nginx-test"

# Проверить DNS
ssh artur@r1.kryukov.lan "sudo kubectl run dns-test --image=busybox:1.36 --restart=Never -- nslookup nginx-test.default.svc.cluster.local"
```

**Критерии успеха:**

- [ ] Deployment создан, 3 реплики Running
- [ ] Поды распределены по разным нодам
- [ ] Service доступен
- [ ] DNS разрешение работает

#### 4.3.4. Проверка HA после upgrade

```bash
# Проверить Virtual IP на control plane нодах
ssh artur@r1.kryukov.lan "ip addr show | grep 192.168.218.130"
ssh artur@r2.kryukov.lan "ip addr show | grep 192.168.218.130"
ssh artur@r3.kryukov.lan "ip addr show | grep 192.168.218.130"

# Проверить доступность API через Virtual IP
curl -k https://192.168.218.130:7443/version

# Проверить что API доступен с worker нод
ssh artur@r4.kryukov.lan "curl -sk https://192.168.218.130:7443/version"
```

---

## 5. Этап 3: Отказоустойчивость и негативные тесты

### 5.1. Тест отказоустойчивости etcd

```bash
# Остановить etcd на одной ноде (e1)
ssh artur@e1.kryukov.lan "sudo systemctl stop etcd"

# Проверить что кластер продолжает работать
ssh artur@r1.kryukov.lan "sudo kubectl get nodes"

# Проверить что оставшиеся 2 ноды etcd работают
ssh artur@e2.kryukov.lan "sudo docker exec etcd etcdctl \
  --cacert=/etc/etcd/pki/ca.crt \
  --cert=/etc/etcd/pki/server.crt \
  --key=/etc/etcd/pki/server.key \
  --endpoints=https://192.168.218.142:2379,https://192.168.218.143:2379 \
  endpoint health"

# Запустить etcd обратно
ssh artur@e1.kryukov.lan "sudo systemctl start etcd"

# Проверить что нода вернулась в кластер
ssh artur@e1.kryukov.lan "sudo docker exec etcd etcdctl \
  --cacert=/etc/etcd/pki/ca.crt \
  --cert=/etc/etcd/pki/server.crt \
  --key=/etc/etcd/pki/server.key \
  --endpoints=https://192.168.218.141:2379 \
  member list -w table"
```

### 5.2. Тест отказоустойчивости control plane

```bash
# Остановить HAProxy + Keepalived на ноде с Virtual IP
# (определить ноду с VIP)
ssh r1.kryukov.lan "systemctl stop keepalived haproxy"

# Проверить что VIP переехал на другую ноду
ssh r2.kryukov.lan "ip addr show | grep 192.168.218.130"

# Проверить что API доступен
curl -k https://192.168.218.130:7443/version

# Вернуть обратно
ssh r1.kryukov.lan "systemctl start keepalived haproxy"
```

### 5.3. Тест создания/удаления ресурсов

```bash
# Создать Namespace, Deployment, Service, ConfigMap, Secret
kubectl create namespace test-ns
kubectl create configmap test-cm --from-literal=key=value -n test-ns
kubectl create secret generic test-secret --from-literal=password=secret -n test-ns
kubectl create deployment test-app --image=nginx:1.25 --replicas=2 -n test-ns
kubectl expose deployment test-app --port=80 -n test-ns

# Проверить всё создано
kubectl get all -n test-ns
kubectl get cm,secret -n test-ns

# Удалить
kubectl delete namespace test-ns
```

---

## 6. Этап 5: Проверка pre-flight и hooks

### 6.1. Pre-flight проверки

Pre-flight проверки запускаются автоматически в начале `install-cluster.yaml`.
Для тестирования можно запустить с некорректными данными:

```bash
# Тест: некорректная версия Kubernetes (должна завершиться ошибкой)
ansible-playbook -i hosts-homelab.yaml install-cluster.yaml \
  -u artur --become \
  -e "kube_version=1.27.0" \
  -e "etcd_mode=external" \
  --check -vv

# Тест: нечётное количество control plane (проверка в pre-flight)
# Создать временный инвентори с 2 control plane нодами и запустить

# Тест: недопустимый CRI
ansible-playbook -i hosts-homelab.yaml install-cluster.yaml \
  -u artur --become \
  -e "cri=invalid" \
  -e "etcd_mode=external" \
  --check -vv
```

**Критерии успеха:**

- [ ] Pre-flight завершается с ошибкой при некорректной версии
- [ ] Pre-flight завершается с ошибкой при чётном количестве control plane
- [ ] Pre-flight завершается с ошибкой при недопустимом CRI/CNI

### 6.2. Hooks (расширения)

Hooks определяются в `group_vars/all/hooks.yaml` и позволяют выполнять
кастомные задачи до/после основных этапов установки.

```bash
# Создать тестовый hook
cat > group_vars/all/hooks-test.yaml << 'EOF'
pre_prepare_tasks:
  - name: Test pre-prepare hook
    debug:
      msg: "Pre-prepare hook executed"

post_master_init_tasks:
  - name: Test post-master-init hook
    debug:
      msg: "Post-master-init hook executed"
EOF

# Запустить установку с hooks (offline)
ansible-playbook -i hosts-homelab.yaml install-cluster.yaml \
  -u artur --become \
  -e "kube_version=1.35.0" \
  -e "etcd_mode=external" \
  -e "k8s_install_mode=offline" \
  -vv
```

**Критерии успеха:**

- [ ] Pre-prepare hook выполняется перед подготовкой хостов
- [ ] Post-master-init hook выполняется после инициализации master
- [ ] Hooks не влияют на основной процесс установки

---

## 7. Этап 6: Очистка (Reset)

### 7.1. Reset кластера

**Через Makefile (рекомендуется):**

```bash
make reset ENV=homelab EXTRA='-e "etcd_mode=external" -e "reset_etcd=true"'
```

**Напрямую через ansible-playbook:**

```bash
# Проверить синтаксис (dry-run)
ansible-playbook -i hosts-homelab.yaml reset.yaml \
  -e "etcd_mode=external" \
  -e "reset_etcd=true" \
  --check -vv

# Запустить reset
ansible-playbook -i hosts-homelab.yaml reset.yaml \
  -e "etcd_mode=external" \
  -e "reset_etcd=true" \
  -vv
```

> **Важно:** `reset.yaml` удаляет все нестандартные iptables цепочки!
> External etcd не удаляется по умолчанию (установите `reset_etcd: true`).

### 7.2. Проверки после reset

```bash
# Проверить что kubeadm удалён
ssh artur@r1.kryukov.lan "which kubeadm"  # должно вернуть ошибку

# Проверить что containerd остановлен
ssh artur@r1.kryukov.lan "sudo systemctl status containerd"

# Проверить что iptables очищены
ssh artur@r1.kryukov.lan "sudo iptables -L"

# Проверить что etcd остановлен (если reset_etcd=true)
ssh artur@e1.kryukov.lan "sudo systemctl status etcd"  # должен быть inactive
```

---

## 8. Матрица проверок

### 8.1. Чек-лист проверок

| # | Проверка | Этап | Ожидаемый результат | Статус |
|---|----------|------|---------------------|--------|
| 1 | SSH доступ ко всем нодам (artur@) | Подготовка | Все ноды доступны, sudo работает | ✅ |
| 2 | Скачивание RPM v1.35 для Rocky Linux 10 | Подготовка | RPM в tmp/rpms/, совместимы с EL10 | ✅ |
| 3 | Скачивание RPM v1.36 для Rocky Linux 10 | Подготовка | RPM в tmp/rpms/, совместимы с EL10 | ✅ |
| 4 | Синтаксис install-cluster.yaml | Подготовка | Без ошибок | ✅ |
| 5 | Pre-flight: некорректная версия | Подготовка | Завершается с ошибкой | ⬜ |
| 6 | Pre-flight: чётное количество control plane | Подготовка | Завершается с ошибкой | ⬜ |
| 7 | Установка external etcd | Установка | 3 ноды, healthy | ✅ |
| 8 | Установка control plane | Установка | 3 ноды, Ready | ✅ |
| 9 | Установка worker нод | Установка | 2 ноды, Ready | ✅ |
| 10 | HA (VIP) | Установка | VIP активен, API доступен | ✅ |
| 11 | CNI (Calico) | Установка | Поды Running, связность | ✅ |
| 12 | CRI (containerd) | Установка | Запущен, контейнеры работают | ✅ |
| 13 | Версия k8s = 1.35.0 → 1.36.1 | Установка / Upgrade | `kubectl version` | ⬜ |
| 14 | Версия etcd = 3.5.24 → 3.6.6 | Установка / Upgrade | `etcdctl version` | ⬜ |
| 15 | Синтаксис upgrade.yaml | Upgrade | Без ошибок | ⬜ |
| 16 | Upgrade etcd до 3.6.6 | Upgrade | Rolling upgrade, healthy | ⬜ |
| 17 | Upgrade k8s до 1.36.1 | Upgrade | Все ноды, новая версия | ⬜ |
| 18 | Работоспособность приложений | Upgrade | Deployment, Service, DNS | ⬜ |
| 19 | HA после upgrade | Upgrade | VIP, API доступен | ⬜ |
| 20 | Отказоустойчивость etcd | Негативные | Кластер жив при 1 ноде down | ⬜ |
| 21 | Отказоустойчивость control plane | Негативные | VIP переезжает, API доступен | ⬜ |
| 22 | Hooks (pre/post install) | Hooks | Выполняются корректно | ⬜ |
| 23 | Reset кластера | Очистка | Пакеты удалены, iptables очищены | ⬜ |
| 24 | Reset etcd | Очистка | etcd остановлен, данные удалены | ⬜ |

---

## 9. Известные проблемы и замечания

### 9.1. Критические

1. ~~**Дубликат в hosts-homelab.yaml**~~ — исправлено в коммите `81a977a`
2. ~~**Offline-пакеты**~~ — реализован offline-режим в коммите `556f60d`:
   - Добавлена переменная `k8s_install_mode: offline`
   - `prepare-hosts` копирует RPM с Ansible control node и устанавливает через dnf
   - Upgrade-задачи используют glob-паттерны и `k8s_rpm_remote_dir`
3. ~~**Upgrade ожидает конкретное именование RPM**~~ — подтверждено:
   скачанные пакеты имеют именование `150500.1.1`, совместимое с playbook.
   Playbook обновлён для использования glob-паттернов.

### 9.2. Рекомендации

1. ~~Добавить задачу в upgrade playbook для копирования RPM на целевые машины~~ — реализовано
2. ~~Добавить проверку доступности RPM перед upgrade~~ — реализовано в `_version-check.yaml`
3. Добавить rollback-сценарий для upgrade
4. ~~Добавить проверку совместимости версий etcd перед upgrade~~ — реализовано в pre-flight
5. ~~Добавить логирование версий до и после upgrade~~ — реализовано в `_version-check.yaml`

---

## 10. Команды для быстрого запуска

### 10.1. Полный цикл тестирования (через Makefile)

```bash
# 0. Собрать Docker-образ
docker build -f Dockerfile.ansible -t ansible-custom:13.6 .

# 1. Подготовить RPM для Rocky Linux 10 (см. раздел 2.3)
mkdir -p tmp/rpms
# ... скачать RPM v1.35 и v1.36 для EL10 ...

# 2. Проверить доступ ко всем нодам
make ping ENV=homelab

# 3. Установить кластер v1.35 с external etcd (offline)
make install ENV=homelab EXTRA='-e "kube_version=1.35.0" -e "etcd_mode=external" -e "k8s_install_mode=offline"'

# 4. Проверить установку (см. раздел 3.3)

# 5. Upgrade до v1.36
make upgrade ENV=homelab EXTRA='-e "kube_version=1.36.1" -e "etcd_mode=external"'

# 6. Проверить upgrade (см. раздел 4.3)

# 7. Reset кластера
make reset ENV=homelab EXTRA='-e "etcd_mode=external" -e "reset_etcd=true"'
```

### 10.2. Запуск через Docker-контейнер (без Makefile)

Если Makefile не используется, полная команда выглядит так:

```bash
# Из директории проекта
docker run --rm -ti \
  -v "$(pwd):/workspace" \
  -v ~/.ssh:/home/ansible/.ssh \
  ansible-custom:13.6 \
  ansible-playbook -i hosts-homelab.yaml install-cluster.yaml \
    -u artur --become \
    -e "kube_version=1.35.0" \
    -e "etcd_mode=external" \
    -e "k8s_install_mode=offline" \
    -vv
```

---

## 11. Диагностика проблем

### 11.1. Полезные команды для отладки

**Через Makefile:**

```bash
# Проверить доступность нод
make ping ENV=homelab

# Проверить синтаксис playbook
make check-install ENV=homelab
make check-upgrade ENV=homelab
make check-reset ENV=homelab

# Проверить группы инвентори
make inventory ENV=homelab
```

**Напрямую через Ansible:**

```bash
# Проверить доступность нод
ansible -i hosts-homelab.yaml all -u artur -m ping

# Проверить переменные
ansible -i hosts-homelab.yaml k8s_masters -u artur -m debug -a "var=kube_version"

# Проверить группу
ansible -i hosts-homelab.yaml --list-hosts k8s_cluster
ansible -i hosts-homelab.yaml --list-hosts etcd_nodes
```

### 11.2. Типичные проблемы

| Проблема | Причина | Решение |
|----------|---------|---------|
| Ноды не становятся Ready | CNI не установлен | Проверить поды Calico |
| API недоступен через VIP | Keepalived не работает | Проверить статус keepalived |
| etcd кластер не формируется | Проблемы с сертификатами | Проверить `files/etcd-pki/` |
| Upgrade зависает | Нода не drain | Проверить `kubectl get nodes` |
| RPM не устанавливаются | Неправильное имя файла | Проверить naming convention |
