#!/usr/bin/env bash
# ============================================================
# Скачивание артефактов для offline-установки Kubernetes
# ============================================================
# Использование:
#   ./scripts/download-offline-artifacts.sh [OPTIONS]
#
# Опции:
#   --kube-version VERSION   Версия Kubernetes (по умолчанию: 1.36.1)
#   --cri CRI                CRI: containerd или crio (по умолчанию: containerd)
#   --cni CNI                CNI: calico или flannel (по умолчанию: calico)
#   --helm-version VERSION   Версия Helm (по умолчанию: v4.0.4)
#   --rpm-arch ARCH          Архитектура RPM (по умолчанию: x86_64)
#   --deb-arch ARCH          Архитектура DEB (по умолчанию: amd64)
#   --output DIR             Выходной каталог (по умолчанию: tmp/offline)
#   --help                   Показать справку
#
# Примеры:
#   ./scripts/download-offline-artifacts.sh
#   ./scripts/download-offline-artifacts.sh --kube-version 1.35.0 --cni flannel
#   ./scripts/download-offline-artifacts.sh --cri crio --cni calico
# ============================================================

set -euo pipefail

# Значения по умолчанию
KUBE_VERSION="1.36.2"
CRI="containerd"
CNI="calico"
HELM_VERSION="v4.0.4"
CERT_MANAGER_VERSION="v1.19.2"
METALLB_CHART_VERSION="0.15.3"
INGRESS_NGINX_CHART_VERSION="4.12.0"
ARGOCD_CHART_VERSION="9.5.14"
NFS_CSI_DRIVER_VERSION="4.13.2"
RELOADER_CHART_VERSION="2.2.11"
ENVOY_GATEWAY_VERSION="v1.8.0"
OUTPUT_DIR="tmp/offline"

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --kube-version)   KUBE_VERSION="$2"; shift 2 ;;
        --cri)            CRI="$2"; shift 2 ;;
        --cni)            CNI="$2"; shift 2 ;;
        --helm-version)   HELM_VERSION="$2"; shift 2 ;;
        --cert-manager-version) CERT_MANAGER_VERSION="$2"; shift 2 ;;
        --metallb-chart-version) METALLB_CHART_VERSION="$2"; shift 2 ;;
        --argocd-chart-version) ARGOCD_CHART_VERSION="$2"; shift 2 ;;
        --nfs-csi-driver-version) NFS_CSI_DRIVER_VERSION="$2"; shift 2 ;;
        --rpm-arch)       K8S_RPM_ARCH="$2"; shift 2 ;;
        --deb-arch)       K8S_DEB_ARCH="$2"; shift 2 ;;
        --output)         OUTPUT_DIR="$2"; shift 2 ;;
        --help)
            sed -n '2,/^# =\{5,/p' "$0" | sed 's/^# //; s/^#//' 
            exit 0
            ;;
        *) echo "Неизвестная опция: $1"; exit 1 ;;
    esac
done

KUBE_MAJOR_MINOR=$(echo "$KUBE_VERSION" | grep -oP '^\d+\.\d+')

echo "============================================================"
echo " Скачивание offline-артефактов"
echo "============================================================"
echo " Kubernetes : $KUBE_VERSION"
echo " CRI        : $CRI"
echo " CNI        : $CNI"
echo " Helm       : $HELM_VERSION"
echo " cert-manager: $CERT_MANAGER_VERSION (OCI)"
echo " MetalLB    : $METALLB_CHART_VERSION"
echo " ArgoCD     : $ARGOCD_CHART_VERSION"
echo " NFS CSI    : $NFS_CSI_DRIVER_VERSION"
echo " Reloader   : $RELOADER_CHART_VERSION"
echo " Envoy GW   : $ENVOY_GATEWAY_VERSION"
echo " Выходной каталог: $OUTPUT_DIR"
echo "============================================================"

# Архитектуры (можно переопределить через окружение)
K8S_RPM_ARCH="${K8S_RPM_ARCH:-x86_64}"
K8S_DEB_ARCH="${K8S_DEB_ARCH:-amd64}"

