# Bashly Locked Distribution

Install [Bashly](https://bashly.dev/) with [Mise](https://mise.jdx.dev/) and get
a proper lockfile, with all dependencies resolved once at release-time rather than
install-time:

```toml
# mise.toml
ruby = "4.0"
"github:pcrockett/bashly-dist" = "2.0.0"
```

_One big caveat: Ruby native extensions are compiled against a particular version of
Ruby, so when you install Bashly this way, you need to be using the same minor version
of Ruby as the Bashly release build. You shouldn't use `ruby = "latest"`._

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

The arm64 architecture is not supported for musl (yet).
