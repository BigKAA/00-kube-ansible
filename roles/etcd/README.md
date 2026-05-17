# Роль: etcd

Установка и настройка external etcd кластера для Kubernetes.

## Что делает

1. Генерирует CA сертификат (на Ansible control node)
2. Генерирует сертификаты для каждой etcd ноды
3. Генерирует клиентский сертификат kube-apiserver
4. Генерирует административный сертификат etcdctl
5. Загружает сертификаты на etcd ноды
6. Загружает клиентские сертификаты на control plane ноды
7. Устанавливает etcd контейнер (через Docker)
8. Проверяет состояние кластера

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `kube_version` | `1.36.1` | Версия Kubernetes (для матрицы etcd) |
| `etcd_mode` | `external` | Должен быть `external` |
| `etcd_config_dir` | `/etc/etcd` | Каталог конфигурации etcd |
| `etcd_data_dir` | `/var/lib/etcd` | Каталог данных etcd |
| `etcd_local_pki_dir` | `{{ playbook_dir }}/files/etcd-pki` | Локальный каталог PKI |
| `etcd_key_size` | `4096` | Размер ключа (бит) |
| `etcd_ca_days` | `3650` | Срок жизни CA (дней) |
| `etcd_cert_days` | `365` | Срок жизни сертификатов (дней) |
| `etcd_quota_backend_bytes` | `8589934592` | Quota backend (8 GB) |

## Зависимости

- Docker должен быть установлен на etcd нодах
- Роль выполняется только при `etcd_mode: external`

## Матрица совместимости

Версия etcd определяется автоматически по `kube_version`:
[roles/etcd/defaults/main.yaml](defaults/main.yaml)

## Примечания

Сертификаты генерируются на Ansible control node и загружаются на ноды.
При `reset.yaml` external etcd **не удаляется** по умолчанию.
