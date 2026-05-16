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

### 2.2. Настройка переменных для external etcd

Создать override-файл переменных для тестирования:

```yaml
# group_vars/k8s_cluster/homelab-test.yaml (или передавать через -e)
etcd_mode: "external"
kube_version: "1.35.0"  # Начальная версия для установки
ha_cluster_virtual_ip: "192.168.218.130"
ha_cluster_virtual_port: 7443
```

### 2.3. Подготовка offline-пакетов (RPM)

Поскольку пакеты Kubernetes недоступны с целевых машин, необходимо скачать их
заранее на Ansible Control Node (MacOS) и разместить в `tmp/rpms/`.

> **Важно:** Целевые машины работают на **Rocky Linux 10** (EL10).
> Пакеты должны быть собраны именно для этой платформы.
> Репозиторий k8s на `pkgs.k8s.io` использует openSUSE Build Service,
> и пакеты для EL10 могут иметь специфическое именование (release tag).

#### 2.3.1. Скачать пакеты Kubernetes v1.35 для Rocky Linux 10

```bash
# Создать директорию
mkdir -p tmp/rpms

# Базовый URL репозитория для k8s v1.35
K8S_RPM_BASE="https://pkgs.k8s.io/core:/stable:/v1.35/rpm"

# Сначала исследуем доступные пакеты для EL10
# Переходим в репозиторий и ищем пакеты для el10/rl10
curl -sL "${K8S_RPM_BASE}/" | grep -i "el10\|rl10\|rocky"

# Если пакеты для EL10 доступны, скачиваем их:
K8S_VERSION="1.35.0"

# Вариант 1: Если пакеты имеют стандартное именование для EL10
curl -L "${K8S_RPM_BASE}/x86_64/kubeadm-${K8S_VERSION}-*.el10.x86_64.rpm" \
  -o "tmp/rpms/kubeadm-${K8S_VERSION}.rpm"
curl -L "${K8S_RPM_BASE}/x86_64/kubelet-${K8S_VERSION}-*.el10.x86_64.rpm" \
  -o "tmp/rpms/kubelet-${K8S_VERSION}.rpm"
curl -L "${K8S_RPM_BASE}/x86_64/kubectl-${K8S_VERSION}-*.el10.x86_64.rpm" \
  -o "tmp/rpms/kubectl-${K8S_VERSION}.rpm"

# Вариант 2: Если используются пакеты от SUSE (как в текущем playbook)
# curl -L "${K8S_RPM_BASE}/x86_64/kubeadm-${K8S_VERSION}-*.x86_64.rpm" \
#   -o "tmp/rpms/kubeadm-${K8S_VERSION}.rpm"
# ... аналогично для kubelet и kubectl
```

> **Проверка:** После скачивания проверьте, что пакеты совместимы с EL10:
> ```bash
> rpm -qp --requires tmp/rpms/kubeadm-1.35.0.rpm | head -20
> ```

#### 2.3.2. Скачать пакеты для upgrade (v1.36) для Rocky Linux 10

```bash
K8S_UPGRADE_VERSION="1.36.1"
K8S_RPM_BASE_136="https://pkgs.k8s.io/core:/stable:/v1.36/rpm"

# Исследовать доступные пакеты
curl -sL "${K8S_RPM_BASE_136}/" | grep -i "el10\|rl10\|rocky"

# Скачать (адаптировать под фактическое именование)
curl -L "${K8S_RPM_BASE_136}/x86_64/kubeadm-${K8S_UPGRADE_VERSION}-*.el10.x86_64.rpm" \
  -o "tmp/rpms/kubeadm-${K8S_UPGRADE_VERSION}.rpm"
curl -L "${K8S_RPM_BASE_136}/x86_64/kubelet-${K8S_UPGRADE_VERSION}-*.el10.x86_64.rpm" \
  -o "tmp/rpms/kubelet-${K8S_UPGRADE_VERSION}.rpm"
curl -L "${K8S_RPM_BASE_136}/x86_64/kubectl-${K8S_UPGRADE_VERSION}-*.el10.x86_64.rpm" \
  -o "tmp/rpms/kubectl-${K8S_UPGRADE_VERSION}.rpm"
```

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

