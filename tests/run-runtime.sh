#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 ManateeLazyCat

set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runtime_root=$(mktemp -d -t desktop-top-runtime.XXXXXXXX)
trap 'rm -rf -- "$runtime_root"' EXIT
mkdir -- "$runtime_root/Plugin"
cp -r -- "$project_root/renderer" "$runtime_root/Plugin/renderer"
cp -- "$project_root/tests/Runtime.qml" "$runtime_root/shell.qml"
mkdir -p -- "$project_root/tests/output"
QML_IMPORT_PATH="$project_root/build/qml" QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
  DESKTOP_TOP_CAPTURE_PATH="$project_root/tests/output/preview.png" \
  timeout 25s quickshell -p "$runtime_root" --no-color 2>&1 | tee "$project_root/tests/output/runtime.log"
rg -q 'TOP_RUNTIME_PASSED' "$project_root/tests/output/runtime.log"
if rg -q 'TOP_RUNTIME_FAILED|TypeError|ReferenceError|Binding loop|Unable to assign' "$project_root/tests/output/runtime.log"; then exit 1; fi
