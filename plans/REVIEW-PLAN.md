# План работ — Ревизия проекта kube-ansible

> Дата создания: 2026-05-17
> Приоритеты: 1. Удобство использования · 2. Качество документации · 3. Расширяемость

---

## Фаза 1 — Быстрые победы (1–2 дня)

### 1.2 Автоматический `cri_socket`
- [x] Вычислять `cri_socket` автоматически на основе переменной `cri`
- [x] Убрать ручное раскомментирование из `group_vars/k8s_cluster`
- [x] Файлы: `group_vars/k8s_cluster`

### 1.3 Автоматический `crio_version`
- [x] Создать матрицу совместимости k8s → crio_version (аналогично etcd)
- [x] Автоматическое определение версии при отсутствии явного указания
- [x] Файлы: `group_vars/k8s_cluster`, `roles/prepare-hosts/vars/`

### 1.6 Информативные сообщения
- [x] Добавить debug-сообщения в начало `install-cluster.yaml`: что будет установлено (CRI, CNI, режим etcd, кол-во нод)
- [x] Добавить assert'ы с понятными сообщениями об ошибках
- [x] Файлы: `install-cluster.yaml`

### 1.7 Переключение inventory + Makefile
- [x] Убрать отладочный комментарий из `ansible.cfg`
- [x] Создать Makefile с targets: `make install ENV=homelab`, `make reset ENV=homelab` и т.д.
- [x] Файлы: `ansible.cfg`, `Makefile`

### 2.4 Убрать мёртвый код
- [x] Удалить закомментированные блоки: `kubeadm-config.v4.j2`, `calicoctl` в `roles/master/tasks/main.yaml`
- [x] Удалить закомментированный `crio-net.j2` и старые URL в `roles/prepare-hosts/tasks/crio.yaml`
- [x] Удалить закомментированный sleep в `roles/upgrade-cluster/tasks/upgrade-1st-master.yaml`
- [x] Удалить закомментированный альтернативный kubeadm init в `roles/master/tasks/calico.yaml`
- [x] Удалить закомментированные старые URL репозитория k8s в `roles/prepare-hosts/tasks/main.yaml`

### 2.5 Исправить ошибки в документации
- [x] `hosts.yml` → `hosts.yaml` в README.md
- [x] `ePBF` → `eBPF` в `group_vars/k8s_cluster`
- [x] `group_vars\k8s_cluster` → `group_vars/k8s_cluster` (обратный слеш) в README.md
- [x] Актуализировать `ansible-core<2.17` в README.md
- [x] Дописать незавершённый раздел «Сервисные функции» в README.md
- [x] `cluser` → `cluster` в README.md и roles/upgrade-cluster/README.md
- [x] `Nothing todo` → `Nothing to do` (3 файла upgrade-cluster)
- [x] `1.3x` → `1.30` в README.md
- [x] Обновить roles/upgrade-cluster/README.md (было 2 строки)

### 3.5 Унификация FQCN
- [x] Заменить все `command:` → `ansible.builtin.command:`
- [x] Заменить все `shell:` → `ansible.builtin.shell:`
- [x] Заменить все `file:` → `ansible.builtin.file:`
- [x] Заменить все `debug:` → `ansible.builtin.debug:`
- [x] Заменить все `template:` → `ansible.builtin.template:`
- [x] Заменить все `systemd:` → `ansible.builtin.systemd:`
- [x] Заменить все `yum_repository:` → `ansible.builtin.yum_repository:`
- [x] Заменить все `set_fact:` → `ansible.builtin.set_fact:`
- [x] Заменить все `include_tasks:` → `ansible.builtin.include_tasks:`
- [x] Заменить все `meta:` → `ansible.builtin.meta:`
- [x] Заменить все `systemd:` → `ansible.builtin.systemd:`
- [x] Заменить все `yum_repository:` → `ansible.builtin.yum_repository:`
- [x] Заменить все `dnf:` → `ansible.builtin.dnf:` (нет в основном проекте)
- [x] Заменить все `apt:` → `ansible.builtin.apt:` (нет в основном проекте)
- [x] Заменить все `stat:` → `ansible.builtin.stat:` (нет в основном проекте)
- [x] Заменить все `fail:` → `ansible.builtin.fail:` (нет в основном проекте)
- [x] Заменить все `assert:` → `ansible.builtin.assert:` (нет в основном проекте)
- [x] Заменить все `set_fact:` → `ansible.builtin.set_fact:`
- [x] Заменить все `include_tasks:` → `ansible.builtin.include_tasks:`
- [x] Заменить все `get_url:` → `ansible.builtin.get_url:` (нет в основном проекте)
- [x] Заменить все `lineinfile:` → `ansible.builtin.lineinfile:` (нет в основном проекте)
- [x] Заменить все `replace:` → `ansible.builtin.replace:` (нет в основном проекте)
- [x] Заменить все `unarchive:` → `ansible.builtin.unarchive:` (нет в основном проекте)
- [x] Заменить все `wait_for:` → `ansible.builtin.wait_for:` (нет в основном проекте)
- [x] Заменить все `uri:` → `ansible.builtin.uri:` (нет в основном проекте)
- [x] Заменить все `meta:` → `ansible.builtin.meta:`
- [x] Заменить все `slurp:` → `ansible.builtin.slurp:` (нет в основном проекте)

