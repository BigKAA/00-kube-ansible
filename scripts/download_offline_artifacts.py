#!/usr/bin/env python3
"""
Скачивание артефактов для offline-установки Kubernetes.

Единый источник версий — scripts/versions.yaml.

Что скачивает:
  1. Kubernetes пакеты (RPM): kubeadm, kubelet, kubectl, cri-tools,
     kubernetes-cni — резолв из pkgs.k8s.io (динамический суффикс OBS)
  2. Containerd (RPM): containerd.io, runc — из download.docker.com
  3. Образы контейнеров (docker pull + docker save):
     k8s-images.tar, cilium-images.tar / flannel-images.tar
  4. CNI: cilium helm-chart.tgz (flannel — только образы)
  5. Helm-чарты утилит: cert-manager, MetalLB, NFS CSI, Reloader,
     Envoy Gateway, ArgoCD
  6. CLI-инструменты: helm, cilium CLI, yq, stern — обе архитектуры
  7. Helm-плагин helm-diff (git clone)

Использование:
  python3 scripts/download_offline_artifacts.py [OPTIONS]

Опции:
  --kube-version VERSION   Версия Kubernetes (по умолчанию из versions.yaml)
  --cni CNI                CNI: cilium или flannel (по умолчанию: cilium)
  --arch ARCH              Архитектуры через запятую: x86_64,aarch64
                           (по умолчанию: x86_64)
  --output DIR             Выходной каталог (по умолчанию: tmp/offline)
  --dry-run                Показать резолвнутые версии без скачивания
  --help                   Показать справку
"""

from __future__ import annotations

import argparse
import gzip
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Iterable

try:
    import yaml
except ImportError:
    sys.exit("ОШИБКА: PyYAML не установлен. Установите: pip install pyyaml")

# ============================================================
# Константы
# ============================================================

SCRIPT_DIR = Path(__file__).resolve().parent
VERSIONS_FILE = SCRIPT_DIR / "versions.yaml"
PROJECT_ROOT = SCRIPT_DIR.parent

# Namespace primary.xml для резолва RPM
NS = {"repo": "http://linux.duke.edu/metadata/repo"}
NS_COMMON = {"": "http://linux.duke.edu/metadata/common"}


# ============================================================
# Утилиты
# ============================================================

def die(msg: str, code: int = 1) -> None:
    """Вывести ошибку и завершиться."""
    print(f"ОШИБКА: {msg}", file=sys.stderr)
    sys.exit(code)


def check_dependencies() -> None:
    """Проверить наличие внешних инструментов."""
    missing = []
    for tool in ("curl", "docker", "helm", "git"):
        if not shutil.which(tool):
            missing.append(tool)
    if missing:
        die(f"инструменты не найдены: {', '.join(missing)}. Установите и добавьте в PATH.")
    if not VERSIONS_FILE.is_file():
        die(f"файл версий не найден: {VERSIONS_FILE}")


def load_versions() -> dict:
    """Загрузить versions.yaml."""
    with VERSIONS_FILE.open() as f:
        return yaml.safe_load(f)


def arch_to_docker(arch: str) -> str:
    """Преобразовать rpm-arch в docker-arch."""
    return {"x86_64": "amd64", "aarch64": "arm64"}.get(arch, arch)


