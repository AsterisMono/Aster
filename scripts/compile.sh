#!/usr/bin/env bash
# Prepare and compile Aster. This script runs inside the build image.

set -Eeuo pipefail
umask 022

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/build/src"
CACHE="$REPO_ROOT/build/download_cache"
OUT="out/Default"
JOBS="${JOBS:-$(nproc)}"
SOURCE_STATE_SCHEMA=3

log() {
  printf '\n\033[1;34m==> %s\033[0m\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer (got '$JOBS')"
[ "$(uname -m)" = x86_64 ] || die "the build container must run as linux/amd64"

EXPECTED_VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/chromium_version.txt")"
SOURCE_MARKER="$SRC/.aster-source-state"
DOMSUB_CACHE="$SRC/.aster-domsub-cache.tar.gz"

chromium_tree_version() {
  local version_file="$1"
  awk -F= '
    $1 == "MAJOR" { major=$2 }
    $1 == "MINOR" { minor=$2 }
    $1 == "BUILD" { build=$2 }
    $1 == "PATCH" { patch=$2 }
    END {
      if (major != "" && minor != "" && build != "" && patch != "")
        printf "%s.%s.%s.%s", major, minor, build, patch
    }
  ' "$version_file"
}

source_fingerprint() {
  local -a inputs=(
    "$REPO_ROOT/chromium_version.txt"
    "$REPO_ROOT/downloads.ini"
    "$REPO_ROOT/pruning.list"
    "$REPO_ROOT/domain_regex.list"
    "$REPO_ROOT/domain_substitution.list"
    "$REPO_ROOT/flags.gn"
  )
  local file

  while IFS= read -r -d '' file; do
    inputs+=("$file")
  done < <(find "$REPO_ROOT/patches" -type f -print0 | sort -z)
  while IFS= read -r -d '' file; do
    inputs+=("$file")
  done < <(find "$REPO_ROOT/utils" -maxdepth 1 -type f -name '*.py' -print0 | sort -z)

  {
    printf 'schema=%s\n' "$SOURCE_STATE_SCHEMA"
    for file in "${inputs[@]}"; do
      printf '%s\0' "${file#"$REPO_ROOT"/}"
      sha256sum "$file"
    done
  } | sha256sum | awk '{print $1}'
}

prepare_source() {
  SOURCE_FINGERPRINT="$(source_fingerprint)"
  SOURCE_READY=0
  if [ -f "$SOURCE_MARKER" ] \
      && [ "$(cat "$SOURCE_MARKER")" = "$SOURCE_FINGERPRINT" ] \
      && [ -f "$SRC/chrome/VERSION" ] \
      && [ "$(chromium_tree_version "$SRC/chrome/VERSION")" = "$EXPECTED_VERSION" ] \
      && [ -f "$SRC/third_party/ublock/manifest.json" ] \
      && [ -f "$SRC/third_party/sidebery/manifest.json" ] \
      && [ -x "$SRC/third_party/llvm-build/Release+Asserts/bin/clang" ] \
      && [ -x "$SRC/third_party/rust-toolchain/bin/rustc" ] \
      && [ -f "$SRC/build/linux/debian_bullseye_amd64-sysroot/.stamp" ]; then
    SOURCE_READY=1
  fi

  if [ "$SOURCE_READY" -eq 0 ]; then
    log "Preparing a clean Chromium $EXPECTED_VERSION source tree"
    mkdir -p "$CACHE"
    "$REPO_ROOT/utils/downloads.py" retrieve -c "$CACHE" -i "$REPO_ROOT/downloads.ini"

    # A failed patch, toolchain, or domain-substitution pass cannot be resumed
    # safely. The archives remain cached; recreate only the derived source tree.
    case "$SRC" in
      "$REPO_ROOT"/build/src) ;;
      *) die "refusing to replace unexpected source path: $SRC" ;;
    esac
    rm -rf -- "$SRC"
    mkdir -p "$SRC"

    "$REPO_ROOT/utils/downloads.py" unpack \
      -c "$CACHE" -i "$REPO_ROOT/downloads.ini" -- "$SRC"

    ACTUAL_VERSION="$(chromium_tree_version "$SRC/chrome/VERSION")"
    [ "$ACTUAL_VERSION" = "$EXPECTED_VERSION" ] \
      || die "downloaded Chromium is $ACTUAL_VERSION, expected $EXPECTED_VERSION"
    [ -f "$SRC/third_party/ublock/manifest.json" ] || die "uBlock extraction is incomplete"
    [ -f "$SRC/third_party/sidebery/manifest.json" ] || die "Sidebery extraction is incomplete"

    log "Pruning bundled binaries"
    "$REPO_ROOT/utils/prune_binaries.py" "$SRC" "$REPO_ROOT/pruning.list"

    log "Applying Aster and ungoogled-chromium patches"
    "$REPO_ROOT/utils/patches.py" apply "$SRC" "$REPO_ROOT/patches"

    # Fetch these while their source URLs are still pristine. Domain
    # substitution deliberately rewrites Google hostnames in the source tree.
    log "Installing Chromium clang toolchain"
    (cd "$SRC" && python3 tools/clang/scripts/update.py)

    log "Installing Chromium Rust toolchain"
    (cd "$SRC" && python3 tools/rust/update_rust.py)

    log "Installing Chromium amd64 sysroot"
    (cd "$SRC" && python3 build/linux/sysroot_scripts/install-sysroot.py --arch=amd64)

    log "Applying domain substitution"
    "$REPO_ROOT/utils/domain_substitution.py" apply \
      -r "$REPO_ROOT/domain_regex.list" \
      -f "$REPO_ROOT/domain_substitution.list" \
      -c "$DOMSUB_CACHE" \
      "$SRC"

    printf '%s\n' "$SOURCE_FINGERPRINT" > "$SOURCE_MARKER.tmp"
    mv -f "$SOURCE_MARKER.tmp" "$SOURCE_MARKER"
  else
    log "Source preparation and toolchains are current"
  fi
}

