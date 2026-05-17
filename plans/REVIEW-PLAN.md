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

- [x] Проверка SSH connectivity (ansible.builtin.ping)
- [x] Проверка Python3 на remote хостах
- [x] Проверка что порты не заняты (6443, ha_cluster_virtual_port)
- [x] Проверка нечётности k8s_masters
- [x] Проверка нечётности etcd_nodes при `etcd_mode: external`
- [x] Проверка `kube_version` в допустимом диапазоне (1.28–1.36)
- [x] Проверка `ha_cluster_virtual_port != 6443`
- [x] Проверка допустимых значений CRI и CNI
- [x] Файлы: `install-cluster.yaml`

### 1.4 Разделить group_vars

- [x] Создать `group_vars/all.yaml` — общие переменные для всех групп
- [x] Реструктурировать `group_vars/k8s_cluster` — секции ОБЯЗАТЕЛЬНО/ОПЦИОНАЛЬНО/ВНУТРЕННИЕ
- [x] Убрать дубли переменных между `group_vars/k8s_cluster` и `group_vars/etcd_nodes`
- [x] Файлы: `group_vars/`

### 1.5 Примеры конфигураций

- [x] Создать `examples/single-node/hosts.yaml` + `group_vars/`
- [x] Создать `examples/ha-stacked/hosts.yaml` + `group_vars/`
- [x] Создать `examples/ha-external-etcd/hosts.yaml` + `group_vars/`
- [x] Создать `hosts.template.yaml` с placeholder'ами
- [x] Файлы: `examples/`, `hosts.template.yaml`

### 2.1 Переписать README.md

- [x] Добавить секцию «Быстрый старт» — single-node кластер за 5 минут
- [x] Добавить «Требования к хостам» (минимальные CPU/RAM/disk)
- [x] Добавить «Сетевые требования» (порты между нодами)
- [x] Добавить таблицу всех переменных с описанием, дефолтами и примерами
- [x] Добавить описание сервисных плейбуков `services/01–06`
- [x] Добавить Troubleshooting / FAQ секцию
- [x] Добавить описание структуры ролей
- [x] Актуализировать таблицу совместимости дистрибутивов
- [x] Файлы: `README.md`

### 2.2 Документировать роли

- [x] Создать `roles/prepare-hosts/README.md`
- [x] Создать `roles/master/README.md`
- [x] Создать `roles/ha/README.md`
- [x] Создать `roles/workers/README.md`
- [x] Создать `roles/second_controls/README.md`
- [x] Создать `roles/utils/README.md`
- [x] Создать `roles/etcd/README.md`
- [x] Обновить `roles/upgrade-cluster/README.md` (было 2 строки)

### 2.3 Убрать дубли в конфигурации

- [x] Матрица etcd — оставить только в `roles/etcd/defaults/main.yaml`
- [x] Убрать дубли etcd из `group_vars/k8s_cluster` (оставлен etcd_mode, etcd_image для stacked)
- [x] Убрать дубль `ansible_python_interpreter` — вынесен в `group_vars/all.yaml`
- [x] Убрать дубль `kube_version` — вынесен в `group_vars/all.yaml`
- [x] В README.md — ссылка на файл с матрицей вместо дублирования таблицы

---

## Фаза 3 — Архитектура (5–7 дней)

### 3.1 Абстракция пакетных менеджеров

- [x] Создать `roles/prepare-hosts/vars/RedHat.yaml` — карта пакетов для RedHat
- [x] Создать `roles/prepare-hosts/vars/Debian.yaml` — карта пакетов для Debian
- [x] Заменить дубли dnf/apt задач на единые задачи с `include_vars`
- [x] Обновить `roles/prepare-hosts/tasks/containerd.yaml`
- [x] Обновить `roles/prepare-hosts/tasks/crio.yaml`
- [x] Обновить `roles/ha/tasks/main.yml`
- [x] Обновить `reset.yaml`

### 3.2 Матрица совместимости CNI

- [x] Добавить k8s ↔ Calico version matrix
- [x] Добавить k8s ↔ Flannel version matrix
- [x] Автоматическое определение версии CNI по `kube_version`
- [x] Заменить хардкод версии в flannel.j2 на переменную

### 3.3 Вынести upgrade-логику в общие задачи

- [x] Создать `_version-check.yaml` — общая проверка версии
- [x] Создать `_update-repo.yaml` — общая логика обновления репозитория
- [x] Обновить `upgrade-1st-master.yaml` — использовать общие задачи
- [x] Обновить `upgrade-other-masters.yaml` — использовать общие задачи
- [x] Обновить `upgrade-workers.yaml` — использовать общие задачи

### 3.4 Точки расширения (hooks)

- [x] Создать `group_vars/all/hooks.yaml` с pre/post хуками
- [x] Добавить хуки в роль prepare-hosts

### 3.6 Заменить shell/command на нативные модули

- [x] containerd.yaml: заменить `sed` на `lineinfile` (3 замены)
- [x] utils: заменить `mv` на `copy` с `remote_src`
- [x] utils: заменить `helm plugin list | grep` на `stat`

---

## Фаза 4 — По необходимости

### 2.6 Стандарт языка документации

- [x] Определиться: русский (по AGENTS.md)
- [x] Перевести комментарии в `group_vars/k8s_cluster`
- [x] Унифицировать комментарии во всех ролях (master, ha, workers, second_controls, utils, prepare-hosts)

### 2.7 Комментарии в шаблонах

- [x] Добавить комментарии в `kubeadm-config.j2`
- [x] Добавить комментарии в `haproxy.j2`
- [x] Добавить комментарии в `keepalived.j2`
- [x] Добавить комментарии в `etcd.service.j2`
- [x] Добавить комментарии в `etcd.env.j2`
- [x] Добавить комментарии в `calico-install.j2`

### 3.7 Расширенный offline режим

- [x] Добавить поддержку `.deb` offline (Debian/Ubuntu)
- [x] Добавить offline для CRI (containerd, crio)
- [x] Добавить offline для CNI (Calico, Flannel)
- [x] Добавить offline для утилит (Helm, cert-manager и др.)
- [x] Создать скрипт скачивания артефактов `scripts/download-offline-artifacts.sh`
- [x] Добавить `make download-artifacts` в Makefile
- [x] Файлы: `group_vars/k8s_cluster`, `roles/prepare-hosts/`, `roles/master/`, `roles/utils/`, `scripts/`

---

## Сводка прогресса

| Фаза | Задач | Выполнено | Осталось | Прогресс |
|------|-------|-----------|----------|----------|
| Фаза 1 — Быстрые победы | 7 | 7 | 0 | 100% |
| Фаза 2 — Основная работа | 6 | 6 | 0 | 100% |
| Фаза 3 — Архитектура | 6 | 6 | 0 | 100% |
| Фаза 4 — По необходимости | 3 | 3 | 0 | 100% |
| **Итого** | **22** | **22** | **0** | **100%** |