def http_get(url: str, timeout: int = 120) -> bytes:
    """HTTP GET с обработкой ошибок."""
    req = urllib.request.Request(url, headers={"User-Agent": "kube-ansible-offline/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def http_get_text(url: str, timeout: int = 120) -> str:
    """HTTP GET, вернуть текст."""
    return http_get(url, timeout).decode("utf-8", errors="replace")


# ============================================================
# Скачивание файлов
# ============================================================

def download_file(url: str, dest: Path, desc: str, timeout: int = 600) -> bool:
    """Скачать файл по URL в dest. True если скачан, False если уже существует."""
    if dest.exists():
        print(f"  [SKIP] {desc} (уже существует)")
        return False
    print(f"  [GET]  {desc}")
    print(f"        URL: {url}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        data = http_get(url, timeout=timeout)
        dest.write_bytes(data)
        size = dest.stat().st_size
        print(f"        OK: {size / (1024 * 1024):.1f} MB")
        return True
    except Exception as e:
        print(f"        ОШИБКА: {e}", file=sys.stderr)
        if dest.exists():
            dest.unlink()
        return False


def run_cmd(cmd: list[str], desc: str, cwd: Path | None = None, check: bool = True) -> bool:
    """Запустить внешнюю команду. True при успехе."""
    print(f"  [RUN]  {desc}")
    print(f"        cmd: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, check=check, cwd=cwd, capture_output=True, text=True)
        return True
    except subprocess.CalledProcessError as e:
        print(f"        ОШИБКА (rc={e.returncode}): {e.stderr.strip()[:300]}", file=sys.stderr)
        return False


# ============================================================
# Резолв RPM из primary.xml (pkgs.k8s.io и download.docker.com)
# ============================================================

class RpmResolver:
    """Резолв имен RPM-пакетов из репозитория через primary.xml."""

    def __init__(self, repo_base_url: str):
        self.base = repo_base_url.rstrip("/")
        self._primary_cache: str | None = None

    def _fetch_primary(self) -> str:
        if self._primary_cache is not None:
            return self._primary_cache
        repomd_url = f"{self.base}/repodata/repomd.xml"
        repomd = http_get_text(repomd_url)
        root = ET.fromstring(repomd)
        primary_href = None
        for data_el in root:
            if data_el.get("type") != "primary":
                continue
            location = data_el.find("{http://linux.duke.edu/metadata/repo}location")
            if location is not None:
                primary_href = location.get("href")
                break
        if not primary_href:
            die(f"primary data не найден в {repomd_url}")
        primary_url = f"{self.base}/{primary_href}"
        compressed = http_get(primary_url)
        # Поддержка gzip (.gz) и zstd (.zst)
        if primary_href.endswith(".gz"):
            data = gzip.decompress(compressed)
        elif primary_href.endswith(".zst"):
            try:
                import zstandard
                data = zstandard.decompress(compressed)
            except ImportError:
                # Fallback: распаковка через subprocess (zstd есть в большинстве систем)
                import tempfile
                with tempfile.NamedTemporaryFile(suffix=".zst", delete=False) as tmp:
                    tmp.write(compressed)
                    tmp_path = tmp.name
                try:
                    result = subprocess.run(
                        ["zstd", "-d", tmp_path, "-c"], capture_output=True, check=True,
                    )
                    data = result.stdout
                finally:
                    os.unlink(tmp_path)
        else:
            data = compressed
        self._primary_cache = data.decode("utf-8", errors="replace")
        return self._primary_cache

    def resolve(self, pkg: str, version: str, arch: str) -> str | None:
        """
        Найти basename RPM-файла для пакета с указанной версией.
        version может содержать '*' как wildcard для patch (например '1.7.*').
        Возвращает basename (например 'kubeadm-1.36.2-150500.2.1.x86_64.rpm') или None.
        """
        primary = self._fetch_primary()
        # primary.xml использует namespace http://linux.duke.edu/metadata/common
        try:
            root = ET.fromstring(primary)
        except ET.ParseError as e:
            die(f"не удалось разобрать primary.xml: {e}")
        # version pattern: экранируем для regex, '*' → '.*'
        ver_pattern = "^" + re.escape(version).replace(r"\*", ".*") + "$"
        ver_re = re.compile(ver_pattern)
        for pkg_el in root.findall(".//{http://linux.duke.edu/metadata/common}package"):
            name_el = pkg_el.find("{http://linux.duke.edu/metadata/common}name")
            arch_el = pkg_el.find("{http://linux.duke.edu/metadata/common}arch")
            ver_el = pkg_el.find("{http://linux.duke.edu/metadata/common}version")
            loc_el = pkg_el.find("{http://linux.duke.edu/metadata/common}location")
            if name_el is None or arch_el is None or ver_el is None or loc_el is None:
                continue
            if name_el.text != pkg or arch_el.text != arch:
                continue
            ver = ver_el.get("ver", "")
            epoch = ver_el.get("epoch", "0")
            rel = ver_el.get("rel", "")
            # Полная версия для сравнения: ver-rel
            full_ver = f"{ver}-{rel}"
            # Проверяем соответствие версии (ver-rel или ver)
            if not (ver_re.match(full_ver) or ver_re.match(ver)):
                continue
            href = loc_el.get("href", "")
            # basename
            return href.rsplit("/", 1)[-1]
        return None

    def resolve_latest(self, pkg: str, arch: str) -> tuple[str, str] | None:
        """
        Найти последнюю версию пакета для arch.
        Возвращает (full_version, basename) или None.
        """
        primary = self._fetch_primary()
        try:
            root = ET.fromstring(primary)
        except ET.ParseError as e:
            die(f"не удалось разобрать primary.xml: {e}")
        candidates: list[tuple[str, str]] = []
        for pkg_el in root.findall(".//{http://linux.duke.edu/metadata/common}package"):
            name_el = pkg_el.find("{http://linux.duke.edu/metadata/common}name")
            arch_el = pkg_el.find("{http://linux.duke.edu/metadata/common}arch")
            ver_el = pkg_el.find("{http://linux.duke.edu/metadata/common}version")
            loc_el = pkg_el.find("{http://linux.duke.edu/metadata/common}location")
            if name_el is None or arch_el is None or ver_el is None or loc_el is None:
                continue
            if name_el.text != pkg or arch_el.text != arch:
                continue
            ver = ver_el.get("ver", "")
            rel = ver_el.get("rel", "")
            href = loc_el.get("href", "")
            basename = href.rsplit("/", 1)[-1]
            # Ключ сортировки: (epoch, ver, rel) — используем packaging.version если есть,
            # иначе строковая сортировка по версиям
            full = f"{ver}-{rel}"
            candidates.append((full, basename))
        if not candidates:
            return None
        # Сортировка по версии (упрощённая: split по не-цифрам)
        def sort_key(item: tuple[str, str]) -> list:
            return [int(x) if x.isdigit() else x for x in re.split(r"(\d+)", item[0])]

        candidates.sort(key=sort_key, reverse=True)
        return candidates[0]


def download_k8s_rpm(
    resolver: RpmResolver, output_dir: Path, pkg: str, version: str, arch: str, mm: str, latest: bool = False
) -> None:
    """Скачать k8s RPM-пакет."""
    if latest:
        result = resolver.resolve_latest(pkg, arch)
        if not result:
            die(f"пакет {pkg} не найден в pkgs.k8s.io (v{mm}, {arch})")
        full_ver, basename = result
        desc = f"{pkg} RPM (latest: {full_ver}) [{arch}]"
    else:
        basename = resolver.resolve(pkg, version, arch)
        if not basename:
            die(f"пакет {pkg} {version} не найден в pkgs.k8s.io (v{mm}, {arch})")
        desc = f"{pkg} RPM {version} [{arch}]"
    url = f"https://pkgs.k8s.io/core:/stable:/v{mm}/rpm/{arch}/{basename}"
    dest = output_dir / "packages" / basename
    if not download_file(url, dest, desc):
        return


# ============================================================
# Образы контейнеров (docker pull + docker save)
# ============================================================

def get_k8s_images(kube_version: str) -> list[str]:
    """Получить список образов kubeadm для версии."""
    # kubeadm может быть недоступен на хосте подготовки — используем дефолтный список
    default_images = [
        f"registry.k8s.io/kube-apiserver:v{kube_version}",
        f"registry.k8s.io/kube-controller-manager:v{kube_version}",
        f"registry.k8s.io/kube-scheduler:v{kube_version}",
        f"registry.k8s.io/kube-proxy:v{kube_version}",
        "registry.k8s.io/coredns/coredns:v1.12.0",
        "registry.k8s.io/pause:3.10",
        "registry.k8s.io/etcd:3.6.6-0",
    ]
    # Попытка через kubeadm
    try:
        result = subprocess.run(
            ["kubeadm", "config", "images", "list", f"--kubernetes-version={kube_version}"],
            capture_output=True, text=True, timeout=30, check=True,
        )
        images = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        if images:
            return images
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return default_images


def get_cilium_images(chart_version: str) -> list[str]:
    """Получить список образов Cilium через helm template."""
    run_cmd(["helm", "repo", "add", "cilium", "https://helm.cilium.io/"], "helm repo add cilium", check=False)
    run_cmd(["helm", "repo", "update", "cilium"], "helm repo update cilium", check=False)
    try:
        result = subprocess.run(
            ["helm", "template", "cilium", "cilium/cilium", f"--version={chart_version}"],
            capture_output=True, text=True, timeout=60, check=True,
        )
        images = []
        for line in result.stdout.splitlines():
            # Ищем строки с image:
            m = re.search(r'image:\s*"?([^"\s]+)"?', line)
            if m:
                images.append(m.group(1))
        # Уникальные, сохраняя порядок
        seen = set()
        unique = []
        for img in images:
            if img not in seen:
                seen.add(img)
                unique.append(img)
        return unique
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        print("  [WARN] не удалось получить список образов Cilium через helm template", file=sys.stderr)
        return []


def _image_to_filename(image: str) -> str:
    """
    Преобразовать ссылку на образ в имя файла для docker save.
    Пример: registry.k8s.io/kube-apiserver:v1.36.2 → kube-apiserver_v1.36.2.tar
            docker.io/flannel/flannel:v0.26.4 → flannel_v0.26.4.tar
    """
    # Берём часть после последнего '/' (репозиторий/имя → имя)
    name = image.rsplit("/", 1)[-1]
    # Заменяем ':' на '_' для имени файла
    return name.replace(":", "_") + ".tar"


def save_images(output_dir: Path, group: str, desc: str, images: list[str], archs: list[str]) -> None:
    """
    docker pull + docker save каждого образа в отдельный .tar-файл.
    Файлы складываются в images/<group>/ (k8s, cilium, flannel).
    Имя файла: <image-name>_<tag>.tar
    """
    group_dir = output_dir / "images" / group
    group_dir.mkdir(parents=True, exist_ok=True)
    if not images:
        print(f"  [SKIP] {desc} (нет образов)")
        return
    print(f"  [IMAGES] {desc} ({len(images)} образов → images/{group}/)")
    for img in images:
        tar_name = _image_to_filename(img)
        dest = group_dir / tar_name
        if dest.exists():
            print(f"  [SKIP] {tar_name} (уже существует)")
            continue
        # docker pull для каждой arch (берём первую доступную)
        pulled = False
        for arch in archs:
            docker_arch = arch_to_docker(arch)
            platform = f"linux/{docker_arch}"
            print(f"        docker pull --platform={platform} {img}")
            if run_cmd(
                ["docker", "pull", f"--platform={platform}", img],
                f"pull {img} [{docker_arch}]", check=False,
            ):
                pulled = True
                break  # достаточно одной arch
        if not pulled:
            print(f"        [WARN] не удалось pull {img} — пропуск", file=sys.stderr)
            continue
        # docker save в отдельный файл
        print(f"        docker save → {tar_name}")
        try:
            subprocess.run(["docker", "save", "-o", str(dest), img], check=True)
            if dest.exists():
                size = dest.stat().st_size
                print(f"        OK: {tar_name} ({size / (1024 * 1024):.1f} MB)")
            else:
                print(f"        ОШИБКА: docker save завершился, но файл не создан", file=sys.stderr)
        except subprocess.CalledProcessError as e:
            print(f"        ОШИБКА: docker save не удался (rc={e.returncode})", file=sys.stderr)
            if dest.exists():
                dest.unlink()


# ============================================================
# Helm-чарты
# ============================================================

def download_helm_chart_oci(oci_ref: str, version: str, dest_dir: Path, desc: str) -> None:
    """Скачать OCI helm-chart."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    # helm pull сохраняет как <name>-<version>.tgz — проверяем наличие по шаблону
    chart_name = oci_ref.rsplit("/", 1)[-1]
    expected = dest_dir / f"{chart_name}-{version}.tgz"
    if expected.exists():
        print(f"  [SKIP] {desc} (уже существует)")
        return
    print(f"  [HELM] {desc}")
    run_cmd(
        ["helm", "pull", oci_ref, f"--version={version}", f"--destination={dest_dir}"],
        f"pull {oci_ref}:{version}", check=False,
    )


def download_helm_chart_repo(
    repo_url: str, chart_name: str, version: str, dest: Path, desc: str
) -> None:
    """Скачать helm-chart из классического репозитория."""
    if dest.exists():
        print(f"  [SKIP] {desc} (уже существует)")
        return
    print(f"  [HELM] {desc}")
    run_cmd(["helm", "repo", "add", "_tmp", repo_url], f"add repo {repo_url}", check=False)
    run_cmd(["helm", "repo", "update", "_tmp"], f"update repo _tmp", check=False)
    if run_cmd(
        ["helm", "pull", f"_tmp/{chart_name}", f"--version={version}", f"--destination={dest.parent}"],
        f"pull {chart_name}:{version}", check=False,
    ):
        # helm pull сохраняет как <chart>-<version>.tgz, переименовываем
        default_name = dest.parent / f"{chart_name}-{version}.tgz"
        # Для чартов с '/' в имени helm использует часть после '/'
        short_name = chart_name.rsplit("/", 1)[-1]
        alt_name = dest.parent / f"{short_name}-{version}.tgz"
        for candidate in (default_name, alt_name):
            if candidate.exists() and candidate != dest:
                candidate.rename(dest)
                print(f"        OK: {dest.name}")
                break
    run_cmd(["helm", "repo", "remove", "_tmp"], "remove _tmp", check=False)


# ============================================================
# CLI-инструменты
# ============================================================

def download_cli_tools(output_dir: Path, versions: dict, cni: str, archs: list[str]) -> None:
    """Скачать helm, cilium CLI, yq, stern для каждой arch."""
    utils_dir = output_dir / "utils"
    utils_dir.mkdir(parents=True, exist_ok=True)
    helm_ver = versions["cli"]["helm"]
    cilium_cli_ver = versions["cli"]["cilium_cli"]
    yq_ver = versions["cli"]["yq"]
    stern_ver = versions["cli"]["stern"]
    stern_ver_no_v = stern_ver.lstrip("v")

    for arch in archs:
        docker_arch = arch_to_docker(arch)
        print(f"  [arch: {arch} → {docker_arch}]")
        # Helm
        download_file(
            f"https://get.helm.sh/helm-{helm_ver}-linux-{docker_arch}.tar.gz",
            utils_dir / f"helm-{helm_ver}-linux-{docker_arch}.tar.gz",
            f"Helm {helm_ver} [{docker_arch}]",
        )
        # cilium CLI (только при cni=cilium)
        if cni == "cilium":
            download_file(
                f"https://github.com/cilium/cilium-cli/releases/download/{cilium_cli_ver}/cilium-linux-{docker_arch}.tar.gz",
                utils_dir / f"cilium-linux-{docker_arch}.tar.gz",
                f"cilium CLI {cilium_cli_ver} [{docker_arch}]",
            )
        # yq
        download_file(
            f"https://github.com/mikefarah/yq/releases/download/{yq_ver}/yq_linux_{docker_arch}",
            utils_dir / f"yq_linux_{docker_arch}",
            f"yq {yq_ver} [{docker_arch}]",
        )
        # stern
        download_file(
            f"https://github.com/stern/stern/releases/download/{stern_ver}/stern_{stern_ver_no_v}_linux_{docker_arch}.tar.gz",
            utils_dir / f"stern_{stern_ver}_linux_{docker_arch}.tar.gz",
            f"stern {stern_ver} [{docker_arch}]",
        )


# ============================================================
# Helm-плагин helm-diff
# ============================================================

def download_helm_diff(output_dir: Path) -> None:
    """git clone helm-diff plugin."""
    dest = output_dir / "utils" / "helm-plugins" / "helm-diff"
    if (dest / ".git").exists():
        print("  [SKIP] helm-diff plugin (уже существует)")
        return
    print("  [GET]  helm-diff plugin")
    if dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    run_cmd(
        ["git", "clone", "--depth", "1", "https://github.com/databus23/helm-diff.git", str(dest)],
        "git clone helm-diff", check=False,
    )


# ============================================================
# Итоги
# ============================================================

def print_summary(output_dir: Path) -> None:
    """Вывести структуру скачанных файлов."""
    print()
    print("=" * 60)
    print(" Скачивание завершено")
    print("=" * 60)
    print()
    print(f"Структура каталога {output_dir}/:")
    for path in sorted(output_dir.rglob("*")):
        if path.is_file():
            rel = path.relative_to(output_dir)
            size = path.stat().st_size
            size_str = f"{size / (1024 * 1024):.1f} MB" if size >= 1024 * 1024 else f"{size / 1024:.0f} KB"
            print(f"  {size_str:>10}  {rel}")
    print()
    print("Следующий шаг:")
    print("  make install ENV=curs EXTRA='-e \"k8s_install_mode=offline\"'")


# ============================================================
# Главная функция
# ============================================================

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Скачивание артефактов для offline-установки Kubernetes",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Примеры:
  %(prog)s
  %(prog)s --kube-version 1.35.0 --cni flannel
  %(prog)s --arch x86_64,aarch64
""",
    )
    versions = load_versions()
    parser.add_argument("--kube-version", default=versions["kube_version_default"],
                        help=f"Версия Kubernetes (по умолчанию: {versions['kube_version_default']})")
    parser.add_argument("--cni", default=versions["cni_default"], choices=["cilium", "flannel"],
                        help=f"CNI (по умолчанию: {versions['cni_default']})")
    parser.add_argument("--arch", default="x86_64",
                        help="Архитектуры через запятую: x86_64,aarch64 (по умолчанию: x86_64)")
    parser.add_argument("--output", default="tmp/offline",
                        help="Выходной каталог (по умолчанию: tmp/offline)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Показать резолвнутые версии без скачивания")
    args = parser.parse_args()

    check_dependencies()

    kube_version = args.kube_version
    cni = args.cni
    archs = [a.strip() for a in args.arch.split(",") if a.strip()]
    output_dir = PROJECT_ROOT / args.output

    # Версия CNI по матрице
    mm_match = re.match(r"^(\d+\.\d+)", kube_version)
    if not mm_match:
        die(f"некорректная kube_version: {kube_version}")
    mm = mm_match.group(1)
    cni_version = versions["cni_matrix"].get(cni, {}).get(mm)
    if not cni_version:
        die(f"версия {cni} не найдена в матрице для k8s {mm}. Проверьте scripts/versions.yaml")

    containerd_version = versions["containerd_version"]
    runc_version = versions["runc_version"]
    u = versions["utils"]
    cli = versions["cli"]

    # Шапка
    print("=" * 60)
    print(" Скачивание offline-артефактов")
    print("=" * 60)
    print(f" Kubernetes   : {kube_version}")
    print(f" CNI          : {cni} ({cni_version})")
    print(f" Архитектуры  : {','.join(archs)}")
    print(f" Containerd   : {containerd_version} (runc {runc_version})")
    print(f" Helm         : {cli['helm']}")
    print(f" CLI          : cilium {cli['cilium_cli']}, yq {cli['yq']}, stern {cli['stern']}")
    print(f" cert-manager : {u['cert_manager']}")
    print(f" MetalLB      : {u['metallb_chart']}")
    print(f" NFS CSI      : {u['nfs_csi_driver']}")
    print(f" Reloader     : {u['reloader_chart']}")
    print(f" Envoy GW     : {u['envoy_gateway']}")
    print(f" ArgoCD       : {u['argocd_chart']}")
    print(f" Выходной каталог: {args.output}")
    if args.dry_run:
        print(" РЕЖИМ      : dry-run (без скачивания)")
    print("=" * 60)

    if args.dry_run:
        print("Dry-run: параметры резолвнуты, выход без скачивания.")
        return

    # Структура каталогов
    for subdir in ("packages", "cri/containerd", "cni", "images",
                   "utils/helm-charts", "utils/helm-plugins/helm-diff"):
        (output_dir / subdir).mkdir(parents=True, exist_ok=True)

    # --- 1. Kubernetes RPM ---
    print("\n>>> 1. Пакеты Kubernetes v" + kube_version + " (RPM)")
    k8s_resolver = RpmResolver(f"https://pkgs.k8s.io/core:/stable:/v{mm}/rpm")
    for arch in archs:
        print(f"  [arch: {arch}]")
        for pkg in ("kubeadm", "kubelet", "kubectl"):
            download_k8s_rpm(k8s_resolver, output_dir, pkg, kube_version, arch, mm, latest=False)
        # Зависимости — latest
        for pkg in ("cri-tools", "kubernetes-cni"):
            download_k8s_rpm(k8s_resolver, output_dir, pkg, kube_version, arch, mm, latest=True)

    # --- 2. Containerd RPM ---
    print("\n>>> 2. Containerd v" + containerd_version + " (RPM)")
    docker_resolver = RpmResolver("https://download.docker.com/linux/centos/9/x86_64/stable")
    for arch in archs:
        print(f"  [arch: {arch}]")
        # Resolver для каждой arch — разный base URL
        docker_resolver = RpmResolver(f"https://download.docker.com/linux/centos/9/{arch}/stable")
        for pkg_ver in (("containerd.io", containerd_version), ("runc", runc_version)):
            pkg, ver = pkg_ver
            basename = docker_resolver.resolve(pkg, ver, arch)
            if not basename:
                # Попытка с wildcard для patch
                basename = docker_resolver.resolve(pkg, f"{ver.split('.')[0]}.*", arch)
            if not basename:
                # runc отсутствует в Docker CE repo для RHEL 9+ (поставляется системой)
                print(f"  [SKIP] {pkg} {ver} недоступен в Docker repo для {arch} "
                      f"(поставляется ОС или входит в containerd.io)")
                continue
            url = f"https://download.docker.com/linux/centos/9/{arch}/stable/Packages/{basename}"
            dest = output_dir / "cri" / "containerd" / basename
            download_file(url, dest, f"{pkg} {ver} [{arch}]")

    # --- 3. Образы контейнеров ---
    print("\n>>> 3. Образы контейнеров (docker pull + save, по одному tar на образ)")
    k8s_images = get_k8s_images(kube_version)
    save_images(output_dir, "k8s", f"Kubernetes images v{kube_version}", k8s_images, archs)
    if cni == "cilium":
        cilium_images = get_cilium_images(cni_version)
        save_images(output_dir, "cilium", f"Cilium images v{cni_version}", cilium_images, archs)
    elif cni == "flannel":
        flannel_images = [
            f"docker.io/flannel/flannel:{cni_version}",
            "docker.io/flannel/flannel-cni-plugin:v1.5.1-flannel2",
        ]
        save_images(output_dir, "flannel", f"Flannel images {cni_version}", flannel_images, archs)

    # --- 4. CNI helm-chart ---
    print("\n>>> 4. CNI (" + cni + ")")
    if cni == "cilium":
        download_file(
            f"https://helm.cilium.io/cilium-{cni_version}.tgz",
            output_dir / "cni" / f"cilium-{cni_version}.tgz",
            f"Cilium helm-chart v{cni_version}",
        )
    # Flannel использует манифест (templates/flannel.j2), chart не нужен

    # --- 5. Helm-чарты утилит ---
    print("\n>>> 5. Helm-чарты утилит")
    charts_dir = output_dir / "utils" / "helm-charts"
    # cert-manager (OCI)
    download_helm_chart_oci(
        "oci://quay.io/jetstack/charts/cert-manager", u["cert_manager"],
        output_dir / "utils", f"cert-manager {u['cert_manager']} (OCI)",
    )
    # MetalLB
    download_helm_chart_repo(
        "https://metallb.github.io/metallb", "metallb", u["metallb_chart"],
        charts_dir / f"metallb-{u['metallb_chart']}.tgz", f"MetalLB helm-chart v{u['metallb_chart']}",
    )
    # NFS CSI Driver
    download_helm_chart_repo(
        "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts",
        "csi-driver-nfs", u["nfs_csi_driver"],
        charts_dir / f"csi-driver-nfs-{u['nfs_csi_driver']}.tgz",
        f"NFS CSI Driver helm-chart v{u['nfs_csi_driver']}",
    )
    # Stakater Reloader
    download_helm_chart_repo(
        "https://stakater.github.io/stakater-charts", "reloader", u["reloader_chart"],
        charts_dir / f"reloader-{u['reloader_chart']}.tgz", f"Stakater Reloader helm-chart v{u['reloader_chart']}",
    )
    # Envoy Gateway (OCI)
    download_helm_chart_oci(
        "oci://docker.io/envoyproxy/gateway-helm", u["envoy_gateway"],
        charts_dir, f"Envoy Gateway {u['envoy_gateway']} (OCI)",
    )
    # ArgoCD
    download_helm_chart_repo(
        "https://argoproj.github.io/argo-helm", "argo-cd", u["argocd_chart"],
        charts_dir / f"argo-cd-{u['argocd_chart']}.tgz", f"ArgoCD helm-chart v{u['argocd_chart']}",
    )

    # --- 6. CLI-инструменты ---
    print("\n>>> 6. CLI-инструменты")
    download_cli_tools(output_dir, versions, cni, archs)

    # --- 7. Helm-плагин helm-diff ---
    print("\n>>> 7. Helm-плагины")
    download_helm_diff(output_dir)

    # --- Итоги ---
    print_summary(output_dir)


if __name__ == "__main__":
    main()

