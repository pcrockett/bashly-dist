#!/usr/bin/env bash
# Linkage audit for the bundled ruby and gem extensions: every shared-library
# dependency must resolve to a system dir or the bundled ruby/lib, so the
# tarball cannot silently depend on build-machine paths (e.g. Homebrew).
# Usage: audit-linkage.sh <build-dir> <os: linux|macos>
set -euo pipefail

build_dir="$1"
os="$2"
bundled_lib="$(cd "${build_dir}/ruby/lib" && pwd)"

audit_fail=0

check_linux() {
  local file="$1" line lib_path resolved ldd_output
  if ! ldd_output="$(LD_LIBRARY_PATH="${bundled_lib}" ldd "${file}" 2>&1)"; then
    case "${ldd_output}" in
      *"not a dynamic executable"*) return ;;
    esac
    echo "AUDIT: ldd failed for ${file}:" >&2
    printf '%s\n' "${ldd_output}" >&2
    audit_fail=1
    return
  fi
  while IFS= read -r line; do
    case "${line}" in
      *"not found"* | *"Error loading shared library"*)
        echo "AUDIT: ${file}: ${line}" >&2
        audit_fail=1
        ;;
      *"=> "*)
        lib_path="${line#*=> }"
        lib_path="${lib_path%% *}"
        [ -n "${lib_path}" ] || continue
        resolved="$(realpath -- "${lib_path}" 2>/dev/null || printf '%s' "${lib_path}")"
        case "${resolved}" in
          /lib/* | /lib64/* | /usr/lib/* | /usr/lib64/* | "${bundled_lib}"/*) ;;
          *)
            echo "AUDIT: ${file}: dependency resolved outside system dirs and bundle: ${resolved}" >&2
            audit_fail=1
            ;;
        esac
        ;;
    esac
  done <<<"${ldd_output}"
}

resolve_macos_path() {
  # Resolves an @-prefixed install name/rpath against a file's LC_RPATHs.
  # Prints the candidate path, or nothing if it cannot be resolved.
  local dep="$1" file_dir="$2" rpaths="$3" rpath leaf cand
  case "${dep}" in
    @rpath/*) leaf="${dep#@rpath/}" ;;
    *) leaf="${dep#*/}" ;;
  esac
  if [ "${dep}" = "@rpath/${leaf}" ]; then
    while IFS= read -r rpath; do
      case "${rpath}" in
        @loader_path*) cand="${file_dir}${rpath#@loader_path}/${leaf}" ;;
        @executable_path*) cand="${build_dir}/ruby/bin${rpath#@executable_path}/${leaf}" ;;
        /*) cand="${rpath}/${leaf}" ;;
        *) continue ;;
      esac
      [ -e "${cand}" ] && printf '%s\n' "${cand}"
    done <<<"${rpaths}"
  else
    case "${dep}" in
      @loader_path/*) cand="${file_dir}${dep#@loader_path}" ;;
      @executable_path/*) cand="${build_dir}/ruby/bin${dep#@executable_path}" ;;
    esac
    [ -e "${cand}" ] && printf '%s\n' "${cand}"
  fi
}

check_macos() {
  local file="$1" file_dir dep rpath rp resolved cand
  file_dir="$(dirname "${file}")"
  local rpaths
  rpaths="$(otool -l "${file}" | awk '/cmd LC_RPATH/{getline; getline; print $2}')"

  # LC_RPATH entries must resolve into system dirs or the bundle
  while IFS= read -r rpath; do
    [ -n "${rpath}" ] || continue
    case "${rpath}" in
      /usr/lib/* | /System/*) continue ;;
      @loader_path*) rp="${file_dir}${rpath#@loader_path}" ;;
      @executable_path*) rp="${build_dir}/ruby/bin${rpath#@executable_path}" ;;
      /*) rp="${rpath}" ;;
      *) continue ;; # chained @rpath; caught via dependency resolution below
    esac
    resolved="$(realpath -q "${rp}" 2>/dev/null || printf '%s' "${rp}")"
    case "${resolved}" in
      /usr/lib/* | /System/* | "${bundled_lib}"/*) ;;
      *)
        echo "AUDIT: ${file}: LC_RPATH outside system dirs and bundle: ${rpath} -> ${resolved}" >&2
        audit_fail=1
        ;;
    esac
  done <<<"${rpaths}"

  while IFS= read -r dep; do
    [ -n "${dep}" ] || continue
    case "${dep}" in
      /usr/lib/* | /System/*) continue ;;
      /*)
        echo "AUDIT: ${file}: absolute dependency outside system dirs: ${dep}" >&2
        audit_fail=1
        continue
        ;;
    esac
    local found=0 rc
    while IFS= read -r cand; do
      [ -n "${cand}" ] || continue
      found=1
      rc="$(realpath "${cand}" 2>/dev/null || printf '%s' "${cand}")"
      case "${rc}" in
        /usr/lib/* | /System/* | "${bundled_lib}"/*) ;;
        *)
          echo "AUDIT: ${file}: ${dep} resolves outside system dirs and bundle: ${rc}" >&2
          audit_fail=1
          ;;
      esac
    done < <(resolve_macos_path "${dep}" "${file_dir}" "${rpaths}")
    if [ "${found}" != 1 ]; then
      echo "AUDIT: ${file}: unresolved @-path dependency: ${dep}" >&2
      audit_fail=1
    fi
  done < <(otool -L "${file}" | tail -n +2 | awk '{print $1}')
}

scan_dirs=("${build_dir}/ruby/bin" "${build_dir}/ruby/lib")
if [ -d "${build_dir}/gems/extensions" ]; then
  scan_dirs+=("${build_dir}/gems/extensions")
fi

while IFS= read -r -d '' file; do
  case "${os}" in
    macos) check_macos "${file}" ;;
    *) check_linux "${file}" ;;
  esac
done < <(find "${scan_dirs[@]}" -type f \
  \( -name ruby -o -name '*.so' -o -name '*.so.*' -o -name '*.bundle' -o -name '*.dylib' \) -print0)

if [ "${audit_fail}" != 0 ]; then
  echo "AUDIT FAILED: unresolved or non-system dependencies found; see above" >&2
  exit 1
fi
