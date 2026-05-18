# TODO

## Роль etcd

- [ ] Поддержка Podman как альтернативы Docker для etcd-контейнера.
      На RHEL-системах (Rocky, Alma) Docker deprecated, Podman встроен.
      Нужна переменная `etcd_container_runtime: docker|podman` и условия
      в `etcd.service.j2` (разный синтаксис запуска контейнера).
