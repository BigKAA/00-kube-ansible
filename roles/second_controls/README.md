# Роль: second_controls

Подключение дополнительных control plane нод к Kubernetes кластеру.

## Что делает

- Генерирует join token, discovery-token-ca-cert-hash и certificate-key (на первом master)
- Для external etcd: копирует PKI сертификаты с первого master
- Выполняет `kubeadm join --control-plane` на дополнительных нодах
- Перезапускает coredns после подключения всех нод

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `kube_version` | `1.36.1` | Версия Kubernetes |
| `etcd_mode` | `stacked` | Режим etcd: `stacked` или `external` |

## Зависимости

- `prepare-hosts` — должна быть выполнена до second_controls
- `master` — первый control plane должен быть инициализирован
- `ha` — при использовании HA, должен быть настроен

## Примечания

Роль применяется ко всем хостам в группе `k8s_masters`.
Подготовка выполняется только на первом master.
Join выполняется на всех нодах кроме первой.
