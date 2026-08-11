# Роль: utils

Установка утилит, CLI-инструментов и аддонов на первой control node.
Версии — из [`scripts/versions.yaml`](../../scripts/versions.yaml).

## Что делает

- Устанавливает Helm + плагин helm-diff
- Устанавливает CLI-инструменты: cilium CLI (при cni=cilium), yq, stern
- Настраивает приватный registry (imagePullSecrets) при включении
- Устанавливает PriorityClass для системных компонентов
- Устанавливает (опционально, через enable-флаги):
  - cert-manager (через OCI Helm chart)
  - Metrics Server
  - NFS CSI Driver (динамическое provisioning)
  - MetalLB
  - Stakater Reloader
  - Envoy Gateway (Gateway API)
  - ArgoCD

## Структура task-файлов

Роль разбита на отдельные task-файлы, `main.yaml` — диспетчер
(последовательный include_tasks по порядку зависимостей):

```text
tasks/
├── main.yaml           # диспетчер: include_tasks по порядку
├── helm.yaml           # Helm + helm-diff
├── cli-tools.yaml      # cilium CLI, yq, stern (jq — через packages_common)
├── registry.yaml       # приватный registry (imagePullSecrets)
├── priorityclass.yaml  # PriorityClasses
├── cert-manager.yaml   # cert-manager + Issuer
├── metrics-server.yaml # Metrics Server (raw-манифест)
├── nfs-csi.yaml        # NFS CSI Driver
├── reloader.yaml       # Stakater Reloader
├── loadbalancer.yaml   # LoadBalancer (Cilium L2 для cilium / MetalLB для flannel)
├── envoy-gateway.yaml  # Envoy Gateway (Gateway API)
└── argocd.yaml         # ArgoCD
```

Порядок учитывает зависимости: cert-manager → до envoy-gateway (TLS).

## Переменные

Значения по умолчанию — в `group_vars/k8s_cluster` (canonical-источник
версий — `scripts/versions.yaml`).

| Переменная | Описание |
|------------|----------|
| `helmVersion` | Версия Helm |
| `ciliumCliVersion` | Версия cilium CLI (только при cni=cilium) |
| `yqVersion` | Версия yq |
| `sternVersion` | Версия stern |
| `nfsEnable` | Включить NFS CSI Driver |
| `nfsCSIDriverVersion` | Версия NFS CSI Driver |
| `nfsServerHost` / `nfsServerPath` | Адрес/путь NFS сервера |
| `certManagerEnable` / `certManagerVersion` | cert-manager |
| `metricsServerEnable` | Включить Metrics Server |
| `metallbEnable` / `metallbChartVersion` | MetalLB |
| `reloaderEnable` / `reloaderChartVersion` | Stakater Reloader |
| `envoyGatewayEnable` / `envoyGatewayVersion` | Envoy Gateway |
| `argoCDEnable` / `argoCDChartVersion` | ArgoCD |

## Приватный registry (закрытое окружение)

Роль поддерживает установку образов из закрытого registry. Включается
блоком `utils_registry` (см. `roles/utils/defaults/main.yaml`):

```yaml
utils_registry:
    enabled: true
    server: "harbor.corp.local:8443"
    username: "robot$pull"
    password: "CHANGE_ME"
    pull_secret_name: "utils-pull-secret"
    namespaces:
        - kube-system
        - cert-manager
        - metallb
        - argocd
        - envoy-gateway-system
    helm_oci_login: true
```

При `enabled: true`:

- создаётся `Secret(docker-registry)` во всех неймспейсах из `namespaces`;
- Secret автоматически подключается ко всем утилитам через
  `imagePullSecrets` / `global.imagePullSecrets`;
- выполняется `helm registry login` для приватных OCI-чартов
  (cert-manager, envoy-gateway).

Переопределение registry/образа для каждой утилиты — через переменные
`*ImageRegistry` / `*ImageRepository` / `*ImageTag` (см. `defaults/main.yaml`).

## Offline-режим

При `k8s_install_mode: "offline"`:

- Helm и CLI-инструменты — из локальных архивов `tmp/offline/utils/`
- Плагин helm-diff (опционально, `helmDiffEnable: true`) — из локальной копии `tmp/offline/utils/helm-plugins/`
- Helm-чарты утилит — из локальных `.tgz` в `tmp/offline/utils/helm-charts/`
- cert-manager (OCI) — из `tmp/offline/utils/cert-manager-*.tgz`
- Envoy Gateway (OCI) — из `tmp/offline/utils/helm-charts/envoy-gateway-*.tgz`

Каталоги offline-артефактов:

```text
tmp/offline/utils/
├── helm-*.tar.gz                  # Helm (обе arch)
├── cilium-linux-*.tar.gz          # cilium CLI (при cni=cilium)
├── yq_linux_*                     # yq (обе arch)
├── stern_*_linux_*.tar.gz         # stern (обе arch)
├── cert-manager-*.tgz             # OCI чарт cert-manager
├── helm-charts/
│   ├── metallb-*.tgz
│   ├── csi-driver-nfs-*.tgz
│   ├── reloader-*.tgz
│   ├── envoy-gateway-*.tgz        # OCI чарт Envoy Gateway
│   └── argo-cd-*.tgz
└── helm-plugins/
    └── helm-diff/                 # плагин helm-diff
```

## Зависимости

- Рабочий Kubernetes кластер с настроенным kubectl
- Helm устанавливается автоматически (task `helm.yaml`)
- cert-manager требуется для Envoy Gateway TLS

## Примечания

Роль выполняется только на первой control node (`k8s_masters[0]`).
Каждая утилита включается/отключается отдельной переменной `*Enable`.