> **Примечание:** `k3s-playbook/` — отдельный проект, FQCN в нём не приводились.

---

## Фаза 2 — Основная работа (3–5 дней)

### 1.1 Pre-flight проверки
- [ ] Проверка SSH connectivity (ansible.builtin.ping)
- [ ] Проверка Python3 на remote хостах
- [ ] Проверка NTP синхронизации (chronyc / ntpq)
- [ ] Проверка что порты не заняты (6443, ha_cluster_virtual_port, 2379–2380)
- [ ] Проверка нечётности k8s_masters (уже есть, улучшить сообщение)
- [ ] Проверка нечётности etcd_nodes при `etcd_mode: external`
- [ ] Проверка `kube_version` в допустимом диапазоне (1.28–1.36)
- [ ] Проверка `ha_cluster_virtual_port != 6443`
- [ ] Проверка отсутствия пересечения service_cidr и pod_network_cidr
- [ ] Файлы: `install-cluster.yaml` (новый play в начале)

### 1.4 Разделить group_vars
- [ ] Создать `group_vars/all/defaults.yaml` — дефолтные значения (CIDR, версии, образы)
- [ ] Создать `group_vars/all/user-config.yaml` — что пользователь должен настроить (IP, домены, пароли)
- [ ] Убрать хардкод IP-адресов из дефолтов (NFS, MetalLB, ArgoCD URL, HA virtual IP)
- [ ] Убрать дубли переменных между `group_vars/k8s_cluster` и `group_vars/etcd_nodes`
- [ ] Файлы: `group_vars/`

### 1.5 Примеры конфигураций
- [ ] Создать `examples/single-node/hosts.yaml` + `group_vars/`
- [ ] Создать `examples/ha-stacked/hosts.yaml` + `group_vars/`
- [ ] Создать `examples/ha-external-etcd/hosts.yaml` + `group_vars/`
- [ ] Создать `hosts.template.yaml` с placeholder'ами
- [ ] Файлы: `examples/`, `hosts.template.yaml`

### 2.1 Переписать README.md
- [ ] Добавить секцию «Быстрый старт» — single-node кластер за 5 минут
- [ ] Добавить «Требования к хостам» (минимальные CPU/RAM/disk)
- [ ] Добавить «Сетевые требования» (порты между нодами)
- [ ] Добавить таблицу всех переменных с описанием, дефолтами и примерами
- [ ] Добавить описание сервисных плейбуков `services/01–06`
- [ ] Добавить Troubleshooting / FAQ секцию
- [ ] Добавить описание структуры ролей
- [ ] Актуализировать таблицу совместимости дистрибутивов
- [ ] Файлы: `README.md`

### 2.2 Документировать роли
- [ ] Создать `roles/prepare-hosts/README.md`
- [ ] Создать `roles/master/README.md`
- [ ] Создать `roles/ha/README.md`
- [ ] Создать `roles/workers/README.md`
- [ ] Создать `roles/second_controls/README.md`
- [ ] Создать `roles/utils/README.md`
- [ ] Создать `roles/etcd/README.md`
- [ ] Обновить `roles/upgrade-cluster/README.md` (сейчас 2 строки)

### 2.3 Убрать дубли в конфигурации
- [ ] Матрица etcd — оставить только в `roles/etcd/defaults/main.yaml`
- [ ] Убрать дубль `etcd_image` из `group_vars/k8s_cluster`
- [ ] Убрать дубль `etcd_ca_days`, `etcd_cert_days` из `group_vars/k8s_cluster`
- [ ] Убрать дубль `etcd_initial_cluster_token` из `group_vars/k8s_cluster`
- [ ] Убрать дубль `etcd_quota_backend_bytes` из `group_vars/k8s_cluster`
- [ ] В README.md — ссылка на файл с матрицей вместо дублирования таблицы

---

## Фаза 3 — Архитектура (5–7 дней)