```
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

#### 2.4.2. Dockerfile

```bash
# Создать Dockerfile для Ansible
cat > Dockerfile.ansible << 'EOF'
FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    openssh-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install ansible passlib

WORKDIR /workspace
EOF

# Собрать образ
docker build -f Dockerfile.ansible -t ansible-k8s:latest .
```

#### 2.4.3. Запуск контейнера с persistent-директориями

```bash
# Запустить контейнер с пробросом всех необходимых директорий
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -v "$(pwd)/tmp/rpms:/tmp/rpms" \
  -v "$(pwd)/tmp/ssh:/home/ansible/.ssh" \
  -v "$(pwd)/tmp/ansible-cache:/tmp/ansible-cache" \
  -v "$(pwd)/tmp/logs:/tmp/logs" \
  -w /workspace \
  --user ansible \
  -e ANSIBLE_CONFIG=/workspace/ansible.cfg \
  -e ANSIBLE_CACHE_PLUGIN=jsonfile \
  -e ANSIBLE_CACHE_PLUGIN_CONNECTION=/tmp/ansible-cache \
  ansible-k8s:latest /bin/bash
```

> **Примечание:** SSH-ключи для подключения к `artur@<host>` должны быть
> размещены в `tmp/ssh/` на хост-машине (или скопированы туда из `~/.ssh/`).
> Файлы `known_hosts` также сохраняются в этой директории между запусками.

---

## 3. Этап 1: Первичная установка кластера Kubernetes v1.35

### 3.1. Конфигурация

Обновить `ansible.cfg` для работы через пользователя `artur`:

```ini
[defaults]
inventory = ./hosts-homelab.yaml
roles_path = ./roles
stdout_callback = yaml
stderr_callback = yaml
host_key_checking = False

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
```

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
  --check -vv
```

### 3.2. Запуск установки

```bash
ansible-playbook -i hosts-homelab.yaml install-cluster.yaml \
  -u artur --become \
  -e "kube_version=${KUBE_VERSION}" \
  -e "etcd_mode=external" \
  -vv
```

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
- [ ] Версия etcd соответствует матрице совместимости для v1.35 (`registry.k8s.io/etcd:3.5.21-0`)

#### 3.3.2. Проверка Kubernetes кластера

```bash
# На первой control plane ноде (r1) через SSH:
ssh artur@r1.kryukov.lan "sudo kubectl get nodes -o wide"

# Проверить статус всех подов в kube-system
ssh artur@r1.kryukov.lan "sudo kubectl get pods -n kube-system -o wide"

# Проверить компоненты control plane
ssh artur@r1.kryukov.lan "sudo kubectl get pods -n kube-system | grep -E 'apiserver|controller|scheduler|etcd|proxy'"

# Проверить версию кластера
ssh artur@r1.kryukov.lan "sudo kubectl version --short"

# Проверить конфигурацию cluster-info
ssh artur@r1.kryukov.lan "sudo kubectl cluster-info"
```

> **Совет:** Для удобства можно скопировать kubeconfig локально:
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

Согласно `roles/etcd/defaults/main.yaml`:
- Для k8s v1.35 → etcd `3.5.21-0`
- Для k8s v1.36 → etcd `3.6.6-0`

**Требуется upgrade etcd!**

### 4.2. Запуск upgrade

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
ssh artur@r1.kryukov.lan "sudo kubectl version --short"

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

## 6. Этап 4: Очистка (Reset)

### 6.1. Reset кластера

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

### 6.2. Проверки после reset

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

## 7. Матрица проверок

### 7.1. Чек-лист проверок

