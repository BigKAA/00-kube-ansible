# TODO

## Offline-скрипт

- [ ] Проверка мульти-арх (aarch64): протестировать скачивание и
      установку offline-артефактов на arm64-нодах.
- [ ] Добавить поддержку multi-arch docker save (образы для нескольких
      платформ в одном tar через `docker buildx imagetools`).

## Тестирование

- [ ] Прогнать полный цикл через Docker-контейнер (Dockerfile.ansible)
      на inventory `hosts-curs.yaml` (install → проверка → reset → offline).
- [ ] Проверить `make upgrade` — upgrade minor-версии k8s + CNI + утилит.