install_system_build_tools() {
  local gperf_path gperf_link node_path node_link

  gperf_path="$(command -v gperf)" || die "system gperf is missing from the build environment"
  gperf_link="$SRC/third_party/gperf/cipd/bin/gperf"

  mkdir -p "$(dirname "$gperf_link")"
  ln -sfn "$gperf_path" "$gperf_link"
  [ -x "$gperf_link" ] || die "could not expose system gperf to Chromium"

  node_path="$(command -v node)" || die "system node is missing from the build environment"
  node_link="$SRC/third_party/node/linux/node-linux-x64/bin/node"
  mkdir -p "$(dirname "$node_link")"
  ln -sfn "$node_path" "$node_link"
  [ -x "$node_link" ] || die "could not expose system node to Chromium"
}

prepare_source
install_system_build_tools

if [ -x "$SRC/$OUT/gn" ] && ! "$SRC/$OUT/gn" --version >/dev/null 2>&1; then
  rm -f -- "$SRC/$OUT/gn"
fi
if [ ! -x "$SRC/$OUT/gn" ]; then
  log "Bootstrapping GN"
  mkdir -p "$SRC/$OUT"
  GN_CLANG_DIR="$SRC/third_party/llvm-build/Release+Asserts/bin"
  [ -x "$GN_CLANG_DIR/clang++" ] || die "bundled clang++ is missing"
  [ -x "$GN_CLANG_DIR/llvm-ar" ] || die "bundled llvm-ar is missing"
  (cd "$SRC" && \
    CC="$GN_CLANG_DIR/clang" \
    CXX="$GN_CLANG_DIR/clang++" \
    AR="$GN_CLANG_DIR/llvm-ar" \
    CXXFLAGS="-Wno-error=deprecated-declarations" \
    ./tools/gn/bootstrap/bootstrap.py \
      --skip-generate-buildfiles \
      --build-path "$OUT" \
      -j "$JOBS")
fi

log "Writing GN arguments"
mkdir -p "$SRC/$OUT"
{
  cat "$REPO_ROOT/flags.gn"
  cat <<'GNARGS'

target_cpu = "x64"
is_debug = false
symbol_level = 0
blink_symbol_level = 0
is_component_build = false
use_sysroot = true

# The default non-official DevTools configuration transpiles TypeScript with
# a prebuilt esbuild binary. ungoogled-chromium deliberately prunes that
# binary, so use the retained JavaScript TypeScript compiler instead.
devtools_skip_typecheck = false
GNARGS
} > "$SRC/$OUT/args.gn.tmp"
mv -f "$SRC/$OUT/args.gn.tmp" "$SRC/$OUT/args.gn"

log "Generating Ninja files"
(cd "$SRC" && "./$OUT/gn" gen "$OUT" --fail-on-unused-args)

log "Building Chromium runtime (JOBS=$JOBS)"
(cd "$SRC" && ninja -C "$OUT" -j "$JOBS" \
  chrome \
  chrome_sandbox \
  chrome_crashpad_handler \
  chrome_management_service \
  chrome/installer/linux:common_packaging_files)

for required in chrome chrome_crashpad_handler chrome_management_service chrome_sandbox \
                resources.pak icudtl.dat installer/common/desktop.template; do
  [ -e "$SRC/$OUT/$required" ] || die "Ninja completed without $OUT/$required"
done
[ -f "$SRC/$OUT/locales/en-US.pak" ] || die "Ninja completed without the en-US locale"

log "Compilation complete"
