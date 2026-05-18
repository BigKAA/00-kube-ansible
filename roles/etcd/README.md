# Роль: etcd

Установка и настройка external etcd кластера для Kubernetes.

## Что делает

### Режим установки (по умолчанию)

1. Генерирует CA сертификат (на Ansible control node)
2. Генерирует сертификаты для каждой etcd ноды
3. Генерирует клиентский сертификат kube-apiserver
4. Генерирует административный сертификат etcdctl
5. Загружает сертификаты на etcd ноды
6. Загружает клиентские сертификаты на control plane ноды
7. Устанавливает etcd контейнер (через Docker)
8. Проверяет состояние кластера

### Режим подключения к существующему кластеру (`etcd_use_existing: true`)

1. Проверяет обязательные переменные (пути к сертификатам)
2. Проверяет health всех etcd-нод через HTTPS API
3. Проверяет совместимость версии etcd с Kubernetes
4. Распределяет клиентские сертификаты на control plane ноды

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `kube_version` | `1.36.1` | Версия Kubernetes (для матрицы etcd) |
| `etcd_mode` | `external` | Должен быть `external` |
| `etcd_use_existing` | `false` | Подключиться к существующему кластеру |
| `etcd_existing_ca_cert` | `""` | CA сертификат существующего кластера (путь на Ansible control node) |
| `etcd_existing_client_cert` | `""` | Клиентский сертификат apiserver (путь на Ansible control node) |
| `etcd_existing_client_key` | `""` | Ключ клиентского сертификата (путь на Ansible control node) |
| `etcd_config_dir` | `/etc/etcd` | Каталог конфигурации etcd |
| `etcd_data_dir` | `/var/lib/etcd` | Каталог данных etcd |
| `etcd_local_pki_dir` | `{{ playbook_dir }}/files/etcd-pki` | Локальный каталог PKI |
| `etcd_key_size` | `4096` | Размер ключа (бит) |
| `etcd_ca_days` | `3650` | Срок жизни CA (дней) |
| `etcd_cert_days` | `365` | Срок жизни сертификатов (дней) |
| `etcd_quota_backend_bytes` | `8589934592` | Quota backend (8 GB) |

## Зависимости

- Docker устанавливается автоматически через playbook `install-cluster.yaml`
- Роль выполняется только при `etcd_mode: external`

## Матрица совместимости

Версия etcd определяется автоматически по `kube_version`:
[roles/etcd/defaults/main.yaml](defaults/main.yaml)

## Примечания

- Сертификаты генерируются на Ansible control node и загружаются на ноды
- При `reset.yaml` external etcd **не удаляется** по умолчанию
- См. [TODO.md](../../TODO.md) для планов по развитию роли
