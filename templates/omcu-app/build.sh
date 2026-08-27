#!/usr/bin/env sh
set -eu

app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sdk_dir=${OMCU_SDK_PATH:-}
riscv_prefix=${OMCU_RISCV_PREFIX:-riscv-none-elf-}
cmake_path=${OMCU_CMAKE:-cmake}
ninja_path=${OMCU_NINJA:-ninja}

if [ -z "$sdk_dir" ]; then
  echo "Set OMCU_SDK_PATH to <OpenMCU-TN9K>/sdk." >&2
  exit 2
fi

"$cmake_path" -S "$app_dir" -B "$app_dir/build" -G Ninja \
  "-DCMAKE_MAKE_PROGRAM:FILEPATH=$ninja_path" \
  "-DOMCU_SDK_PATH:PATH=$sdk_dir" \
  "-DOMCU_RISCV_PREFIX:STRING=$riscv_prefix"
"$cmake_path" --build "$app_dir/build" --target my_omcu_app --parallel
"${OMCU_PYTHON:-python3}" "$sdk_dir/../tools/omcu_image.py" validate \
  --image "$app_dir/build/my_omcu_app.omcu"

echo "PASS: $app_dir/build/my_omcu_app.omcu"
