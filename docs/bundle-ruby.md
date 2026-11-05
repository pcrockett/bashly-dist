# Handoff: Bundle Ruby into the distribution tarballs

Status: **idea, validated by local proof of concept, not implemented**. Goal: ship a
self-contained Ruby inside each release tarball so end users no longer need
`ruby = "latest"` in their own `mise.toml`. This also eliminates the known coupling
between the tarball's compiled gem extensions and the user's Ruby minor version
(extensions live under `gems/extensions/<plat>/<major.minor.0>[-static]/`).

## Why

- Today the wrapper (`src/bashly-wrapper`) execs `gems/bin/bashly`, whose RubyGems
  binstub is a `#!/bin/sh` polyglot that falls back to `ruby` on `PATH`. Users must
  install Ruby themselves (README says `ruby = "latest"`), and when that drifts to a
  different Ruby minor than the one the gem extensions were compiled against
  (currently 4.0.x, per `mise.lock` and the `ruby:4.0-alpine` image guard in the
  workflows), native extensions (`io-console`, `erb/escape`) fail to load.
- Bundling the exact Ruby used at build time makes the tarball hermetic and removes
  both problems.

## Proof of concept (verified locally, 2026-11-05)

mise's Ruby build is **statically linked and relocatable**:
`rbconfig.rb` has `ENABLE_SHARED = "no"` and `prefix = (TOPDIR || DESTDIR + "/.")`,
so the install tree can be copied anywhere and still work.

Steps performed on a machine with mise Ruby 4.0.9:

```sh
R=~/.local/share/mise/installs/ruby/4.0.9
mkdir rt && cp -a "$R/bin" rt/bin && cp -a "$R/lib" rt/lib
rm -rf rt/lib/ruby/4.0.0/rdoc rt/lib/ruby/gems/4.0.0/doc   # trim docs
cp -a build/gems rt/gems                                     # vendored gems from `just build`
```

Wrapper `rt/bin/bashly`:

```sh
#!/usr/bin/env sh
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
export GEM_HOME="$ROOT/gems"
export GEM_PATH="$ROOT/gems"
PATH="$ROOT/bin:$PATH"; export PATH
exec "$ROOT/bin/ruby" -x "$GEM_HOME/bin/bashly" "$@"
```

Results: `./rt/bin/bashly --version` -> `2.0.0`; `--help` works; `erb`, `json`,
`openssl`, `io/console` (incl. native `.so`s) load from the relocated tree;
`Gem.default_dir` re-resolves to the new prefix; works under `env -i` with no
system Ruby on `PATH`. Trimmed+stripped bundle compressed to **~66 MB**
(vs ~2 MB today); pruning dev default gems (rbs, msgpack, debug, rdoc) and
`include/`/`share/` should get it to roughly 45-55 MB.

## Proposed implementation

### Tarball layout

```
bin/bashly        # wrapper (see below)
bin/ruby, ...     # bundled Ruby executables
lib/...           # bundled Ruby lib tree (stdlib + default gems)
gems/...          # vendored bashly + deps (as today)
```

mise already expects `bin/bashly` in the tarball, so consumers need no changes.

### Wrapper (`src/bashly-wrapper`)

```sh
#!/usr/bin/env sh
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
export GEM_HOME="$ROOT/gems"
export GEM_PATH="$ROOT/gems"
PATH="$ROOT/bin:$PATH"; export PATH
exec "$ROOT/bin/ruby" -x "$GEM_HOME/bin/bashly" "$@"
```

(`-x` skips the binstub's sh-polyglot prologue. Alternatively rely on the polyglot's
`PATH` fallback and just `exec "$GEM_HOME/bin/bashly" "$@"` — the PoC used `-x`,
both should work; verify in the smoke test.)

### `justfile` `build` changes

After `gem install ... --install-dir build/gems`:

- glibc/macOS builds: copy the prefix of the mise-installed Ruby,
  `ruby_prefix="$(dirname "$(dirname "$(command -v ruby)")")"`,
  `cp -a "$ruby_prefix" build/ruby`, then prune:
  `rm -rf build/ruby/include build/ruby/share` plus rdoc/ri/doc dirs and
  dev-only default gems (rbs, msgpack, debug, rdoc, ...). Optionally
  `strip --strip-unneeded` on binaries and `.so` files.
- musl build: `cp -a /usr/local build/ruby` from the `ruby:4.0-alpine` container,
  same pruning.
- Keep stdlib (`lib/ruby/4.0.0`) intact — bashly evaluates users' ERB templates
  in-process and they can `require` arbitrary stdlib.
- Tarball becomes `tar czf ... -C build bin lib gems ruby/...` — decide whether
  Ruby lives at top level (`bin/`, `lib/`) or under `ruby/`; the PoC used top level.

### musl caveat

The official `ruby:4.0-alpine` image builds Ruby **shared** (published musl tarball
has extensions under `.../4.0.0/`, not `4.0.0-static/`), so `lib/libruby.so*` must
be shipped and the wrapper must set `LD_LIBRARY_PATH="$ROOT/lib"` (or ensure rpath).
mise/jdx builds are static and need no such handling.

### CI notes

- The existing "image ruby must match mise.lock major.minor" guard
  (`release.yml` / `ci.yml`, awk over `mise.lock`) becomes even more critical: the
  bundled Ruby must be the same one the gem extensions were compiled against.
- Smoke test (`just test`) is unchanged — it runs `bin/bashly --version`.
- The `ruby:4.0-alpine` container tag still needs manual bumps.

## Costs / trade-offs to decide on

- **Size**: \~45-66 MB per platform tarball (5 assets) vs \~2 MB today. mise caches
  per version, so it's a one-time download, but release assets grow \~25x.
- **Ruby security updates become this repo's responsibility.** The daily cron only
  rebuilds when a new upstream Bashly release appears; a Ruby CVE would not trigger
  a rebuild unless releases are also keyed off `mise.lock` changes.
- **glibc floor**: bundled `.so`s compiled on `ubuntu-22.04` need glibc >= 2.35 —
  same constraint the gem extensions already have today.
- **License**: Ruby is under the Ruby license (BSD-2-Clause-style); redistribution is
  allowed — ship Ruby's `LEGAL`/`LICENSE` files and credit it in release notes.

## Alternatives considered (rejected for now)

- Keep current design, document `ruby = "4.0"` (pinned minor) in the README —
  cheapest fix for the minor-version coupling, but keeps the Ruby dependency.
- Single-file binary via ruby-packer (squashfs/AppImage style) — much more complex
  build, no clear win over "copy the tree".
- Status quo: users already use mise, which installs Ruby fine.

## Open questions

1. Top-level `bin/`/`lib/` vs `ruby/` subdir in the tarball (wrapper path depends on it)?
2. Ship shared `libruby.so` for musl via `LD_LIBRARY_PATH`, or build a static musl
   Ruby for the dist?
3. How aggressive should pruning be, given users' ERB templates can require anything?
4. Should a `mise.lock` Ruby bump trigger a new release tag, or a separate "ruby refresh"
   mechanism? (Release tags are currently keyed to the Bashly version.)
