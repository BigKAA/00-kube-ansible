# Роль: master

Инициализация первой (primary) control plane ноды Kubernetes.

## Что делает

- Генерирует kubeadm-config.yaml (stacked etcd)
- Загружает образы Kubernetes (kubeadm config images pull)
- Выполняет `kubeadm init`
- Устанавливает CNI (Flannel или Cilium)
- Устанавливает NodeLocalDNS
- Создаёт symlink для kubeconfig (`/root/.kube/config`)

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `kube_version` | `1.36.2` | Версия Kubernetes (>= 1.35) |
| `cri_socket` | авто | Сокет CRI (containerd) |
| `cni` | `cilium` | CNI: `flannel` или `cilium` |
| `service_cidr` | `10.233.0.0/18` | CIDR для сервисов |
| `pod_network_cidr` | `10.233.64.0/18` | CIDR для подов |
| `flannel_version` | авто (по матрице) | Версия Flannel |
| `cilium_version` | авто (по матрице) | Версия Cilium |
| `cilium_chart_version` | = `cilium_version` | Версия Helm-чарта Cilium |
| `cilium_kube_proxy_replacement` | `true` | Заменить kube-proxy на eBPF-датаплейн Cilium |
| `cilium_nodelocaldns` | `true` | NodeLocalDNS через CiliumLocalRedirectPolicy |
| `nodelocaldns_image` | см. group_vars | Образ NodeLocalDNS |
| `nodelocaldns_local_ip` | `169.254.25.10` | IP NodeLocalDNS |

## Offline-режим

При `k8s_install_mode: "offline"`:

- Образы Kubernetes загружаются из `images/k8s/*.tar` (через `ctr images import`)
- Образы Cilium — из `images/cilium/*.tar`
- Образы Flannel — из `images/flannel/*.tar`
- Helm-чарт Cilium устанавливается из локального файла `cni/cilium-<version>.tgz`

Каталоги offline-артефактов:

```text
tmp/offline/
├── images/
│   ├── k8s/        # образы Kubernetes (отдельные tar)
│   ├── cilium/     # образы Cilium (при cni: cilium)
│   └── flannel/    # образы Flannel (при cni: flannel)
└── cni/
    └── cilium-<version>.tgz  # Helm-чарт Cilium (при cni: cilium)
```

## Зависимости

- `prepare-hosts` — должна быть выполнена до master
- `ha` — при использовании HA, должна быть выполнена до master

## Примечания

Роль выполняется только на первом хосте в группе `k8s_masters`
(`when: inventory_hostname == groups['k8s_masters'][0]`).
