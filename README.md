# Bashly Locked Distribution

Install [Bashly](https://bashly.dev/) with [Mise](https://mise.jdx.dev/) and get
a proper lockfile, with all dependencies resolved once at release-time rather
than install-time:

```toml
# mise.toml
"github:pcrockett/bashly-dist" = "2.0.0"
```

Each tarball bundles its own Ruby, so no Ruby installation is needed.

## Platforms

Tarballs are published for Linux (glibc and musl) and macOS, on x64 and arm64
(musl is x64 only); mise picks the right one for your platform automatically.
