# Роль: workers

Подключение worker нод к Kubernetes кластеру.

## Что делает

- Генерирует join token и discovery-token-ca-cert-hash (на первом master)
- Выполняет `kubeadm join` на worker нодах
- Запускает и включает kubelet

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `kube_version` | `1.36.1` | Версия Kubernetes |

## Зависимости

- `prepare-hosts` — должна быть выполнена до workers
- `master` — первый control plane должен быть инициализирован

## Примечания

Роль выполняется на хостах `groups['k8s_masters'][0],k8s_workers`.
Подготовка (генерация токена) выполняется только на первом master.
