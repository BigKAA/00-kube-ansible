# Роль: master

Инициализация первой (primary) control plane ноды Kubernetes.

## Что делает

- Генерирует kubeadm-config.yaml (для stacked или external etcd)
- Загружает образы Kubernetes (kubeadm config images pull)
- Выполняет `kubeadm init`
- Устанавливает CNI (Calico, Flannel или Cilium)
- Устанавливает NodeLocalDNS
- Создаёт symlink для kubeconfig (`/root/.kube/config`)

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `kube_version` | `1.36.1` | Версия Kubernetes |
| `cri_socket` | авто | Сокет CRI |
| `cni` | `calico` | CNI: `calico`, `flannel` или `cilium` |
| `etcd_mode` | `stacked` | Режим etcd: `stacked` или `external` |
| `service_cidr` | `10.233.0.0/18` | CIDR для сервисов |
| `pod_network_cidr` | `10.233.64.0/18` | CIDR для подов |
| `tigera_operator_version` | `v3.28.1` | Версия Calico/Tigera Operator |
| `enableBPF` | не задано | Включить eBPF для Calico |
| `cilium_version` | авто (по матрице) | Версия Cilium |
| `cilium_chart_version` | = `cilium_version` | Версия Helm-чарта Cilium |
| `cilium_kube_proxy_replacement` | `false` | Заменить kube-proxy на eBPF-датаплейн Cilium |
| `nodelocaldns_image` | см. group_vars | Образ NodeLocalDNS |
| `nodelocaldns_local_ip` | `169.254.25.10` | IP NodeLocalDNS |

## Offline-режим

При `k8s_install_mode: "offline"`:

- Образы Kubernetes загружаются из `k8s-images.tar` (через `ctr images import`)
- Tigera Operator устанавливается из локального файла `cni/tigera-operator.yaml`
- CNI-образы Calico загружаются из `calico-images.tar`
- Helm-чарт Cilium устанавливается из локального файла `cni/cilium-<version>.tgz`
- CNI-образы Cilium загружаются из `cilium-images.tar`

Каталоги offline-артефактов:

```text
tmp/offline/
├── images/
│   ├── k8s-images.tar        # образы Kubernetes
│   ├── calico-images.tar     # образы Calico (при cni: calico)
│   └── cilium-images.tar     # образы Cilium (при cni: cilium)
└── cni/
    ├── tigera-operator.yaml  # манифест Calico Operator (при cni: calico)
    └── cilium-<version>.tgz  # Helm-чарт Cilium (при cni: cilium)
```

## Зависимости

- `prepare-hosts` — должна быть выполнена до master
- `ha` — при использовании HA, должна быть выполнена до master

## Примечания

Роль выполняется только на первом хосте в группе `k8s_masters`
(`when: inventory_hostname == groups['k8s_masters'][0]`).
