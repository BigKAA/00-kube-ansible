# Upgrade kubernetes cluster

Процедура обновления кластера:

1. Обновляется external etcd (если используется)
2. Последовательно обновляются control plane ноды (serial: 1)
3. Последовательно обновляются worker ноды (serial: 1)

Для каждой ноды:

- Сравнивается текущая версия с целевой
- При совпадении — нода пропускается
- Обновляются пакеты kubeadm/kubelet/kubectl
- Выполняется drain → upgrade → restart → uncordon