| # | Проверка | Этап | Ожидаемый результат | Статус |
|---|----------|------|---------------------|--------|
| 1 | SSH доступ ко всем нодам (artur@) | Подготовка | Все ноды доступны, sudo работает | ☐ |
| 2 | Скачивание RPM v1.35 для Rocky Linux 10 | Подготовка | RPM в tmp/rpms/, совместимы с EL10 | ☐ |
| 3 | Скачивание RPM v1.36 для Rocky Linux 10 | Подготовка | RPM в tmp/rpms/, совместимы с EL10 | ☐ |
| 4 | Синтаксис install-cluster.yaml | Подготовка | Без ошибок | ☐ |
| 5 | Установка external etcd | Установка | 3 ноды, healthy | ☐ |
| 6 | Установка control plane | Установка | 3 ноды, Ready | ☐ |
| 7 | Установка worker нод | Установка | 2 ноды, Ready | ☐ |
| 8 | HA (VIP) | Установка | VIP активен, API доступен | ☐ |
| 9 | CNI (Calico) | Установка | Поды Running, связность | ☐ |
| 10 | CRI (containerd) | Установка | Запущен, контейнеры работают | ☐ |
| 11 | Версия k8s = 1.35.0 | Установка | `kubectl version` | ☐ |
| 12 | Версия etcd = 3.5.21 | Установка | `etcdctl version` | ☐ |
| 13 | Синтаксис upgrade.yaml | Upgrade | Без ошибок | ☐ |
| 14 | Upgrade etcd до 3.6.6 | Upgrade | Rolling upgrade, healthy | ☐ |
| 15 | Upgrade k8s до 1.36.1 | Upgrade | Все ноды, новая версия | ☐ |
| 16 | Работоспособность приложений | Upgrade | Deployment, Service, DNS | ☐ |
| 17 | HA после upgrade | Upgrade | VIP, API доступен | ☐ |
| 18 | Отказоустойчивость etcd | Негативные | Кластер жив при 1 ноде down | ☐ |
| 19 | Отказоустойчивость control plane | Негативные | VIP переезжает, API доступен | ☐ |
| 20 | Reset кластера | Очистка | Пакеты удалены, iptables очищены | ☐ |
| 21 | Reset etcd | Очистка | etcd остановлен, данные удалены | ☐ |

---

## 8. Известные проблемы и замечания

### 8.1. Критические

1. **Дубликат в hosts-homelab.yaml** (строка 15): `r4.kryukov.lan` должен быть `r5.kryukov.lan`
2. **Offline-пакеты**: Текущий playbook ожидает онлайн-репозитории. Необходимо:
   - Либо модифицировать `prepare-hosts/tasks/main.yaml` для установки из локальных RPM
   - Либо скопировать RPM на целевые машины перед запуском
3. **Upgrade ожидает конкретное именование RPM**: В `upgrade-1st-master.yaml` указано:
   ```
   /tmp/k8s-rpms/kubeadm-{{ kube_version }}-150500.1.1.x86_64.rpm
   ```
   Это naming convention для SUSE/openSUSE. Для Rocky Linux 10 naming будет другим
   (вероятно, с суффиксом `.el10` или аналогичным).
   **Необходимо адаптировать playbook.**

### 8.2. Рекомендации

1. Добавить задачу в upgrade playbook для копирования RPM на целевые машины
2. Добавить проверку доступности RPM перед upgrade
3. Добавить rollback-сценарий для upgrade
4. Добавить проверку совместимости версий etcd перед upgrade
5. Добавить логирование версий до и после upgrade

---

## 9. Команды для быстрого запуска

### 9.1. Полный цикл тестирования

