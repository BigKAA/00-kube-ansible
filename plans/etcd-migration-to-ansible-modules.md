# План перевода роли etcd с bash-скриптов на модули Ansible

## Обзор

Данный план описывает замену bash-скриптов (команды `openssl`,
`docker run`) на нативные модули Ansible в роли `roles/etcd`.

### Текущее состояние

В роли etcd используются следующие bash-команды через
`ansible.builtin.command`:

| Файл | Команда | Назначение |
| :--- | :--- | :--- |
| `generate-ca.yaml` | `openssl genrsa` | Генерация CA ключа |
| `generate-ca.yaml` | `openssl req -new -x509` | Генерация CA сертификата |
| `_generate-node-cert.yaml` | `openssl genrsa` | Генерация ключа ноды |
| `_generate-node-cert.yaml` | `openssl req -new` | Генерация CSR ноды |
| `_generate-node-cert.yaml` | `openssl x509 -req` | Подпись сертификата |
| `generate-apiserver-cert.yaml` | `openssl genrsa` | Генерация ключа |
| `generate-apiserver-cert.yaml` | `openssl req -new` | Генерация CSR |
| `generate-apiserver-cert.yaml` | `openssl x509 -req` | Подпись сертификата |
| `generate-admin-cert.yaml` | `openssl genrsa` | Генерация ключа admin |
| `generate-admin-cert.yaml` | `openssl req -new` | Генерация CSR admin |
| `generate-admin-cert.yaml` | `openssl x509 -req` | Подпись сертификата |
| `health-check.yaml` | `docker run etcdctl health` | Проверка health |
| `health-check.yaml` | `docker run etcdctl status` | Статус endpoints |
| `health-check.yaml` | `docker run etcdctl members` | Список членов |
| `_renew-node-certs.yaml` | `docker run etcdctl health` | Health после update |
| `install.yaml` | `docker --version` | Проверка Docker |

---

## Этап 1: Замена OpenSSL на `community.crypto`

**Приоритет:** высокий

**Затронутые файлы:**

- `tasks/generate-ca.yaml`
- `tasks/_generate-node-cert.yaml`
- `tasks/generate-apiserver-cert.yaml`
- `tasks/generate-admin-cert.yaml`

**Требуемая коллекция:** `community.crypto`

### 1.1. Генерация CA (`generate-ca.yaml`)

| Текущий bash | Модуль Ansible | Примечание |
| :--- | :--- | :--- |
| `openssl genrsa` | `openssl_privatekey` | `type: RSA` |
| `openssl req -x509` | `openssl_certificate` | `provider: selfsigned` |

Пример замены генерации CA ключа:

```yaml
# Было:
- name: Генерация CA закрытого ключа
  ansible.builtin.command: >
    openssl genrsa
    -out {{ etcd_local_pki_dir }}/{{ etcd_ca_key }}
    {{ etcd_key_size }}
  args:
    creates: "{{ etcd_local_pki_dir }}/{{ etcd_ca_key }}"

# Стало:
- name: Генерация CA закрытого ключа
  community.crypto.openssl_privatekey:
    path: "{{ etcd_local_pki_dir }}/{{ etcd_ca_key }}"
    type: RSA
    size: "{{ etcd_key_size }}"
    mode: "0600"
```

Пример замены генерации CA сертификата:

```yaml
# Было:
- name: Генерация CA самоподписанного сертификата
  ansible.builtin.command: >
    openssl req -new -x509
    -key {{ etcd_local_pki_dir }}/{{ etcd_ca_key }}
    -out {{ etcd_local_pki_dir }}/{{ etcd_ca_crt }}
    -days {{ etcd_ca_days }}
    -subj "/CN=etcd-ca"
    -sha256

# Стало:
- name: Генерация CA сертификата
  community.crypto.openssl_certificate:
    path: "{{ etcd_local_pki_dir }}/{{ etcd_ca_crt }}"
    privatekey_path: "{{ etcd_local_pki_dir }}/{{ etcd_ca_key }}"
    provider: selfsigned
    selfsigned_not_after: "+{{ etcd_ca_days }}d"
    selfsigned_digest: sha256
    selfsigned_subject:
      commonName: etcd-ca
```

### 1.2. Сертификаты нод (`_generate-node-cert.yaml`)

| Текущий bash | Модуль Ansible | Примечание |
| :--- | :--- | :--- |
| `openssl genrsa` | `openssl_privatekey` | Аналогично CA |
| `openssl req -new` | `openssl_csr` | SAN из Jinja |
| `openssl x509 -req` | `openssl_certificate` | `provider: ownca` |

