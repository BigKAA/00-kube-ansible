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
#   --helm-version VERSION   Версия Helm (по умолчанию: v3.16.3)
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
KUBE_VERSION="1.36.1"
CRI="containerd"
CNI="calico"
HELM_VERSION="v3.16.3"
CERT_MANAGER_VERSION="v1.17.1"
OUTPUT_DIR="tmp/offline"

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --kube-version)   KUBE_VERSION="$2"; shift 2 ;;
        --cri)            CRI="$2"; shift 2 ;;
        --cni)            CNI="$2"; shift 2 ;;
        --helm-version)   HELM_VERSION="$2"; shift 2 ;;
        --cert-manager-version) CERT_MANAGER_VERSION="$2"; shift 2 ;;
        --output)         OUTPUT_DIR="$2"; shift 2 ;;
        --help)
            head -n 18 "$0" | tail -n 15 | sed 's/^# //' 
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
echo " Выходной каталог: $OUTPUT_DIR"
echo "============================================================"

# Создание структуры каталогов
mkdir -p "$OUTPUT_DIR"/{packages,cri/{containerd,crio},cni,images,utils/helm-charts,utils/helm-plugins/helm-diff}

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
# 1. Kubernetes пакеты (RPM + DEB)
# ============================================================
echo ""
echo ">>> Пакеты Kubernetes v$KUBE_VERSION"

# RPM
download \
    "https://pkgs.k8s.io/core:/stable:/v${KUBE_MAJOR_MINOR}/rpm/x86_64/kubeadm-${KUBE_VERSION}-150000.1.1.x86_64.rpm" \
    "$OUTPUT_DIR/packages/kubeadm-${KUBE_VERSION}.x86_64.rpm" \
    "kubeadm RPM"

download \
    "https://pkgs.k8s.io/core:/stable:/v${KUBE_MAJOR_MINOR}/rpm/x86_64/kubelet-${KUBE_VERSION}-150000.1.1.x86_64.rpm" \
    "$OUTPUT_DIR/packages/kubelet-${KUBE_VERSION}.x86_64.rpm" \
    "kubelet RPM"

download \
    "https://pkgs.k8s.io/core:/stable:/v${KUBE_MAJOR_MINOR}/rpm/x86_64/kubectl-${KUBE_VERSION}-150000.1.1.x86_64.rpm" \
    "$OUTPUT_DIR/packages/kubectl-${KUBE_VERSION}.x86_64.rpm" \
    "kubectl RPM"

# DEB
download \
    "https://pkgs.k8s.io/core:/stable:/v${KUBE_MAJOR_MINOR}/deb/amd64/kubeadm_${KUBE_VERSION}-1.1_amd64.deb" \
    "$OUTPUT_DIR/packages/kubeadm_${KUBE_VERSION}-1.1_amd64.deb" \
    "kubeadm DEB"

download \
    "https://pkgs.k8s.io/core:/stable:/v${KUBE_MAJOR_MINOR}/deb/amd64/kubelet_${KUBE_VERSION}-1.1_amd64.deb" \
    "$OUTPUT_DIR/packages/kubelet_${KUBE_VERSION}-1.1_amd64.deb" \
    "kubelet DEB"

download \
    "https://pkgs.k8s.io/core:/stable:/v${KUBE_MAJOR_MINOR}/deb/amd64/kubectl_${KUBE_VERSION}-1.1_amd64.deb" \
    "$OUTPUT_DIR/packages/kubectl_${KUBE_VERSION}-1.1_amd64.deb" \
    "kubectl DEB"

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
fi

# Flannel использует шаблон, скачивать не нужно

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

# cert-manager
download \
    "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml" \
    "$OUTPUT_DIR/utils/cert-manager.yaml" \
    "cert-manager $CERT_MANAGER_VERSION"

# ============================================================
# 4. Helm-чарты
# ============================================================
echo ""
echo ">>> Helm-чарты"

# MetalLB
download \
    "https://metallb.github.io/metallb/charts/metallb-v0.14.8.tgz" \
    "$OUTPUT_DIR/utils/helm-charts/metallb-v0.14.8.tgz" \
    "MetalLB Helm chart v0.14.8" || true

# Ingress Nginx
download \
    "https://kubernetes.github.io/ingress-nginx/charts/ingress-nginx-4.12.0.tgz" \
    "$OUTPUT_DIR/utils/helm-charts/ingress-nginx-4.12.0.tgz" \
    "Ingress Nginx Helm chart 4.12.0" || true

# ArgoCD
download \
    "https://argoproj.github.io/argo-helm/argo-cd-7.8.7.tgz" \
    "$OUTPUT_DIR/utils/helm-charts/argo-cd-7.8.7.tgz" \
    "ArgoCD Helm chart 7.8.7" || true

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
