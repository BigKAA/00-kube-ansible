# Установка k3s (air-gap)

Обязательно в директорию files скачайте файлы:
* [install.sh](https://get.k3s.io/).
* [k3s](https://github.com/k3s-io/k3s/releases).
* [k3s-airgap-images-amd64.tar.gz](https://github.com/k3s-io/k3s/releases).

Простейшая установка с одной контрол нодой.

На worker (agent) нодах, ставится без доступа из интернет. Кроме dnf - тут надо доработать настройку внутреннего репозитория.