SAN задаются через параметр `subject_alt_name` модуля `openssl_csr`.

Пример замены CSR:

```yaml
# Было:
- name: Генерация CSR
  ansible.builtin.command: >
    openssl req -new
    -key {{ etcd_local_pki_dir }}/{{ _node_short_name }}.key
    -out {{ etcd_local_pki_dir }}/{{ _node_short_name }}.csr
    -config {{ etcd_local_pki_dir }}/{{ _node_short_name }}-openssl.cnf

# Стало:
- name: Генерация CSR ноды
  community.crypto.openssl_csr:
    path: "{{ etcd_local_pki_dir }}/{{ _node_short_name }}.csr"
    privatekey_path: "{{ etcd_local_pki_dir }}/{{ _node_short_name }}.key"
    common_name: "{{ _node_fqdn }}"
    subject_alt_name:
      - "DNS:{{ _node_fqdn }}"
      - "DNS:{{ _node_short_name }}"
      - "IP:{{ _node_ip }}"
      - "IP:127.0.0.1"
    key_usage:
      - keyEncipherment
      - dataEncipherment
      - digitalSignature
    extended_key_usage:
      - serverAuth
      - clientAuth
```

Пример замены подписи сертификата:

```yaml
# Было:
- name: Подпись сертификата CA
  ansible.builtin.command: >
    openssl x509 -req
    -in {{ etcd_local_pki_dir }}/{{ _node_short_name }}.csr
    -CA {{ etcd_local_pki_dir }}/{{ etcd_ca_crt }}
    -CAkey {{ etcd_local_pki_dir }}/{{ etcd_ca_key }}
    -CAcreateserial
    -out {{ etcd_local_pki_dir }}/{{ _node_short_name }}.crt
    -days {{ etcd_cert_days }}
    -sha256
    -extensions v3_req
    -extfile {{ etcd_local_pki_dir }}/{{ _node_short_name }}-openssl.cnf

# Стало:
- name: Подпись сертификата ноды CA
  community.crypto.openssl_certificate:
    path: "{{ etcd_local_pki_dir }}/{{ _node_short_name }}.crt"
    csr_path: "{{ etcd_local_pki_dir }}/{{ _node_short_name }}.csr"
    ownca_path: "{{ etcd_local_pki_dir }}/{{ etcd_ca_crt }}"
    ownca_privatekey_path: "{{ etcd_local_pki_dir }}/{{ etcd_ca_key }}"
    provider: ownca
    ownca_not_after: "+{{ etcd_cert_days }}d"
    ownca_digest: sha256
```

### 1.3. Клиентские сертификаты

Файлы: `generate-apiserver-cert.yaml`, `generate-admin-cert.yaml`.

Аналогично 1.2, но без SAN (только CN и O).

Пример замены CSR для клиентского сертификата:

```yaml
- name: Генерация CSR клиентского сертификата
  community.crypto.openssl_csr:
    path: "{{ etcd_local_pki_dir }}/{{ cert_filename }}.csr"
    privatekey_path: "{{ etcd_local_pki_dir }}/{{ cert_filename }}.key"
    common_name: "{{ cert_cn }}"
    organization_name: "{{ cert_org }}"
    key_usage:
      - keyEncipherment
      - dataEncipherment
      - digitalSignature
    extended_key_usage:
      - clientAuth
```

### 1.4. Удаление временных openssl конфигов

После перехода на модули `community.crypto` шаблоны
`openssl-node.cnf.j2` и `openssl-client.cnf.j2` больше не нужны.
Все параметры задаются напрямую в модулях Ansible.

**Действия:**

- Удалить `templates/openssl-node.cnf.j2`
- Удалить `templates/openssl-client.cnf.j2`
- Удалить задачи создания `.cnf` файлов из task-файлов
- Удалить задачи удаления `.cnf` файлов (cleanup)

---

## Этап 2: Замена health-check команд

**Приоритет:** средний

**Затронутые файлы:**

- `tasks/health-check.yaml`
- `tasks/_renew-node-certs.yaml`

### 2.1. Проверка health через HTTP endpoint

etcd предоставляет HTTP endpoint `/health` для проверки состояния.

| Текущий bash | Модуль Ansible | Примечание |
| :--- | :--- | :--- |
| `docker run etcdctl health` | `ansible.builtin.uri` | GET `/health` |

Пример замены:

