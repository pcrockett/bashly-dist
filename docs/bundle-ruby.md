# Bundle Ruby into the distribution tarballs

Status: **implemented**. Each release tarball ships a self-contained Ruby so
end users need no Ruby installation.

## Design

- Tarball layout: `bin/bashly` (the only entry point mise exposes on PATH),
  `ruby/` (the build Ruby's full prefix, pruned), `gems/` (vendored bashly
  gems, as today).
- `ruby/bin/` and `ruby/lib/` must stay under one root: ruby resolves its
  prefix relative to the executable, so they cannot be split.
- Wrapper (`src/bashly-wrapper`): sets `GEM_HOME`/`GEM_PATH` to the bundled
  gems and `LD_LIBRARY_PATH` to `ruby/lib`, then execs the bundled ruby with
  `-x`, bypassing the binstub's build-machine shebang.
- musl: `ruby:4.0-alpine` builds ruby shared, so the NEEDED system libs
  (`libssl.so.3`, `libcrypto.so.3`, `libz.so.1`, `libgmp.so.10`, `libffi.so.8`,
  `libyaml-0.so.2`, `libgcc_s.so.1`) are bundled into `ruby/lib` and found via
  `LD_LIBRARY_PATH` (musl searches it before rpath). glibc/macOS builds are
  static and need no such handling.
- Pruning: keep the whole stdlib (`lib/ruby/<ver>/`) — users' ERB templates
  can require arbitrary stdlib. Delete dev/doc artifacts only: `*.a`,
  `include/`, `share/`, `libexec/`, `etc/`, `lib/pkgconfig`, rdoc trees, gem
  `doc`/`cache`/`build_info`, and the dev default gems (`rbs`, `msgpack`,
  `debug`, `rdoc`, `typeprof`, `syntax_suggest`). Keep only `ruby` in
  `ruby/bin`. Strip (`--strip-unneeded`; `-x` on macOS) the interpreter and
  every extension.
- Linkage audit (`src/audit-linkage.sh`, run by `just build`): every
  dependency of the interpreter, the bundled extensions, and the gem
  extensions must resolve to a system dir or the bundled `ruby/lib` — fail
  loudly rather than ship a bundle that breaks on user machines.
- Releases stay keyed to the Bashly version only (no Ruby-CVE trigger).

## Resolved questions

1. `ruby/` subdir vs top-level `bin/`/`lib/`: `ruby/` subdir — mise only
   exposes top-level `bin/` on PATH, and ruby's `bin/` + `lib/` must stay
   under one root.
2. Shared `libruby.so` for musl via `LD_LIBRARY_PATH`; static for
   glibc/macOS (mise/jdx builds).
3. Aggressive pruning: keep the whole stdlib; delete dev/doc artifacts only.
4. Releases stay keyed to the Bashly version.
