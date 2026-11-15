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
    ./src/build.sh {{version}} {{os}} {{arch}}

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
