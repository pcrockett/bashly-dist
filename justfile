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
    mkdir -p build/gems

    if [ -d .gem-cache ]; then
        mv .gem-cache build/gems/cache
    fi
    gem install bashly --version "{{version}}" --install-dir build/gems --no-document
    mv build/gems/cache .gem-cache

    mkdir build/bin
    cp src/bashly-wrapper build/bin/bashly

    mkdir -p artifacts
    tarball_path="artifacts/bashly-{{version}}-{{os}}-{{arch}}.tar.gz"
    rm -f "${tarball_path}"
    tar czf "${tarball_path}" -C build bin gems

# Smoke-test a built tarball
test version os arch:
    #!/usr/bin/env bash
    set -euo pipefail
    temp_dir="$(mktemp -d)"
    tar xzf "artifacts/bashly-{{version}}-{{os}}-{{arch}}.tar.gz" -C "${temp_dir}"
    bashly_version="$("${temp_dir}/bin/bashly" --version)"
    rm -rf "${temp_dir}"
    if [ "${bashly_version}" = "{{version}}" ]; then
        echo "SUCCESS: Result of \`bashly --version\`: ${bashly_version}"
    else
        echo "FAIL: Result of \`bashly --version\`: ${bashly_version}"
        exit 1
    fi

# Delete `build` directory
clean:
    rm -rf build
