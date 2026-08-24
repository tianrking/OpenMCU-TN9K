#!/usr/bin/env sh
# Build the portable OpenMCU SDK on Linux and macOS.  This intentionally uses
# the same CMake toolchain file and executable-prefix contract as
# build-sdk.ps1, so an application has one reproducible firmware definition
# across all supported developer hosts.

set -eu

usage() {
  cat <<'EOF'
Usage: scripts/build-sdk.sh [options]

Options:
  --build-dir <path>       SDK build directory (default: <repo>/build/sdk)
  --riscv-prefix <prefix>  GNU executable prefix (default: riscv-none-elf-)
  --cmake <path>           CMake executable (default: cmake on PATH)
  --ninja <path>           Ninja executable (default: ninja on PATH)
  --fresh                  Request CMake --fresh (requires CMake 3.24+)
  -h, --help               Show this help text

Environment equivalents: OMCU_SDK_BUILD_DIR, OMCU_RISCV_PREFIX,
OMCU_CMAKE and OMCU_NINJA.  The selected toolchain must expose both
<prefix>gcc and <prefix>objcopy on PATH.
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
build_dir=${OMCU_SDK_BUILD_DIR:-"$project_root/build/sdk"}
riscv_prefix=${OMCU_RISCV_PREFIX:-riscv-none-elf-}
cmake_path=${OMCU_CMAKE:-cmake}
ninja_path=${OMCU_NINJA:-ninja}
fresh=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --build-dir)
      [ "$#" -ge 2 ] || { echo "--build-dir requires a value" >&2; exit 2; }
      build_dir=$2
      shift 2
      ;;
    --riscv-prefix)
      [ "$#" -ge 2 ] || { echo "--riscv-prefix requires a value" >&2; exit 2; }
      riscv_prefix=$2
      shift 2
      ;;
    --cmake)
      [ "$#" -ge 2 ] || { echo "--cmake requires a value" >&2; exit 2; }
      cmake_path=$2
      shift 2
      ;;
    --ninja)
      [ "$#" -ge 2 ] || { echo "--ninja requires a value" >&2; exit 2; }
      ninja_path=$2
      shift 2
      ;;
    --fresh)
      fresh=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$riscv_prefix" ]; then
  echo "--riscv-prefix must not be empty (for example: riscv-none-elf-)" >&2
  exit 2
fi

if ! command -v "$cmake_path" >/dev/null 2>&1; then
  echo "Missing CMake: $cmake_path. Install CMake 3.20 or later, or pass --cmake." >&2
  exit 1
fi
cmake_path=$(command -v "$cmake_path")
if ! command -v "$ninja_path" >/dev/null 2>&1; then
  echo "Missing Ninja: $ninja_path. Install Ninja, or pass --ninja." >&2
  exit 1
fi
ninja_path=$(command -v "$ninja_path")
if ! command -v "${riscv_prefix}gcc" >/dev/null 2>&1 || \
   ! command -v "${riscv_prefix}objcopy" >/dev/null 2>&1; then
  echo "Could not find ${riscv_prefix}gcc and ${riscv_prefix}objcopy on PATH." >&2
  echo "Install a matching GNU bare-metal RISC-V toolchain or pass --riscv-prefix." >&2
  exit 1
fi

set -- -S "$project_root/sdk" -B "$build_dir" -G Ninja \
  "-DCMAKE_MAKE_PROGRAM:FILEPATH=$ninja_path" \
  "-DCMAKE_TOOLCHAIN_FILE:FILEPATH=$project_root/sdk/cmake/riscv32-gcc.cmake" \
  "-DOMCU_RISCV_PREFIX:STRING=$riscv_prefix"

if [ "$fresh" -eq 1 ]; then
  cmake_version=$("$cmake_path" --version | sed -n 's/^cmake version //p' | sed -n '1p')
  cmake_major=$(printf '%s' "$cmake_version" | cut -d. -f1)
  cmake_minor=$(printf '%s' "$cmake_version" | cut -d. -f2)
  case "$cmake_major:$cmake_minor" in
    ''|*[!0-9:]*|*:*:*)
      echo "Unable to determine the CMake version for --fresh: $cmake_version" >&2
      exit 1
      ;;
  esac
  if [ "$cmake_major" -lt 3 ] || { [ "$cmake_major" -eq 3 ] && [ "$cmake_minor" -lt 24 ]; }; then
    echo "--fresh requires CMake 3.24 or later; choose a new build directory instead." >&2
    exit 1
  fi
  set -- --fresh "$@"
fi

"$cmake_path" "$@"
"$cmake_path" --build "$build_dir" --parallel

echo "PASS: built OpenMCU RV32IMC SDK images in $build_dir"
echo "Compiler: $(command -v "${riscv_prefix}gcc")"
echo "Objcopy: $(command -v "${riscv_prefix}objcopy")"
