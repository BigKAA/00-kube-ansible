# Роль: second_controls

Подключение дополнительных control plane нод к Kubernetes кластеру (stacked etcd).

## Что делает

- Генерирует join token, discovery-token-ca-cert-hash и certificate-key (на первом master)
- Выполняет `kubeadm join --control-plane` на дополнительных нодах
- Создаёт symlink для kubeconfig (`/root/.kube/config`)
- Перезапускает kubelet

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `kube_version` | `1.36.2` | Версия Kubernetes |

## Зависимости

- `prepare-hosts` — должна быть выполнена до second_controls
- `master` — первый control plane должен быть инициализирован
- `ha` — при использовании HA, должен быть настроен

## Примечания

Роль применяется ко всем хостам в группе `k8s_masters`.
Подготовка (`prepare.yaml`) выполняется только на первом master.
Join (`join.yaml`) выполняется на всех нодах кроме первой.