# Создание структуры каталогов
mkdir -p "$OUTPUT_DIR"/{packages,cri/{containerd,crio},cni,images,utils/helm-charts,utils/helm-plugins/helm-diff}

# ============================================================
# Резолв URL пакетов Kubernetes через индексы pkgs.k8s.io
# ============================================================
# Суффикс release в pkgs.k8s.io (OpenBuildService) непредсказуем и
# меняется между версиями (например, 1.36.2→150500.2.1, 1.36.3→150500.1.1).
# Поэтому имя файла определяется динамически из индексов репозитория:
#   RPM — repodata/repomd.xml → primary.xml.gz
#   DEB — Packages.gz

_RPM_PRIMARY_CACHE=""
_RPM_PRIMARY_MM=""
_DEB_PACKAGES_CACHE=""
_DEB_PACKAGES_MM=""

# Скачать и распаковать primary.xml для RPM (с кэшированием по minor-версии)
_fetch_rpm_primary() {
    local mm="$1"
    [[ "$_RPM_PRIMARY_MM" == "$mm" && -n "$_RPM_PRIMARY_CACHE" ]] && return 0

    local base="https://pkgs.k8s.io/core:/stable:/v${mm}/rpm"
    local primary_href
    primary_href=$(curl -fsSL --connect-timeout 30 --max-time 120 \
        "$base/repodata/repomd.xml" 2>/dev/null \
        | grep -oE 'repodata/[^"'"]*-primary\.xml\.gz' | head -n1)
    if [[ -z "$primary_href" ]]; then
        echo "  ОШИБКА: не удалось найти primary.xml.gz в repomd.xml для v$mm" >&2
        return 1
    fi
    _RPM_PRIMARY_CACHE=$(curl -fsSL --connect-timeout 30 --max-time 120 \
        "$base/$primary_href" 2>/dev/null | gunzip 2>/dev/null) || return 1
    _RPM_PRIMARY_MM="$mm"
}

# Скачать и распаковать Packages для DEB (с кэшированием по minor-версии)
_fetch_deb_packages() {
    local mm="$1"
    [[ "$_DEB_PACKAGES_MM" == "$mm" && -n "$_DEB_PACKAGES_CACHE" ]] && return 0

    _DEB_PACKAGES_CACHE=$(curl -fsSL --connect-timeout 30 --max-time 120 \
        "https://pkgs.k8s.io/core:/stable:/v${mm}/deb/Packages.gz" 2>/dev/null \
        | gunzip 2>/dev/null) || return 1
    _DEB_PACKAGES_MM="$mm"
}

# Резолв basename файла пакета по имени/версии/арх.
# Аргументы: <pkg> <ver> <arch> <format(rpm|deb)> <minor>
# Возвращает: basename файла (напр. kubeadm-1.36.2-150500.2.1.x86_64.rpm)
resolve_k8s_pkg() {
    local pkg="$1" ver="$2" arch="$3" fmt="$4" mm="$5"

    if [[ "$fmt" == "rpm" ]]; then
        _fetch_rpm_primary "$mm" || return 1
        # here-string (а не pipe) чтобы избежать SIGPIPE при exit в awk + pipefail
        awk -v RS='</package>' \
            -v pkg="$pkg" -v ver="$ver" -v arch="$arch" '
            {
                if ($0 ~ "<name>" pkg "</name>" \
                    && $0 ~ "ver=\"" ver "\"" \
                    && $0 ~ "<arch>" arch "</arch>") {
                    if (match($0, /<location href="[^"]*"/)) {
                        loc = substr($0, RSTART+16, RLENGTH-17)
                        # basename
                        n = split(loc, parts, "/")
                        print parts[n]
                        exit 0
                    }
                }
            }' <<< "$_RPM_PRIMARY_CACHE"
    else
        _fetch_deb_packages "$mm" || return 1
        awk -v RS='' \
            -v pkg="$pkg" -v ver="$ver" -v arch="$arch" '
            {
                if ($0 ~ "(^|\n)Package: " pkg "\n" \
                    && $0 ~ "(^|\n)Version: " ver "-" \
                    && $0 ~ "(^|\n)Architecture: " arch "\n") {
                    if (match($0, /(^|\n)Filename: [^\n]*/)) {
                        line = substr($0, RSTART, RLENGTH)
                        sub(/^(\n)?Filename: /, "", line)
                        n = split(line, parts, "/")
                        print parts[n]
                        exit 0
                    }
                }
            }' <<< "$_DEB_PACKAGES_CACHE"
    fi
}

# Резолв latest-версии пакета (для cri-tools, kubernetes-cni, чьи версии
# не совпадают с KUBE_VERSION) и вернуть "ver basename".
# Аргументы: <pkg> <arch> <format(rpm|deb)> <minor>
resolve_k8s_pkg_latest() {
    local pkg="$1" arch="$2" fmt="$3" mm="$4"

    if [[ "$fmt" == "rpm" ]]; then
        _fetch_rpm_primary "$mm" || return 1
        # Собираем «ver basename» для всех совпадений, выбираем max ver через sort -V
        awk -v RS='</package>' \
            -v pkg="$pkg" -v arch="$arch" '
            {
                if ($0 ~ "<name>" pkg "</name>" && $0 ~ "<arch>" arch "</arch>") {
                    ver=""; loc=""
                    if (match($0, /ver="[^"]*"/)) {
                        ver = substr($0, RSTART+5, RLENGTH-6)
                    }
                    if (match($0, /<location href="[^"]*"/)) {
                        loc = substr($0, RSTART+16, RLENGTH-17)
                        n = split(loc, parts, "/")
                        loc = parts[n]
                    }
                    if (ver != "" && loc != "") print ver "\t" loc
                }
            }' <<< "$_RPM_PRIMARY_CACHE" \
            | sort -V -r | head -n1
    else
        _fetch_deb_packages "$mm" || return 1
        awk -v RS='' \
            -v pkg="$pkg" -v arch="$arch" '
            {
                if ($0 ~ "(^|\n)Package: " pkg "\n" \
                    && $0 ~ "(^|\n)Architecture: " arch "\n") {
                    ver=""; fn=""
                    if (match($0, /(^|\n)Version: [^\n]*/)) {
                        line = substr($0, RSTART, RLENGTH)
                        sub(/^(\n)?Version: /, "", line)
                        ver = line
                    }
                    if (match($0, /(^|\n)Filename: [^\n]*/)) {
                        line = substr($0, RSTART, RLENGTH)
                        sub(/^(\n)?Filename: /, "", line)
                        n = split(line, parts, "/")
                        fn = parts[n]
                    }
                    if (ver != "" && fn != "") print ver "\t" fn
                }
            }' <<< "$_DEB_PACKAGES_CACHE" \
            | sort -V -r | head -n1
    fi
}

# Скачать пакет Kubernetes с динамическим резолвом имени файла.
# Аргументы: <pkg> <ver> <arch> <fmt> <mm> <latest:(yes|no)>
download_k8s_pkg() {
    local pkg="$1" ver="$2" arch="$3" fmt="$4" mm="$5" latest="${6:-no}"
    local resolved resolved_ver basename dest desc

    if [[ "$latest" == "yes" ]]; then
        resolved=$(resolve_k8s_pkg_latest "$pkg" "$arch" "$fmt" "$mm")
        resolved_ver="${resolved%%$'\t'*}"
        basename="${resolved##*$'\t'*}"
        desc="$pkg $fmt (latest: $resolved_ver)"
    else
        basename=$(resolve_k8s_pkg "$pkg" "$ver" "$arch" "$fmt" "$mm")
        desc="$pkg $fmt $ver"
    fi

    if [[ -z "$basename" ]]; then
        echo "  ОШИБКА: пакет $pkg не найден в индексе pkgs.k8s.io (v$mm, $arch, $fmt)" >&2
        return 1
    fi

    dest="$OUTPUT_DIR/packages/$basename"
    local url
    if [[ "$fmt" == "rpm" ]]; then
        url="https://pkgs.k8s.io/core:/stable:/v${mm}/rpm/${arch}/${basename}"
    else
        url="https://pkgs.k8s.io/core:/stable:/v${mm}/deb/${arch}/${basename}"
    fi

    download "$url" "$dest" "$desc"
}

# ============================================================
# Функция скачивания с проверкой
# ============================================================
download() {
    local url="$1"
    local dest="$2"
    local desc="$3"

    if [[ -f "$dest" ]]; then
        echo "  [SKIP] $desc (уже существует: $dest)"
        return 0
    fi

    echo "  [GET]  $desc"
    echo "        URL: $url"
    if curl -fSL --connect-timeout 30 --max-time 600 -o "$dest" "$url"; then
        echo "        OK: $(du -h "$dest" | cut -f1)"
    else
        echo "        ОШИБКА: не удалось скачать $url"
        rm -f "$dest"
        return 1
    fi
}

# ============================================================
# Функция скачивания Helm-чарта
# ============================================================
download_helm_chart() {
    local repo_url="$1"
    local chart_name="$2"
    local chart_version="$3"
    local dest="$4"
    local desc="$5"

    if [[ -f "$dest" ]]; then
        echo "  [SKIP] $desc (уже существует: $dest)"
        return 0
    fi

    echo "  [HELM] $desc"
    helm repo add _tmp "$repo_url" 2>/dev/null || true
    helm repo update _tmp 2>/dev/null || true
    if helm pull _tmp/"$chart_name" --version "$chart_version" --destination "$(dirname "$dest")"; then
        mv "$(dirname "$dest")"/"${chart_name}-${chart_version}.tgz" "$dest" 2>/dev/null || \
        mv "$(dirname "$dest")"/"${chart_name#*/}-${chart_version}.tgz" "$dest" 2>/dev/null || true
        if [[ -f "$dest" ]]; then
            echo "        OK: $(du -h "$dest" | cut -f1)"
        else
            echo "        ОШИБКА: чарт не найден после скачивания"
            return 1
        fi
    else
        echo "        ОШИБКА: не удалось скачать чарт $chart_name"
        return 1
    fi
    helm repo remove _tmp 2>/dev/null || true
}

# ============================================================
# 1. Kubernetes пакеты (RPM + DEB)
# ============================================================
# Имена файлов определяются динамически из индексов pkgs.k8s.io,
# т.к. суффикс release (150500.x.1 для RPM, x.1 для DEB) меняется
# между версиями и непредсказуем.
# Скачиваются: kubeadm, kubelet, kubectl (по KUBE_VERSION)
#             cri-tools, kubernetes-cni (latest — зависимости kubeadm/kubelet,
#             нужны для offline-установки, см. roles/prepare-hosts/tasks/main.yaml)
echo ""
echo ">>> Пакеты Kubernetes v$KUBE_VERSION (резолв из pkgs.k8s.io)"

# --- RPM ---
echo "  [RPM] arch: $K8S_RPM_ARCH"
for pkg in kubeadm kubelet kubectl; do
    download_k8s_pkg "$pkg" "$KUBE_VERSION" "$K8S_RPM_ARCH" rpm "$KUBE_MAJOR_MINOR" no || exit 1
done
# Зависимости — latest-версии (не привязаны к patch-версии k8s)
for pkg in cri-tools kubernetes-cni; do
    download_k8s_pkg "$pkg" "$KUBE_VERSION" "$K8S_RPM_ARCH" rpm "$KUBE_MAJOR_MINOR" yes || exit 1
done

# --- DEB ---
echo "  [DEB] arch: $K8S_DEB_ARCH"
for pkg in kubeadm kubelet kubectl; do
    download_k8s_pkg "$pkg" "$KUBE_VERSION" "$K8S_DEB_ARCH" deb "$KUBE_MAJOR_MINOR" no || exit 1
done
# Зависимости — latest-версии
for pkg in cri-tools kubernetes-cni; do
    download_k8s_pkg "$pkg" "$KUBE_VERSION" "$K8S_DEB_ARCH" deb "$KUBE_MAJOR_MINOR" yes || exit 1
done

# ============================================================
# 2. CNI манифесты
# ============================================================
echo ""
echo ">>> CNI: $CNI"

if [[ "$CNI" == "calico" ]]; then
    # Определяем версию Calico по матрице
    declare -A CALICO_MATRIX=(
        ["1.28"]="v3.26.4" ["1.29"]="v3.27.0" ["1.30"]="v3.27.3"
        ["1.31"]="v3.28.0" ["1.32"]="v3.28.1" ["1.33"]="v3.29.0"
        ["1.34"]="v3.29.1" ["1.35"]="v3.29.2" ["1.36"]="v3.30.0"
    )
    CALICO_VERSION="${CALICO_MATRIX[$KUBE_MAJOR_MINOR]:-v3.30.0}"

    download \
        "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" \
        "$OUTPUT_DIR/cni/tigera-operator.yaml" \
        "Calico tigera-operator v${CALICO_VERSION}"

# Flannel использует шаблон, скачивать не нужно

elif [[ "$CNI" == "cilium" ]]; then
    # Определяем версию Cilium по матрице
    declare -A CILIUM_MATRIX=(
        ["1.28"]="1.16.19" ["1.29"]="1.16.19" ["1.30"]="1.17.18"
        ["1.31"]="1.17.18" ["1.32"]="1.18.12" ["1.33"]="1.18.12"
        ["1.34"]="1.20.0" ["1.35"]="1.20.0" ["1.36"]="1.20.0"
    )
    CILIUM_VERSION="${CILIUM_MATRIX[$KUBE_MAJOR_MINOR]:-1.20.0}"

    # Helm-чарт Cilium (версия чарта совпадает с app-версией)
    download \
        "https://helm.cilium.io/cilium-${CILIUM_VERSION}.tgz" \
        "$OUTPUT_DIR/cni/cilium-${CILIUM_VERSION}.tgz" \
        "Cilium helm chart v${CILIUM_VERSION}"
fi

# ============================================================
# 3. Утилиты
# ============================================================
echo ""
echo ">>> Утилиты"

# Helm
download \
    "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    "$OUTPUT_DIR/utils/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    "Helm $HELM_VERSION"

# cert-manager (OCI chart — скачиваем через helm pull)
echo ""
echo ">>> cert-manager (OCI chart)"
if [[ ! -f "$OUTPUT_DIR/utils/cert-manager-${CERT_MANAGER_VERSION}.tgz" ]]; then
    echo "  [HELM] cert-manager $CERT_MANAGER_VERSION (OCI)"
    helm pull "oci://quay.io/jetstack/charts/cert-manager" \
        --version "$CERT_MANAGER_VERSION" \
        --destination "$OUTPUT_DIR/utils/" 2>/dev/null || \
    echo "  [WARN] Не удалось скачать cert-manager OCI chart — требуется helm v3.8+"
else
    echo "  [SKIP] cert-manager (уже существует)"
fi

# ============================================================
# 4. Helm-чарты
# ============================================================
echo ""
echo ">>> Helm-чарты"

# MetalLB
download_helm_chart \
    "https://metallb.github.io/metallb" \
    "metallb" \
    "$METALLB_CHART_VERSION" \
    "$OUTPUT_DIR/utils/helm-charts/metallb-${METALLB_CHART_VERSION}.tgz" \
    "MetalLB Helm chart v${METALLB_CHART_VERSION}" || true

# Ingress Nginx
download_helm_chart \
    "https://kubernetes.github.io/ingress-nginx" \
    "ingress-nginx" \
    "$INGRESS_NGINX_CHART_VERSION" \
    "$OUTPUT_DIR/utils/helm-charts/ingress-nginx-${INGRESS_NGINX_CHART_VERSION}.tgz" \
    "Ingress Nginx Helm chart ${INGRESS_NGINX_CHART_VERSION}" || true

# ArgoCD
download_helm_chart \
    "https://argoproj.github.io/argo-helm" \
    "argo-cd" \
    "$ARGOCD_CHART_VERSION" \
    "$OUTPUT_DIR/utils/helm-charts/argo-cd-${ARGOCD_CHART_VERSION}.tgz" \
    "ArgoCD Helm chart ${ARGOCD_CHART_VERSION}" || true

# NFS CSI Driver
download_helm_chart \
    "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts" \
    "csi-driver-nfs" \
    "$NFS_CSI_DRIVER_VERSION" \
    "$OUTPUT_DIR/utils/helm-charts/csi-driver-nfs-${NFS_CSI_DRIVER_VERSION}.tgz" \
    "NFS CSI Driver Helm chart v${NFS_CSI_DRIVER_VERSION}" || true

# Stakater Reloader
download_helm_chart \
    "https://stakater.github.io/stakater-charts" \
    "reloader" \
    "$RELOADER_CHART_VERSION" \
    "$OUTPUT_DIR/utils/helm-charts/reloader-${RELOADER_CHART_VERSION}.tgz" \
    "Stakater Reloader Helm chart v${RELOADER_CHART_VERSION}" || true

# Envoy Gateway (OCI chart)
echo ""
echo ">>> Envoy Gateway (OCI chart)"
if [[ ! -f "$OUTPUT_DIR/utils/helm-charts/envoy-gateway-${ENVOY_GATEWAY_VERSION}.tgz" ]]; then
    echo "  [HELM] Envoy Gateway $ENVOY_GATEWAY_VERSION (OCI)"
    helm pull "oci://docker.io/envoyproxy/gateway-helm" \
        --version "$ENVOY_GATEWAY_VERSION" \
        --destination "$OUTPUT_DIR/utils/helm-charts/" 2>/dev/null || \
    echo "  [WARN] Не удалось скачать Envoy Gateway OCI chart — требуется helm v3.8+"
else
    echo "  [SKIP] Envoy Gateway (уже существует)"
fi

# ============================================================
# 5. Helm-плагин helm-diff
# ============================================================
echo ""
echo ">>> Helm-плагины"

HELM_DIFF_DIR="$OUTPUT_DIR/utils/helm-plugins/helm-diff"
if [[ ! -d "$HELM_DIFF_DIR/.git" ]]; then
    echo "  [GET]  helm-diff plugin"
    rm -rf "$HELM_DIFF_DIR"
    git clone --depth 1 https://github.com/databus23/helm-diff.git "$HELM_DIFF_DIR" || true
else
    echo "  [SKIP] helm-diff plugin (уже существует)"
fi

# ============================================================
# Итоги
# ============================================================
echo ""
echo "============================================================"
echo " Скачивание завершено"
echo "============================================================"
echo ""
echo "Структура каталога $OUTPUT_DIR/:"
if command -v tree &>/dev/null; then
    tree -h "$OUTPUT_DIR" 2>/dev/null || find "$OUTPUT_DIR" -type f | sort
else
    find "$OUTPUT_DIR" -type f | sort
fi
echo ""
echo "Следующие шаги:"
echo "  1. Перенесите каталог $OUTPUT_DIR/ на все ноды кластера"
echo "  2. Запустите установку с флагом:"
echo "     make install ENV=homelab EXTRA='-e \"k8s_install_mode=offline\"'"
echo ""
echo "ПРИМЕЧАНИЕ: Образы Kubernetes (k8s-images.tar) нужно создать"
echo "отдельно на машине с доступом в интернет:"
echo ""
echo "  kubeadm config images pull --kubernetes-version=$KUBE_VERSION"
echo "  ctr -n k8s.io images export $OUTPUT_DIR/images/k8s-images.tar \\"
echo "    \$(ctr -n k8s.io images list -q | grep -v sha256)"
echo ""
echo "Для Calico-образов:"
echo "  ctr -n k8s.io images pull quay.io/tigera/operator:\${CALICO_VERSION}"
echo "  ctr -n k8s.io images export $OUTPUT_DIR/images/calico-images.tar \\"
echo "    \$(ctr -n k8s.io images list -q | grep -E 'calico|tigera')"
echo ""
echo "Для Cilium-образов:"
echo "  helm template cilium cilium/cilium --version \${CILIUM_VERSION} |"
echo "    grep 'image:' | awk '{print \$2}' | sed 's/\"//g' | sort -u"
echo "  # затем pull каждого образа и export в cilium-images.tar:"
echo "  ctr -n k8s.io images export $OUTPUT_DIR/images/cilium-images.tar \\"
echo "    \$(ctr -n k8s.io images list -q | grep -E 'cilium')"
