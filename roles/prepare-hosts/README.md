# Роль: prepare-hosts

Подготовка хостов для установки Kubernetes (RedHat-семейство).

## Что делает

- Устанавливает системные пакеты (net-tools, vim, git, jq и др.)
- Настраивает NTP (chrony)
- Отключает firewalld и SELinux
- Отключает swap
- Загружает модули ядра (br_netfilter, overlay, nf_conntrack)
- Настраивает sysctl (ip_forward, bridge-nf-call)
- Устанавливает и настраивает containerd
- Устанавливает kubeadm, kubelet, kubectl

### IPVS — только при включённом kube-proxy

IPVS-модули (`ip_set`, `ip_vs`, `ip_vs_rr`, `ip_vs_wrr`, `ip_vs_sh`), пакеты
(`ipvsadm`, `ipset`) и `kernel-modules-extra` (содержит `ip_set`) требуются
только работающему kube-proxy (`mode: ipvs` в `kubeadm-config`).

Условие установки/загрузки — производная переменная `kube_proxy_enabled`
(вычисляется в `group_vars/k8s_cluster`):

| CNI | `cilium_kube_proxy_replacement` | kube-proxy | IPVS |
|-----|---------------------------------|------------|------|
| flannel | — | работает | устанавливается |
| cilium | `false` | работает | устанавливается |
| cilium | `true` | удалён (eBPF) | **не устанавливается** |

Список модулей для постоянной загрузки генерируется шаблоном
`templates/modules-kubernetes.conf.j2` (IPVS-блок включается только при
`kube_proxy_enabled`).

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `cri` | `containerd` | Container Runtime (только containerd) |
| `cri_socket` | `unix:///run/containerd/containerd.sock` | Сокет CRI |
| `k8s_install_mode` | `online` | Режим установки: `online` или `offline` |
| `k8s_offline_dir` | `tmp/offline` | Базовый каталог offline-артефактов (относительно playbook_dir) |
| `k8s_packages_remote_dir` | `/tmp/k8s-packages` | Путь на удалённом хосте для временных файлов |
| `dockerhubMirror` | `false` | Включить зеркало Docker Hub |

## Offline-режим

При `k8s_install_mode: "offline"`:

- RPM-пакеты Kubernetes и containerd устанавливаются из `tmp/offline/packages/`
  и `tmp/offline/cri/containerd/` (через `dnf install`)
- Образы контейнеров копируются из `tmp/offline/images/` на ноду
  (`/tmp/k8s-packages/images/`)

## Зависимости

Нет внешних зависимостей. Роль выполняется первой в playbook.
