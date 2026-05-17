# Роль: utils

Установка утилит и дополнений на Kubernetes кластер.

## Что делает

- Устанавливает Helm v4 + плагин helm-diff
- Устанавливает PriorityClass для системных компонентов
- Устанавливает (опционально):
  - cert-manager (через OCI Helm chart)
  - Metrics Server
  - NFS CSI Driver (динамическое provisioning)
  - MetalLB
  - Ingress Nginx
  - Envoy Gateway (Gateway API)
  - Stakater Reloader
  - ArgoCD

## Переменные

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `helmVersion` | `v4.0.4` | Версия Helm |
| `nfsEnable` | `true` | Включить NFS CSI Driver |
| `nfsCSIDriverVersion` | `4.13.2` | Версия NFS CSI Driver |
| `nfsServerHost` | `192.168.218.170` | Адрес NFS сервера |
| `nfsServerPath` | `/var/nfs-disk` | Путь на NFS сервере |
| `nfsStorageClassName` | `managed-nfs-storage` | Имя StorageClass |
| `nfsReclaimPolicy` | `Delete` | Политика удаления PV |
| `nfsArchiveOnDelete` | `false` | Архивировать при удалении |
| `nfsMountOptions` | `["nfsvers=4.1"]` | Опции монтирования NFS |
| `certManagerEnable` | `true` | Включить cert-manager |
| `certManagerVersion` | `v1.19.2` | Версия cert-manager |
| `certManagerEnableGatewayAPI` | `false` | Включить поддержку Gateway API |
| `metricsServerEnable` | `true` | Включить Metrics Server |
| `metallbEnable` | `true` | Включить MetalLB |
| `metallbChartVersion` | `0.15.3` | Версия MetalLB Helm chart |
| `metallbAddresses` | см. group_vars | Диапазон IP для MetalLB |
| `ingressControllerEnable` | `true` | Включить Ingress Nginx |
| `ingressControllerChartVersion` | `4.12.0` | Версия Ingress Nginx chart |
| `envoyGatewayEnable` | `false` | Включить Envoy Gateway |
| `envoyGatewayVersion` | `v1.8.0` | Версия Envoy Gateway |
| `envoyGatewayReplicas` | `1` | Количество реплик Envoy Gateway |
| `envoyGatewayLoadBalancerIP` | `192.168.218.180` | IP для EnvoyProxy Service |
| `envoyGatewayDomain` | `kryukov.lan` | Домен для Gateway TLS |
| `reloaderEnable` | `false` | Включить Stakater Reloader |
| `reloaderChartVersion` | `2.2.11` | Версия Reloader chart |
| `reloaderReloadStrategy` | `annotations` | Стратегия перезагрузки |
| `argoCDEnable` | `true` | Включить ArgoCD |
| `argoCDChartVersion` | `9.5.14` | Версия ArgoCD chart |
| `argoCDURL` | `argocd.kryukov.local` | URL ArgoCD |
| `argoCDAdminPassword` | см. group_vars | Bcrypt hash пароля ArgoCD |

## Offline-режим

При `k8s_install_mode: "offline"`:

- Helm скачивается из локального архива вместо `get.helm.sh`
- Плагин helm-diff устанавливается из локальной копии
- cert-manager манифест устанавливается из OCI чарта (локальный `.tgz`)
- Helm-чарты (MetalLB, Ingress Nginx, ArgoCD, NFS CSI Driver, Reloader, Envoy Gateway) устанавливаются из локальных `.tgz`

Каталоги offline-артефактов:

```text
tmp/offline/utils/
├── helm-*.tar.gz              # бинарный архив Helm
├── cert-manager-*.tgz         # OCI чарт cert-manager
├── helm-charts/
│   ├── metallb-*.tgz          # чарт MetalLB
│   ├── ingress-nginx-*.tgz    # чарт Ingress Nginx
│   ├── argo-cd-*.tgz          # чарт ArgoCD
│   ├── csi-driver-nfs-*.tgz   # чарт NFS CSI Driver
│   ├── reloader-*.tgz         # чарт Stakater Reloader
│   └── envoy-gateway-*.tgz    # OCI чарт Envoy Gateway
└── helm-plugins/
    └── helm-diff/             # плагин helm-diff
```

## Зависимости

- Рабочий Kubernetes кластер с настроенным kubectl
- Helm устанавливается автоматически
- cert-manager требуется для Envoy Gateway TLS

## Примечания

Роль выполняется только на первом control plane (`k8s_masters[0]`).
Каждая утилита включается/отключается отдельной переменной `*Enable`.

### Миграция с nfs-subdir-external-provisioner

Если вы обновляетесь с предыдущей версии, где использовался
`nfs-subdir-external-provisioner`:

1. Новый CSI Driver NFS создаёт StorageClass с именем `managed-nfs-storage`
   (совпадает со старым именем).
2. Существующие PVC продолжат работать — старый provisioner не удаляется
   автоматически.
3. Для полного перехода удалите старый StorageClass и deployment
   `nfs-client-provisioner` после проверки работы CSI Driver.

### Gateway API vs Ingress Nginx

Роль поддерживает оба ingress controller одновременно:

- **Ingress Nginx** — классический ingress controller, проверенный временем
- **Envoy Gateway** — современный Gateway API controller от Envoy Proxy

Для использования Envoy Gateway установите `envoyGatewayEnable: true`.
Gateway создаётся с TLS сертификатом от cert-manager (ClusterIssuer `dev-ca-issuer`).
