# План: Внедрение внешнего etcd кластера в Ansible playbook

> Дата создания: 2026-05-16
> Статус: в работе

---

## 0. Подготовительные изменения

- [x] Обновить версию Kubernetes: добавить `v1.36.1` в поддерживаемые (`group_vars/k8s_cluster`)
- [x] Обновить комментарий `# Versions: 1.28 - 1.35.1` на `# Versions: 1.28 - 1.36.1`
- [x] Добавить переменную `etcd_mode: "stacked"` (по умолчанию) в `group_vars/k8s_cluster` — возможные значения: `stacked`, `external`
- [x] Добавить блок переменных external etcd в `group_vars/k8s_cluster`:
  ```yaml
  # External etcd
  # etcd_mode: external  # раскомментировать для external etcd
  etcd_image: "registry.k8s.io/etcd:3.6.6-0"
  etcd_domain: ""        # домен etcd нод (например, kryukov.lan)
  etcd_initial_cluster_token: "external-etcd-cluster"
  etcd_quota_backend_bytes: 8589934592
  etcd_ca_days: 3650         # Срок жизни CA-сертификата (дней)
  etcd_cert_days: 365        # Срок жизни подписанных сертификатов: ноды, apiserver-client, admin
  ```

## 1. Инвентарь — новая группа `etcd_nodes`

- [x] Добавить группу `etcd_nodes` в `hosts.yaml` (и `hosts-homelab.yaml`):
  ```yaml
  etcd_nodes:
    hosts:
      e1.kryukov.lan:
        ansible_host: 192.168.218.141
        etcd_short_name: e1
      e2.kryukov.lan:
        ansible_host: 192.168.218.142
        etcd_short_name: e2
      e3.kryukov.lan:
        ansible_host: 192.168.218.143
        etcd_short_name: e3
  ```
- [x] Создать `group_vars/etcd_nodes` с переменными специфичными для etcd нод (пользователь Docker и т.д.)

## 2. Новая роль `etcd` — установка и управление кластером

### 2.1. Структура роли

- [x] Создать структуру директорий `roles/etcd/{tasks,templates,files,handlers,defaults}`

### 2.2. Задачи (tasks)

- [x] `roles/etcd/tasks/main.yaml` — точка входа, делегирует вызовы
- [x] `roles/etcd/tasks/generate-ca.yaml` — генерация etcd CA (openssl, на localhost)
- [x] `roles/etcd/tasks/generate-certs.yaml` — генерация сертификатов etcd-нод (на localhost)
- [x] `roles/etcd/tasks/generate-apiserver-cert.yaml` — генерация клиентского сертификата kube-apiserver (на localhost)
- [x] `roles/etcd/tasks/generate-admin-cert.yaml` — генерация административного сертификата etcdctl (на localhost)
- [x] `roles/etcd/tasks/upload-certs-etcd.yaml` — загрузка сертификатов на etcd ноды
- [x] `roles/etcd/tasks/upload-certs-k8s.yaml` — загрузка клиентских сертификатов на control plane ноды
- [x] `roles/etcd/tasks/install.yaml` — установка контейнерного etcd (создание каталогов, env-файл, systemd unit, запуск)
- [x] `roles/etcd/tasks/health-check.yaml` — проверка состояния кластера etcd
- [x] `roles/etcd/tasks/renew-certs.yaml` — обновление сертификатов etcd

### 2.3. Шаблоны (templates)

- [x] `roles/etcd/templates/etcd.env.j2` — шаблон environment-файла для systemd unit
- [x] `roles/etcd/templates/etcd.service.j2` — шаблон systemd unit (на основе `05-etcd-install-container-cluster.sh`)
- [x] `roles/etcd/templates/openssl-node.cnf.j2` — шаблон openssl-конфига для сертификатов нод
- [x] `roles/etcd/templates/openssl-client.cnf.j2` — шаблон openssl-конфига для клиентских сертификатов

### 2.4. Defaults

- [x] `roles/etcd/defaults/main.yaml` — значения по умолчанию для роли etcd

### 2.5. Конфигурация etcd

- [x] Реализовать определение версии etcd по версии Kubernetes (матрица совместимости)
- [x] Использовать `etcd_short_name` из inventory для формирования `ETCD_INITIAL_CLUSTER`
- [x] Формировать `ETCD_INITIAL_CLUSTER` динамически из inventory группы `etcd_nodes`

## 3. Модификация роли `master` — поддержка external etcd

- [x] Создать шаблон `roles/master/templates/kubeadm-config-external-etcd.j2` с блоком `etcd.external` (на основе `manifests/01-kubeadm-external-etcd.yaml`):
  ```yaml
  etcd:
    external:
      endpoints:
        {% for host in groups['etcd_nodes'] %}
        - https://{{ hostvars[host].ansible_host }}:2379
        {% endfor %}
      caFile: /etc/kubernetes/pki/etcd/ca.crt
      certFile: /etc/kubernetes/pki/apiserver-etcd-client.crt
      keyFile: /etc/kubernetes/pki/apiserver-etcd-client.key
  ```
- [x] Модифицировать `roles/master/tasks/main.yaml`:
  - Добавить условие: при `etcd_mode == "external"` использовать шаблон `kubeadm-config-external-etcd.j2`
  - При `etcd_mode == "stacked"` использовать текущий шаблон `kubeadm-config.j2`
  - При `etcd_mode == "external"` — не выполнять `kubeadm config images pull` для etcd-образа (фильтр или `--skip-phases`)
  - При `etcd_mode == "external"` — не генерировать `certificate-key` (он нужен только для stacked etcd)
- [x] Также обновить `kubeadm-config.v4.j2` — заменить `etcd.local` на условный блок для external/stacked (когда шаблон будет раскомментирован)

