# Роль: master

Инициализация первой (primary) control plane ноды Kubernetes.

## Что делает

- Генерирует kubeadm-config.yaml (для stacked или external etcd)
- Загружает образы Kubernetes (kubeadm config images pull)
- Выполняет `kubeadm init`
- Устанавливает CNI (Calico или Flannel)
- Устанавливает NodeLocalDNS
- Создаёт symlink для kubeconfig (`/root/.kube/config`)

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `kube_version` | `1.36.1` | Версия Kubernetes |
| `cri_socket` | авто | Сокет CRI |
| `cni` | `calico` | CNI: `calico` или `flannel` |
| `etcd_mode` | `stacked` | Режим etcd: `stacked` или `external` |
| `service_cidr` | `10.233.0.0/18` | CIDR для сервисов |
| `pod_network_cidr` | `10.233.64.0/18` | CIDR для подов |
| `tigera_operator_version` | `v3.28.1` | Версия Calico/Tigera Operator |
| `enableBPF` | не задано | Включить eBPF для Calico |
| `nodelocaldns_image` | см. group_vars | Образ NodeLocalDNS |
| `nodelocaldns_local_ip` | `169.254.25.10` | IP NodeLocalDNS |

## Зависимости

- `prepare-hosts` — должна быть выполнена до master
- `ha` — при использовании HA, должна быть выполнена до master

## Примечания

Роль выполняется только на первом хосте в группе `k8s_masters`
(`when: inventory_hostname == groups['k8s_masters'][0]`).
