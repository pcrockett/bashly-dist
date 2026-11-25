#!/usr/bin/env bash
set -euo pipefail

version="$1"
os="$2"
arch="$3"

# we don't want or need dependency gem archives to be bundled in the final artifact, but
# we do still want to cache them during build to avoid unnecessary redownloads. so we
# move the cache into the build dir while building, and then back out when the build
# is finished.
setup_gem_cache() {
  mkdir -p build/gems

  if [ -d .gem-cache ]; then
    mv .gem-cache build/gems/cache
  fi
}

teardown_gem_cache() {
  mv build/gems/cache .gem-cache
}

bundle_ruby() {
  # bin/ and lib/ must stay under one root because ruby resolves its prefix
  # relative to the executable. Ask the interpreter for its prefix: in CI,
  # PATH holds mise shims, not the real install dir (/usr/local in alpine).
  ruby_prefix="$(ruby -rrbconfig -e 'print RbConfig::CONFIG["prefix"]')"
  cp -a "${ruby_prefix}" build/ruby

  case "${arch}" in
    *-musl)
      # [ref:musl-ruby-image] builds ruby shared against system libs; bundle the
      # exact NEEDED set so the loader finds them via LD_LIBRARY_PATH
      for lib in libssl.so.3 libcrypto.so.3 libz.so.1 libgmp.so.10 \
        libffi.so.8 libyaml-0.so.2 libgcc_s.so.1; do
        cp -L "/usr/lib/${lib}" build/ruby/lib/
      done
      ;;
  esac
}

prune_ruby() {
  # Prune dev/doc artifacts; keep the whole stdlib so users' ERB templates
  # can require it
  shopt -s nullglob
  find build/ruby -name '*.a' -delete
  rm -rf build/ruby/include build/ruby/share build/ruby/libexec build/ruby/etc
  rm -rf build/ruby/lib/pkgconfig build/ruby/lib/ruby/*/rdoc
  rm -rf build/ruby/lib/ruby/gems/*/doc build/ruby/lib/ruby/gems/*/cache \
    build/ruby/lib/ruby/gems/*/build_info
  for gem_name in rbs msgpack debug rdoc typeprof syntax_suggest; do
    rm -rf build/ruby/lib/ruby/gems/*/gems/"${gem_name}"-*
    rm -f build/ruby/lib/ruby/gems/*/specifications/"${gem_name}"-*.gemspec \
      build/ruby/lib/ruby/gems/*/specifications/default/"${gem_name}"-*.gemspec
  done
  # keep only the interpreter itself
  for exe in build/ruby/bin/*; do
    [ "${exe##*/}" = ruby ] || rm -f "${exe}"
  done
  shopt -u nullglob

  # Strip dev symbols: the tarball is ~4x smaller
  case "${os}" in
    macos) strip_flags=(-x) ;;
    *) strip_flags=(--strip-unneeded) ;;
  esac
  strip "${strip_flags[@]}" build/ruby/bin/ruby
  find build/ruby/lib -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.bundle' -o -name '*.dylib' \) \
    -exec strip "${strip_flags[@]}" {} +
}

main() {
  setup_gem_cache
  gem install bashly --version "${version}" --install-dir build/gems --no-document
  teardown_gem_cache

  mkdir build/bin
  cp src/bashly-wrapper build/bin/bashly

  bundle_ruby
  prune_ruby

  cp licenses/ruby/* build/ruby/

  # Linkage audit: every dep must resolve to a system dir or the bundled
  # ruby/lib; fail loudly rather than ship a bundle that breaks elsewhere
  src/audit-linkage.sh build "${os}"

  mkdir -p artifacts
  tarball_path="artifacts/bashly-${version}-${os}-${arch}.tar.gz"
  rm -f "${tarball_path}"
  tar czf "${tarball_path}" -C build bin gems ruby
}

main