## 4. Модификация роли `second_controls` — external etcd join

- [x] Модифицировать `roles/second_controls/tasks/join.yaml`:
  - При `etcd_mode == "external"`: добавить `--skip-phases=control-plane-prepare/download-certs`
  - При `etcd_mode == "external"`: не передавать `--certificate-key` (он нужен только для stacked etcd)
  - При `etcd_mode == "external"`: перед join — скопировать PKI-сертификаты (ca.crt, ca.key, front-proxy-ca.crt, front-proxy-ca.key, sa.pub, sa.key) с первого master'а
  - При `etcd_mode == "external"`: удалить node-специфичные сертификаты перед join (apiserver.crt, apiserver-kubelet-client.crt, front-proxy-client.crt)
- [x] Добавить проверку наличия etcd client certs на control plane нодах (ca.crt + apiserver-etcd-client.crt/key) — роль `etcd` уже загружает их при установке

## 5. Модификация роли `upgrade-cluster` — upgrade etcd + k8s

- [x] Создать `roles/upgrade-cluster/tasks/upgrade-etcd.yaml` — rolling upgrade etcd кластера:
  1. Определить текущую версию etcd (через etcdctl endpoint status)
  2. Определить целевую версию etcd (по матрице совместимости с kube_version)
  3. Если версия совпадает — пропустить
  4. Скачать новый image на все etcd ноды (автоматически через ExecStartPre systemd unit)
  5. Обновлять по одной ноде: обновить `etcd_image` в etcd.env → перезапустить → проверить health
  6. После каждой ноды — проверять health всего кластера
  7. Финальная проверка
- [x] Создать `roles/upgrade-cluster/tasks/upgrade-etcd-node.yaml` — upgrade одной ноды etcd
- [x] Модифицировать `roles/upgrade-cluster/tasks/main.yaml`:
  - Добавить шаг upgrade etcd перед upgrade k8s при `etcd_mode == "external"`
  - Запускать upgrade etcd на etcd_nodes (через delegate_to), затем upgrade k8s на k8s_cluster

## 6. Модификация `install-cluster.yaml` — добавить шаг etcd

- [ ] Добавить play для установки external etcd перед установкой master:
  ```yaml
  - name: Install external etcd cluster
    hosts: etcd_nodes
    when: etcd_mode is defined and etcd_mode == "external"
    roles:
      - etcd
    # Генерация сертификатов выполняется на localhost (delegate_to)
    # Загрузка сертификатов на k8s_masters выполняется в рамках этой же роли
  ```
  Порядок:
  1. Checking odd number (существующий)
  2. Install packages (существующий)
  3. **Install external etcd** (новый, при external — включает загрузку etcd-сертификатов на k8s_masters)
  4. Install Control nodes (модифицированный)
  5. Install worker nodes (существующий)

## 7. Модификация `upgrade.yaml` — добавить etcd upgrade

- [ ] Добавить play для upgrade etcd перед upgrade k8s:
  ```yaml
  - name: Upgrade external etcd cluster
    hosts: etcd_nodes
    serial: "1"
    when: etcd_mode is defined and etcd_mode == "external"
    roles:
      - { role: etcd, tags: ['etcd-upgrade'] }
  ```
  Затем существующий play для k8s upgrade.

## 8. Модификация `reset.yaml` — очистка external etcd

- [ ] Добавить задачи для очистки external etcd при `etcd_mode == "external"`:
  - Остановка и отключение etcd сервиса на etcd нодах
  - Удаление systemd unit, контейнера, данных (`/var/lib/etcd`), конфигурации (`/etc/etcd`)
  - Опционально: удаление локальных сертификатов PKI (`files/etcd-pki/`) на Ansible control node
- [ ] Добавить отдельный флаг/переменную для управления очисткой etcd (например, `reset_etcd: false`)

## 9. Документация

- [ ] Обновить `README.md`: добавить секцию про external etcd
- [ ] Обновить `AGENTS.md`: добавить информацию о external etcd, новой роли, переменных
- [ ] Добавить пример инвентори с etcd нодами
- [ ] Добавить информацию о матрице совместимости k8s ↔ etcd версий

## 10. TODO (будущие задачи)

- [ ] Поддержка внешнего CA (предоставление готовых сертификатов)
- [ ] Миграция со stacked etcd на external etcd
- [ ] Backup/restore etcd (snapshot)
- [ ] etcdctl wrapper как Ansible-задача
- [ ] Добавление/удаление etcd members через Ansible
- [ ] Замена отказавшей etcd ноды

---

## Ключевые принципы

- **External etcd — опциональный режим**, по умолчанию `stacked` (обратная совместимость)
- **Сертификаты генерируются на Ansible control node**, распространяются через Ansible
- **etcd upgrade выполняется перед k8s upgrade**
- **Вся логика etcd инкапсулирована в роль `etcd`**

## Источник — проект ../k8sbase/cn/etcd

Референс-проект содержит проверенные bash-скрипты и документацию:
- `scripts/01-etcd-generate-certs.sh` — генерация сертификатов нод
- `scripts/02-etcd-generate-apiserver-certs.sh` — генерация клиентского сертификата apiserver
- `scripts/03-etcd-generate-admin-cert.sh` — генерация административного сертификата
- `scripts/04-etcd-upload-certs.sh` — загрузка сертификатов на ноды
- `scripts/05-etcd-install-container-cluster.sh` — установка etcd в контейнерах
- `scripts/06-etcdctl-container.sh` — etcdctl wrapper
- `scripts/00-etcd-destroy.sh` — полная очистка
- `manifests/01-kubeadm-external-etcd.yaml` — пример kubeadm конфига
