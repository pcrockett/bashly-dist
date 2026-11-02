# Bashly Locked Distribution

Install [Bashly](https://bashly.dev/) with [Mise](https://mise.jdx.dev/) and get
a proper lockfile, with all dependencies resolved once at release-time rather than
install-time:

```toml
# mise.toml
ruby = "latest"
"github:pcrockett/bashly-dist" = "latest"
```

## Platforms

Tarballs are published for Linux (glibc and musl) and macOS, on both x64 and
arm64; mise picks the right one for your platform automatically.

## Alpine (musl)

Mise installs Ruby from [jdx/ruby](https://github.com/jdx/ruby), which publishes
no musl builds, so on Alpine mise compiles Ruby from source. Install the build
dependencies first:

```sh
apk add build-base gcc patch bzip2 libffi-dev openssl-dev ncurses-dev gdbm-dev zlib-dev readline-dev yaml-dev bash git
```
