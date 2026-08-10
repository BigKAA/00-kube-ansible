# Контейнеры для предзагрузки (pre-pull) — роль `utils`

Полный список образов контейнеров, которые используются ролью `utils`.
Образы и теги сверены с реальными helm-чартами через `helm template`
для версий из `group_vars/k8s_cluster`.

- В колонке **Переменные** указаны переменные роли (`roles/utils/defaults/main.yaml`
  и `group_vars/k8s_cluster`), из которых формируется образ.
- Если тег берётся из чарта (appVersion), а не из переменной роли — это отмечено
  как `(тег из чарта)`.
- Все образы параметризованы ролью и могут быть перенаправлены в приватный
  registry через переменные.

> Версии (из `group_vars/k8s_cluster` / `scripts/versions.yaml`):
> cert-manager `v1.20.3`, metallb `0.16.1`, argo-cd chart `10.1.2`
> (image `v3.4.4`), reloader chart `2.2.14` (image `v1.4.19`), envoy-gateway
> `v1.8.3`, csi-driver-nfs `4.13.4`, metrics-server `v0.8.1`.
>
> Образы скачиваются автоматически скриптом
> `scripts/download_offline_artifacts.py` (для Cilium — через `helm template`,
> для остальных утилит — helm-чарты содержат образы).

---

## Metrics Server

| registry/container:tag                                 | Переменные                                                                                |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| `registry.k8s.io/metrics-server/metrics-server:v0.8.1` | `metricsServerImageRegistry`<br>`metricsServerImageRepository`<br>`metricsServerImageTag` |

## Cert-manager (v1.20.3)

Все компоненты наследуют `imageRegistry`/`imageNamespace`. Тег = `certManagerVersion`.

| registry/container:tag                                  | Переменные                                                                              |
| ------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `quay.io/jetstack/cert-manager-controller:v1.20.3`      | `certManagerImageRegistry`<br>`certManagerImageNamespace`<br>`certManagerVersion` (тег) |
| `quay.io/jetstack/cert-manager-webhook:v1.20.3`         | `certManagerImageRegistry`<br>`certManagerImageNamespace`<br>`certManagerVersion` (тег) |
| `quay.io/jetstack/cert-manager-cainjector:v1.20.3`      | `certManagerImageRegistry`<br>`certManagerImageNamespace`<br>`certManagerVersion` (тег) |
| `quay.io/jetstack/cert-manager-startupapicheck:v1.20.3` | `certManagerImageRegistry`<br>`certManagerImageNamespace`<br>`certManagerVersion` (тег) |

> Job-образ `cert-manager-acmesolver` используется только при ACME-issuer —
> тянет `quay.io/jetstack/cert-manager-acmesolver:v1.20.3` (те же переменные).

## MetalLB (0.16.1)

| registry/container:tag               | Переменные                                                                                |
| ------------------------------------ | ----------------------------------------------------------------------------------------- |
| `quay.io/metallb/controller:v0.16.1` | `metallbImageRegistry`<br>`metallbImageRepository`<br>`metallbChartVersion` (тег)         |
| `quay.io/metallb/speaker:v0.16.1`    | `metallbImageRegistry`<br>`metallbImageRepository`<br>`metallbChartVersion` (тег)         |
| `quay.io/metallb/frr-k8s:v0.0.25`    | `metallbFrrK8sImageRegistry`<br>`metallbFrrK8sImageRepository`<br>`metallbFrrK8sImageTag` |
| `quay.io/frrouting/frr:10.4.3`       | `metallbFrrImageRegistry`<br>`metallbFrrImageRepository`<br>`metallbFrrImageTag`          |

> Режим BGP по умолчанию в 0.16.x — **frr-k8s** (образ `metallb/frr-k8s`).
> `frrouting/frr` — sidecar/init внутри frr-k8s DaemonSet (deprecated режим
> `frr`, но всё равно используется). Все четыре образа параметризованы.

## ArgoCD (chart 10.1.2)

| registry/container:tag                                 | Переменные                                                                            |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| `quay.io/argoproj/argocd:v3.4.4`                       | `argocdImageRegistry`<br>`argocdImageRepository`<br>(тег `v3.4.4` = appVersion чарта) |
| `ecr-public.aws.com/docker/library/redis:8.2.3-alpine` | `argocdRedisImageRegistry`<br>`argocdRedisImageRepository`<br>`argocdRedisImageTag`   |
| `ghcr.io/dexidp/dex:v2.45.1`                           | `argocdDexImageRegistry`<br>`argocdDexImageRepository`<br>`argocdDexImageTag`         |

> `argocd:v3.4.4` используется всеми компонентами (server, controller,
> repo-server, applicationset, notifications).

## Stakater Reloader (chart 2.2.14)

| registry/container:tag              | Переменные                                                                                 |
| ----------------------------------- | ------------------------------------------------------------------------------------------ |
| `ghcr.io/stakater/reloader:v1.4.19` | `reloaderImageRegistry`<br>`reloaderImageRepository`<br>(тег `v1.4.19` = appVersion чарта) |

## Envoy Gateway (v1.8.2)

| registry/container:tag                    | Переменные                                                                                   |
| ----------------------------------------- | -------------------------------------------------------------------------------------------- |
| `docker.io/envoyproxy/gateway:v1.8.2`     | `envoyGatewayImageRegistry` (registry)<br>`envoyGatewayVersion` (тег)                        |
| `docker.io/envoyproxy/ratelimit:1e50889b` | `envoyRatelimitImageRegistry`<br>`envoyRatelimitImageRepository`<br>`envoyRatelimitImageTag` |

> `global.imageRegistry` переопределяет registry для `gateway`; образ
> `ratelimit` задаётся полностью через `envoyRatelimitImage*` переменные.

## NFS CSI Driver (4.13.4)

`image.baseRepo` (`nfsCsiImageRegistry`) задаёт registry для всех образов.
Теги sidecar — из чарта (registry параметризован, тег — нет).

| registry/container:tag                                          | Переменные                                                                      |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `registry.k8s.io/sig-storage/nfsplugin:v4.13.4`                 | `nfsCsiImageRegistry`<br>`nfsCsiImageRepository`<br>`nfsCSIDriverVersion` (тег) |
| `registry.k8s.io/sig-storage/csi-provisioner:v6.3.0`            | `nfsCsiImageRegistry` (registry)<br>(тег из чарта)                              |
| `registry.k8s.io/sig-storage/csi-resizer:v2.2.0`                | `nfsCsiImageRegistry` (registry)<br>(тег из чарта)                              |
| `registry.k8s.io/sig-storage/csi-snapshotter:v8.6.0`            | `nfsCsiImageRegistry` (registry)<br>(тег из чарта)                              |
| `registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.17.0` | `nfsCsiImageRegistry` (registry)<br>(тег из чарта)                              |
| `registry.k8s.io/sig-storage/livenessprobe:v2.19.0`             | `nfsCsiImageRegistry` (registry)<br>(тег из чарта)                              |

> `snapshot-controller` (registry.k8s.io/sig-storage/snapshot-controller) тянет
> только если включён VolumeSnapshot (по умолчанию off — образ можно исключить).
