# План тестирования: Kubernetes кластер (v0.5.0)

Тестирование установки, обновления и удаления кластера через Docker-контейнер.

## 1. Инфраструктура тестирования

### 1.1. Целевые машины

Инвентарь: `hosts-curs.yaml`

| Хост | IP | Роль |
|------|----|------|
| cp1.local.lan | 192.168.218.141 | control plane (master) |
| cp2.local.lan | 192.168.218.142 | worker |
| cp3.local.lan | 192.168.218.143 | worker |
| w1.local.lan | 192.168.218.144 | worker |
| w2.local.lan | 192.168.218.145 | worker |

ОС: Rocky Linux 9/10. Доступ: `ssh artur@<IP>` (sudo → root).

### 1.2. Ansible control node

Запуск через Docker-контейнер (`Dockerfile.ansible`):

```shell
docker build --platform linux/amd64 -f Dockerfile.ansible -t ansible-custom:13.6 .

alias ansible-playbook="docker run -ti --rm -u root -e HOME=/root \
  -v ~/.ssh:/root/.ssh:ro -v $(pwd):/workspace ansible-custom:13.6 ansible-playbook"
```

Или нативно (venv с ansible 13.6).

## 2. Подготовка к тестированию

- [ ] Docker запущен (Orbstack на macOS)
- [ ] Docker-образ `ansible-custom:13.6` собран
- [ ] SSH-ключи скопированы: `ssh-copy-id artur@192.168.218.141` (на все ноды)
- [ ] `ssh artur@192.168.218.141 hostname` работает без пароля
- [ ] `hosts-curs.yaml` корректен (cp1 в masters, остальные в workers)
- [ ] `group_vars/k8s_cluster` настроен (CNI, утилиты, версии)

## 3. Этап 1: Установка кластера (online)

### 3.1. Запуск

```shell
make install ENV=curs
```

### 3.2. Проверка нод

```shell
ssh artur@192.168.218.141 "sudo kubectl get nodes -o wide"
```

- [ ] cp1 — Ready, role control-plane
- [ ] cp2, cp3, w1, w2 — Ready, role none
- [ ] Все ноды нужной версии Kubernetes

### 3.3. Проверка подов

```shell
ssh artur@192.168.218.141 "sudo kubectl get pods -A"
```

- [ ] Все поды в Running (coredns, kube-proxy при flannel, cilium при cilium)
- [ ] Нет CrashLoopBackOff

### 3.4. Проверка CNI

При `cni: cilium`:

```shell
ssh artur@192.168.218.141 "sudo cilium status"
ssh artur@192.168.218.141 "sudo cilium connectivity test"
```

- [ ] Cilium Agent OK на всех нодах
- [ ] Connectivity test проходит

### 3.5. Проверка связности подов

```shell
ssh artur@192.168.218.141 "sudo kubectl run test-pod-1 --image=busybox:1.36 --restart=Never -- sleep 3600"
ssh artur@192.168.218.141 "sudo kubectl run test-pod-2 --image=busybox:1.36 --restart=Never -- sleep 3600"
# дождаться Running
ssh artur@192.168.218.141 "sudo kubectl exec test-pod-1 -- ping -c 3 <IP_test-pod-2>"
```

- [ ] Ping между подами на разных нодах работает

### 3.6. Проверка DNS

```shell
ssh artur@192.168.218.141 "sudo kubectl run dns-test --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default"
```

- [ ] DNS-резолвинг работает

### 3.7. Проверка утилит

```shell
ssh artur@192.168.218.141 "sudo kubectl get pods -n cert-manager"
ssh artur@192.168.218.141 "sudo kubectl get pods -n argocd"
ssh artur@192.168.218.141 "sudo kubectl get pods -n envoy-gateway-system"
ssh artur@192.168.218.141 "sudo helm list -A"
```

- [ ] cert-manager: 3 пода Running
- [ ] ArgoCD: поды Running
- [ ] Envoy Gateway: под Running
- [ ] Helm-releases соответствуют включённым утилитам

### 3.8. Проверка CLI-инструментов

```shell
ssh artur@192.168.218.141 "sudo helm version"
ssh artur@192.168.218.141 "sudo cilium version"   # при cni=cilium
ssh artur@192.168.218.141 "sudo yq --version"
ssh artur@192.168.218.141 "sudo stern --version"
```

- [ ] helm, cilium, yq, stern доступны на cp1
- [ ] jq доступен (через packages_common)

## 4. Этап 2: Offline-установка

### 4.1. Подготовка артефактов (на Ansible control node)

```shell
make download-artifacts
```

- [ ] `tmp/offline/packages/` содержит RPM (kubeadm, kubelet, kubectl, cri-tools, kubernetes-cni)
- [ ] `tmp/offline/cri/containerd/` содержит containerd.io RPM
- [ ] `tmp/offline/images/k8s/` содержит 7 tar (образы Kubernetes)
- [ ] `tmp/offline/images/cilium/` содержит tar Cilium (при cni=cilium)
- [ ] `tmp/offline/cni/cilium-*.tgz` (при cni=cilium)
- [ ] `tmp/offline/utils/` содержит helm, CLI-инструменты, helm-чарты, helm-diff

### 4.2. Установка offline

```shell
make install ENV=curs EXTRA='-e "k8s_install_mode=offline"'
```

- [ ] Pre-flight offline-проверки проходят
- [ ] RPM ставятся из локальных файлов
- [ ] Образы импортируются через `ctr images import`
- [ ] Кластер поднят, проверка как в этапе 1

## 5. Этап 3: Удаление кластера

### 5.1. Запуск reset

```shell
make reset ENV=curs
```

### 5.2. Проверка очистки

```shell
ssh artur@192.168.218.141 "sudo kubectl get nodes"         # должен ошибиться
ssh artur@192.168.218.141 "ls /etc/kubernetes"              # не существует
ssh artur@192.168.218.141 "ls /var/lib/kubelet"             # не существует
ssh artur@192.168.218.141 "ls /var/lib/containerd"          # не существует
ssh artur@192.168.218.141 "ls /etc/containerd"              # не существует
ssh artur@192.168.218.141 "which kubeadm kubelet kubectl"   # не установлены
ssh artur@192.168.218.141 "which helm cilium yq stern"      # не установлены
ssh artur@192.168.218.141 "systemctl is-active containerd"  # inactive
```

- [ ] Все компоненты удалены на всех нодах

## 6. Этап 4: Обновление кластера

### 6.1. Подготовка

- [ ] Кластер установлен (этап 1)
- [ ] В `group_vars/k8s_cluster` указана новая `kube_version` (minor+1)

### 6.2. Запуск upgrade

```shell
make upgrade ENV=curs
```

### 6.3. Проверка

```shell
ssh artur@192.168.218.141 "sudo kubectl get nodes"
```

- [ ] Все ноды обновлены до новой версии
- [ ] Поды в Running
- [ ] CNI и утилиты обновлены (helm list показывает новые версии)

## 7. Чек-лист

| # | Сценарий | Результат |
|---|----------|-----------|
| 1 | Online install (cilium) | |
| 2 | Проверка нод/подов/DNS | |
| 3 | Cilium connectivity test | |
| 4 | Утилиты (cert-manager, ArgoCD, Envoy) | |
| 5 | CLI (helm, cilium, yq, stern) | |
| 6 | Offline install | |
| 7 | Reset (полная очистка) | |
| 8 | Upgrade minor-версии | |
