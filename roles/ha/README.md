# Роль: ha

Настройка HAProxy + Keepalived для высокодоступного доступа к Kubernetes API.

## Что делает

- Устанавливает пакеты haproxy и keepalived
- Настраивает sysctl `net.ipv4.ip_nonlocal_bind`
- Разворачивает конфигурацию HAProxy (frontend для API server)
- Разворачивает конфигурацию Keepalived (VRRP для virtual IP)
- Запускает и включает сервисы

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `ha_cluster_virtual_ip` | `192.168.218.130` | Virtual IP для HA |
| `ha_cluster_virtual_port` | `7443` | Порт для HA (не 6443) |

## Зависимости

Нет внешних зависимостей. Должна выполняться до роли `master`.

## Примечания

Роль применяется ко всем хостам в группе `k8s_masters`.
HA включается только если `ha_cluster_virtual_ip` определён и не пуст.
