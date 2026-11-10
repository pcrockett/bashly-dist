set positional-arguments

[private]
_default:
    @just --list

# Run pre-commit on all files
lint:
    pre-commit run --all --show-diff-on-failure --color always

# Get latest Bashly release version
latest-version:
    gh release --repo bashly-framework/bashly \
        list --exclude-drafts --exclude-pre-releases \
        --json tagName,isLatest \
        --jq '.[] | select(.isLatest).tagName | ltrimstr("v")'

# Build the release archive
build version os arch: clean
    #!/usr/bin/env bash
    set -euo pipefail

    version="$1"
    os="$2"
    arch="$3"

    mkdir -p build/gems

    if [ -d .gem-cache ]; then
        mv .gem-cache build/gems/cache
    fi
    gem install bashly --version "${version}" --install-dir build/gems --no-document
    mv build/gems/cache .gem-cache

    mkdir build/bin
    cp src/bashly-wrapper build/bin/bashly

    # Bundle the ruby that built the gems so the tarball is self-contained;
    # bin/ and lib/ must stay under one root because ruby resolves its prefix
    # relative to the executable. Ask the interpreter for its prefix: in CI,
    # PATH holds mise shims, not the real install dir (/usr/local in alpine).
    ruby_prefix="$(ruby -rrbconfig -e 'print RbConfig::CONFIG["prefix"]')"
    cp -a "${ruby_prefix}" build/ruby

    case "${arch}" in
      *-musl)
        # ruby:4.0-alpine builds ruby shared against system libs; bundle the
        # exact NEEDED set so the loader finds them via LD_LIBRARY_PATH
        for lib in libssl.so.3 libcrypto.so.3 libz.so.1 libgmp.so.10 \
            libffi.so.8 libyaml-0.so.2 libgcc_s.so.1; do
            cp -L "/usr/lib/${lib}" build/ruby/lib/
        done
        ;;
    esac

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

    cp licenses/ruby/* build/ruby/

    # Linkage audit: every dep must resolve to a system dir or the bundled
    # ruby/lib; fail loudly rather than ship a bundle that breaks elsewhere
    src/audit-linkage.sh build "${os}"

    mkdir -p artifacts
    tarball_path="artifacts/bashly-${version}-${os}-${arch}.tar.gz"
    rm -f "${tarball_path}"
    tar czf "${tarball_path}" -C build bin gems ruby

# Smoke-test a built tarball
test version os arch:
    #!/usr/bin/env bash
    set -euo pipefail

    version="$1"
    os="$2"
    arch="$3"

    temp_dir="$(mktemp -d)"
    trap 'rm -rf "${temp_dir}"' EXIT
    tar xzf "artifacts/bashly-${version}-${os}-${arch}.tar.gz" -C "${temp_dir}"

    # mise puts only top-level bin/ on PATH, so nothing else may leak out
    bin_entries="$(find "${temp_dir}/bin" -mindepth 1 -maxdepth 1 -exec basename {} \;)"
    if [ "${bin_entries}" != "bashly" ]; then
        echo "FAIL: top-level bin/ must contain only bashly, got: ${bin_entries}"
        exit 1
    fi

    pushd "${temp_dir}" >/dev/null
    # hermetic: no modern ruby on PATH, so the binstub's polyglot fallback can
    # never leak in a system ruby
    hermetic() {
        env -i PATH="/usr/bin:/bin" HOME="${temp_dir}" "$@"
    }
    bashly_version="$(hermetic ./bin/bashly --version)"
    hermetic ./bin/bashly init
    hermetic ./bin/bashly generate
    if [ "${os}" = macos ]; then
        # the generated CLI needs bash >= 4.2; /bin/bash is 3.2 on macOS
        hermetic "$(command -v bash)" ./cli --help
    else
        hermetic ./cli --help
    fi
    popd >/dev/null

    if [ "${bashly_version}" = "${version}" ]; then
        echo "SUCCESS: bashly --version -> ${bashly_version}"
    else
        echo "FAIL: Expected '${version}', got '${bashly_version}'"
        exit 1
    fi

# Delete `build` directory
clean:
    rm -rf build

# Trigger the Release workflow in GitHub
release version:
    gh workflow run release.yml --ref main --field version={{version}}