```yaml
# Было:
- name: Проверка health кластера etcd
  ansible.builtin.command: >
    docker run --rm --network host ...
    /usr/local/bin/etcdctl --cacert=... --cert=... --key=...
    endpoint health

# Стало (базовая проверка):
- name: Проверка health кластера etcd
  ansible.builtin.uri:
    url: "https://{{ ansible_host }}:2379/health"
    method: GET
    ca_path: "{{ etcd_pki_dir }}/ca.crt"
    client_cert: "{{ etcd_pki_dir }}/server.crt"
    client_key: "{{ etcd_pki_dir }}/server.key"
    status_code: 200
    return_content: true
  register: _etcd_health
  retries: 10
  delay: 10
  until: _etcd_health.json.health == true
```

### 2.2. Статус endpoints и список членов

Для `endpoint status` и `member list` нет прямой замены через HTTP API.
Эти команды возвращают детальную информацию о кластере.

**Рекомендация:** оставить `docker run etcdctl` для этих двух команд,
так как они используются только для вывода информации (debug).

---

## Этап 3: Мелкие улучшения

**Приоритет:** низкий

### 3.1. Проверка наличия Docker (`install.yaml`)

| Текущий bash | Модуль Ansible | Примечание |
| :--- | :--- | :--- |
| `docker --version` | `ansible.builtin.stat` | Проверка бинарника |

Пример замены:

```yaml
# Было:
- name: Проверить наличие Docker
  ansible.builtin.command: docker --version
  register: _docker_check
  changed_when: false
  failed_when: false

# Стало:
- name: Проверить наличие Docker
  ansible.builtin.stat:
    path: /usr/bin/docker
  register: _docker_binary

- name: Ошибка — Docker не установлен
  ansible.builtin.fail:
    msg: "Docker не найден на {{ inventory_hostname }}."
  when: not _docker_binary.stat.exists
```

---

## Зависимости

### Требуемые коллекции

```yaml
# requirements.yaml
collections:
  - name: community.crypto
    version: ">=2.0.0"
  - name: community.general
  - name: ansible.posix
  - name: kubernetes.core
```

### Установка

```bash
ansible-galaxy collection install \
    community.crypto \
    community.general \
    ansible.posix \
    kubernetes.core
```

### Python-пакеты

```bash
pip install cryptography kubernetes docker
```

### Docker-образ

Все коллекции и пакеты уже установлены в `Dockerfile.ansible`.

---

## Сводная таблица изменений

| Файл | Было | Стало | Удалить | Сложность |
| :--- | :--- | :--- | :--- | :--- |
| `generate-ca.yaml` | 5 | 3 | — | Низкая |
| `_generate-node-cert.yaml` | 7 | 5 | `openssl-node.cnf.j2` | Средняя |
| `generate-apiserver-cert.yaml` | 6 | 4 | `openssl-client.cnf.j2` | Низкая |
| `generate-admin-cert.yaml` | 6 | 4 | `openssl-client.cnf.j2` | Низкая |
| `health-check.yaml` | 7 | 5 | — | Средняя |
| `_renew-node-certs.yaml` | 8 | 7 | — | Низкая |
| `install.yaml` | 6 | 6 | — | Низкая |

---

## Порядок выполнения

1. **Подготовка:**
   - Установить `community.crypto` коллекцию
   - Создать бранч `etcd-ansible-modules`

2. **Этап 1 — OpenSSL:**
   - Переписать `generate-ca.yaml`
   - Переписать `_generate-node-cert.yaml`
   - Переписать `generate-apiserver-cert.yaml`
   - Переписать `generate-admin-cert.yaml`
   - Удалить неиспользуемые шаблоны `.cnf.j2`
   - Протестировать на чистом кластере

3. **Этап 2 — Health check:**
   - Переписать проверку health в `health-check.yaml`
   - Переписать проверку health в `_renew-node-certs.yaml`
   - Протестировать rolling update сертификатов

4. **Этап 3 — Мелкие улучшения:**
   - Заменить проверку Docker в `install.yaml`

5. **Валидация:**
   - Запустить `ansible-lint` на роли
   - Провести полное тестирование установки
   - Провести тестирование обновления сертификатов

---

## Риски и замечания

1. **Идемпотентность:** Модули `community.crypto` обеспечивают
   идемпотентность — ключи и сертификаты не будут перегенерированы
   при повторном запуске. Это улучшение по сравнению с текущим
   подходом (`args.creates`).

2. **Совместимость:** Модули `community.crypto` требуют Python с
   OpenSSL bindings. На большинстве систем это уже установлено.

3. **Откат:** При проблемах можно быстро вернуться к bash-командам,
   так как структура playbook останется прежней.

4. **Время выполнения:** Модули Ansible могут работать немного
   медленнее прямых openssl команд, но разница несущественна.
