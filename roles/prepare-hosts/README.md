# Роль: prepare-hosts

Подготовка хостов для установки Kubernetes.

## Что делает

- Устанавливает системные пакеты (net-tools, vim, git, jq, ipvsadm и др.)
- Настраивает NTP (chrony для RedHat, ntp для Debian)
- Отключает firewalld и SELinux (RedHat)
- Отключает swap
- Загружает модули ядра (br_netfilter, overlay)
- Настраивает sysctl (ip_forward, bridge-nf-call)
- Устанавливает и настраивает CRI (containerd или CRI-O)
- Устанавливает kubeadm, kubelet, kubectl

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `cri` | `containerd` | Container Runtime: `containerd` или `crio` |
| `cri_socket` | авто | Сокет CRI (вычисляется автоматически) |
| `k8s_install_mode` | `online` | Режим установки: `online` или `offline` |
| `k8s_offline_dir` | `tmp/offline` | Базовый каталог offline-артефактов (относительно playbook_dir) |
| `k8s_packages_remote_dir` | `/tmp/k8s-packages` | Путь на удалённом хосте для временных файлов |
| `dockerhubMirror` | `false` | Включить зеркало Docker Hub |
| `crio_version` | авто | Версия CRI-O (вычисляется по kube_version) |
| `stage` | `stable` | Стадия CRI-O: `stable` или `prerelease` |

## Зависимости

Нет внешних зависимостей. Роль выполняется первой в playbook.
