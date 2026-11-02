# Bashly Locked Distribution

Install [Bashly](https://bashly.dev/) with [Mise](https://mise.jdx.dev/) and get
a proper lockfile, with all dependencies resolved once at release-time rather than
install-time:

```toml
# mise.toml
ruby = "latest"
"github:pcrockett/bashly-dist" = "latest"
```
