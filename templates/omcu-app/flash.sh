#!/usr/bin/env sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: ./flash.sh <serial-port> [omcu_flash.py options]" >&2
  exit 2
fi

app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sdk_dir=${OMCU_SDK_PATH:-}
port=$1
shift

if [ -z "$sdk_dir" ]; then
  echo "Set OMCU_SDK_PATH to <OpenMCU-TN9K>/sdk." >&2
  exit 2
fi
if [ ! -f "$app_dir/build/my_omcu_app.omcu" ]; then
  echo "Missing build/my_omcu_app.omcu; run ./build.sh first." >&2
  exit 1
fi

"${OMCU_PYTHON:-python3}" "$sdk_dir/../tools/omcu_flash.py" \
  --port "$port" --image "$app_dir/build/my_omcu_app.omcu" "$@"
