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

    gem install bashly --version "{{version}}" --install-dir build/gems --no-document

    mkdir build/bin
    cp src/bashly-wrapper build/bin/bashly

    mkdir -p build/tarball
    tarball_path="build/tarball/bashly-{{version}}-{{os}}-{{arch}}.tar.gz"
    rm -f "${tarball_path}"
    tar czf "${tarball_path}" -C build bin gems

# Smoke-test a built tarball
test version os arch:
    #!/usr/bin/env bash
    set -euo pipefail
    temp_dir="$(mktemp -d)"
    tar xzf "build/tarball/bashly-{{version}}-{{os}}-{{arch}}.tar.gz" -C "${temp_dir}"
    bashly_version="$("${temp_dir}/bin/bashly" --version)"
    rm -rf "${temp_dir}"
    if [ "${bashly_version}" = "{{version}}" ]; then
        echo "SUCCESS: Result of \`bashly --version\`: ${bashly_version}"
    else
        echo "FAIL: Result of \`bashly --version\`: ${bashly_version}"
        exit 1
    fi

# Delete everything in `build/gems` and `build/bin` except the cache
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    find build/gems -mindepth 1 -maxdepth 1 ! -name cache -exec rm -rf {} +
    rm -rf build/bin