### 3.1 Абстракция пакетных менеджеров
- [ ] Создать `roles/prepare-hosts/vars/RedHat.yaml` — карта пакетов для RedHat
- [ ] Создать `roles/prepare-hosts/vars/Debian.yaml` — карта пакетов для Debian
- [ ] Заменить дубли dnf/apt задач на единые задачи с `include_vars`
- [ ] Обновить `roles/prepare-hosts/tasks/containerd.yaml`
- [ ] Обновить `roles/prepare-hosts/tasks/crio.yaml`
- [ ] Обновить `roles/ha/tasks/main.yml`
- [ ] Обновить `reset.yaml`
- [ ] Файлы: `roles/prepare-hosts/vars/`, `roles/prepare-hosts/tasks/`, `roles/ha/`, `reset.yaml`

### 3.2 Матрица совместимости CNI
- [ ] Добавить k8s ↔ Calico version matrix
- [ ] Добавить k8s ↔ Flannel version matrix
- [ ] Автоматическое определение версии CNI по `kube_version`
- [ ] Файлы: `group_vars/k8s_cluster` или `roles/master/defaults/main.yaml`

### 3.3 Вынести upgrade-логику в общие задачи
- [ ] Создать `roles/upgrade-cluster/tasks/_common.yaml` — общая логика обновления репозитория
- [ ] Создать `roles/upgrade-cluster/tasks/_version-check.yaml` — общая проверка версии
- [ ] Обновить `upgrade-1st-master.yaml` — использовать общие задачи
- [ ] Обновить `upgrade-other-masters.yaml` — использовать общие задачи
- [ ] Обновить `upgrade-workers.yaml` — использовать общие задачи
- [ ] Файлы: `roles/upgrade-cluster/tasks/`

### 3.4 Точки расширения (hooks)
- [ ] Добавить `pre_prepare_tasks` / `post_prepare_tasks` в group_vars
- [ ] Добавить `pre_master_init_tasks` / `post_master_init_tasks`
- [ ] Добавить `pre_worker_join_tasks` / `post_worker_join_tasks`
- [ ] Включить хуки в соответствующие роли через `include_tasks`
- [ ] Файлы: `group_vars/all/hooks.yaml`, роли

### 3.6 Заменить shell/command на нативные модули
- [ ] `containerd.yaml`: заменить `sed` для config.toml на `ansible.builtin.lineinfile` или template
- [ ] `containerd.yaml`: заменить `containerd config default > ...` на template
- [ ] `prepare-hosts/main.yaml`: заменить `swapon --show | wc -l` на `ansible.builtin.command` без pipe
- [ ] `prepare-hosts/main.yaml`: заменить `systemctl list-unit-files firewalld` на `ansible.builtin.service_facts`
- [ ] `prepare-hosts/main.yaml`: убрать `setenforce 0` (уже есть модуль `selinux`)
- [ ] `utils/tasks/main.yaml`: заменить `mv helm` на `ansible.builtin.copy` с `remote_src: true`
- [ ] `utils/tasks/main.yaml`: заменить `helm plugin list | grep` на `ansible.builtin.stat`
- [ ] `reset.yaml`: заменить копирование + shell скрипт на `ansible.builtin.script`
- [ ] Файлы: `roles/prepare-hosts/tasks/`, `roles/utils/tasks/`, `reset.yaml`

---

## Фаза 4 — По необходимости

### 2.6 Стандарт языка документации
- [ ] Определиться: русский (по AGENTS.md) или английский
- [ ] Перевести комментарии в `group_vars/k8s_cluster` (сейчас английский)
- [ ] Унифицировать комментарии во всех ролях

### 2.7 Комментарии в шаблонах
- [ ] Добавить комментарии в `kubeadm-config.j2`
- [ ] Добавить комментарии в `kubeadm-config-external-etcd.j2`
- [ ] Добавить комментарии в `haproxy.j2`
- [ ] Добавить комментарии в `keepalived.j2`
- [ ] Добавить комментарии в `etcd.service.j2`
- [ ] Добавить комментарии в `etcd.env.j2`
- [ ] Добавить комментарии в `calico.j2`
- [ ] Добавить комментарии в `flannel.j2`

### 3.7 Расширенный offline режим
- [ ] Добавить поддержку `.deb` offline (Debian/Ubuntu)
- [ ] Добавить offline для CRI (containerd, crio)
- [ ] Добавить offline для CNI (Calico, Flannel)
- [ ] Добавить offline для утилит (Helm, cert-manager и др.)
- [ ] Файлы: `roles/prepare-hosts/`, `roles/master/`, `roles/utils/`

---

## Сводка прогресса

| Фаза | Задач | Выполнено | Осталось | Прогресс |
|------|-------|-----------|----------|----------|
| Фаза 1 — Быстрые победы | 7 | 7 | 0 | 100% |
| Фаза 2 — Основная работа | 6 | 0 | 6 | 0% |
| Фаза 3 — Архитектура | 6 | 1 | 5 | 17% |
| Фаза 4 — По необходимости | 3 | 0 | 3 | 0% |
| **Итого** | **22** | **8** | **14** | **36%** |
