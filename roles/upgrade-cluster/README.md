# Роль: upgrade-cluster

Поузловое обновление Kubernetes кластера (serial: 1).

## Процедура

1. Последовательно обновляются control plane ноды (serial: 1)
2. Последовательно обновляются worker ноды (serial: 1)
3. На первой control node — upgrade CNI (Cilium helm upgrade) и утилит

Для каждой ноды:

- Сравнивается текущая версия с целевой (`_version-check.yaml`)
- При совпадении — нода пропускается (`meta: end_host`)
- Обновляются пакеты kubeadm/kubelet/kubectl (`_update-repo.yaml`)
- Выполняется drain → upgrade → restart kubelet → uncordon

После upgrade нод, на первой control node (`upgrade-cni-utils.yaml`):

- Helm upgrade Cilium до версии по новой матрице k8s
- Повторный запуск роли utils (идемпотентный helm upgrade всех утилит)

## Task-файлы

- `main.yaml` — диспетчер: 1st master → other masters → workers
- `_version-check.yaml` — сравнение версий, skip при совпадении
- `_update-repo.yaml` — обновление RPM-пакетов (dnf)
- `upgrade-1st-master.yaml` — `kubeadm upgrade apply`
- `upgrade-other-masters.yaml` — `kubeadm upgrade node`
- `upgrade-workers.yaml` — `kubeadm upgrade node`
- `upgrade-cni-utils.yaml` — upgrade CNI + утилит на masters[0]

## Зависимости

- Кластер должен быть установлен (`install-cluster.yaml`)
- Новая `kube_version` задана в `group_vars/k8s_cluster`
