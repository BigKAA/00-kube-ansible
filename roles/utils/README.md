# Роль: utils

Установка утилит и дополнений на Kubernetes кластер.

## Что делает

- Устанавливает Helm + плагин helm-diff
- Устанавливает PriorityClass для системных компонентов
- Устанавливает (опционально):
  - cert-manager
  - Metrics Server
  - NFS Subdir External Provisioner
  - MetalLB
  - Ingress Nginx
  - ArgoCD

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `helmVersion` | `v3.16.3` | Версия Helm |
| `nfsEnable` | `true` | Включить NFS provisioner |
| `nfsServerHost` | `192.168.218.170` | Адрес NFS сервера |
| `nfsServerPath` | `/var/nfs-disk` | Путь на NFS сервере |
| `certManagerEnable` | `true` | Включить cert-manager |
| `certManagerVersion` | `v1.17.1` | Версия cert-manager |
| `metricsServerEnable` | `true` | Включить Metrics Server |
| `metallbEnable` | `true` | Включить MetalLB |
| `metallbChartVersion` | `v0.14.8` | Версия MetalLB |
| `metallbAddresses` | см. group_vars | Диапазон IP для MetalLB |
| `ingressControllerEnable` | `true` | Включить Ingress Nginx |
| `argoCDEnable` | `true` | Включить ArgoCD |
| `argoCDChartVersion` | `7.8.7` | Версия ArgoCD |
| `argoCDURL` | `argocd.kryukov.local` | URL ArgoCD |
| `argoCDAdminPassword` | см. group_vars | Bcrypt hash пароля ArgoCD |

## Зависимости

- Рабочий Kubernetes кластер с настроенным kubectl
- Helm устанавливается автоматически

## Примечания

Роль выполняется только на первом control plane (`k8s_masters[0]`).
Каждая утилита включается/отключается отдельной переменной `*Enable`.