```bash
# 1. Исправить hosts-homelab.yaml
# 2. Скачать RPM для Rocky Linux 10 (см. раздел 2.3)
mkdir -p tmp/rpms
# ... скачать RPM v1.35 и v1.36 для EL10 ...

# 3. Проверить доступ ко всем нодам
ansible -i hosts-homelab.yaml all -u artur -m ping

# 4. Установить кластер v1.35
ansible-playbook -i hosts-homelab.yaml install-cluster.yaml \
  -u artur --become \
  -e "kube_version=1.35.0" \
  -e "etcd_mode=external" \
  -vv

# 5. Проверить установку
# ... (см. раздел 3.3) ...

# 6. Скопировать RPM для upgrade на ноды
ansible k8s_cluster -i hosts-homelab.yaml -u artur --become \
  -m file -a "path=/tmp/k8s-rpms state=directory mode=0755"
ansible k8s_cluster -i hosts-homelab.yaml -u artur --become \
  -m copy -a "src=tmp/rpms/ dest=/tmp/k8s-rpms/"

# 7. Upgrade до v1.36
ansible-playbook -i hosts-homelab.yaml upgrade.yaml \
  -u artur --become \
  -e "kube_version=1.36.1" \
  -e "etcd_mode=external" \
  -vv

# 8. Проверить upgrade
# ... (см. раздел 4.3) ...

# 9. Reset
ansible-playbook -i hosts-homelab.yaml reset.yaml \
  -u artur --become \
  -e "etcd_mode=external" \
  -e "reset_etcd=true" \
  -vv
```

### 9.2. Запуск через Docker-контейнер

```bash
# Создать persistent-директории
mkdir -p tmp/{rpms,ansible-cache,ssh,logs}

# Из директории проекта
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -v "$(pwd)/tmp/rpms:/tmp/rpms" \
  -v "$(pwd)/tmp/ssh:/home/ansible/.ssh" \
  -v "$(pwd)/tmp/ansible-cache:/tmp/ansible-cache" \
  -v "$(pwd)/tmp/logs:/tmp/logs" \
  -w /workspace \
  --user ansible \
  -e ANSIBLE_CONFIG=/workspace/ansible.cfg \
  -e ANSIBLE_CACHE_PLUGIN=jsonfile \
  -e ANSIBLE_CACHE_PLUGIN_CONNECTION=/tmp/ansible-cache \
  ansible-k8s:latest \
  ansible-playbook -i hosts-homelab.yaml install-cluster.yaml \
    -u artur --become \
    -e "kube_version=1.35.0" \
    -e "etcd_mode=external" \
    -vv
```

---

## 10. Диагностика проблем

### 10.1. Полезные команды для отладки

```bash
# Проверить доступность нод
ansible -i hosts-homelab.yaml all -u artur -m ping

# Проверить переменные
ansible -i hosts-homelab.yaml k8s_masters -u artur -m debug -a "var=kube_version"

# Проверить группу
ansible -i hosts-homelab.yaml --list-hosts k8s_cluster
ansible -i hosts-homelab.yaml --list-hosts etcd_nodes

# Проверить журналы на нодах
ssh artur@r1.kryukov.lan "sudo journalctl -u kubelet -f --no-pager"
ssh artur@r1.kryukov.lan "sudo journalctl -u containerd -f --no-pager"
ssh artur@e1.kryukov.lan "sudo docker logs etcd"

# Проверить сертификаты etcd
ssh artur@e1.kryukov.lan "sudo openssl x509 -in /etc/etcd/pki/ca.crt -text -noout"

# Проверить версию Rocky Linux
ssh artur@r1.kryukov.lan "cat /etc/rocky-release"
```

### 10.2. Типичные проблемы

| Проблема | Причина | Решение |
|----------|---------|---------|
| Ноды не становятся Ready | CNI не установлен | Проверить поды Calico |
| API недоступен через VIP | Keepalived не работает | Проверить статус keepalived |
| etcd кластер не формируется | Проблемы с сертификатами | Проверить `files/etcd-pki/` |
| Upgrade зависает | Нода не drain | Проверить `kubectl get nodes` |
| RPM не устанавливаются | Неправильное имя файла | Проверить naming convention |
