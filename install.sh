#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 ManateeLazyCat

set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_id=io.github.manateelazycat.desktop-top
config_base=${XDG_CONFIG_HOME:-$HOME/.config}
plugin_target=$config_base/omarchy/plugins/$plugin_id
backup_root=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/desktop-top/backups
enable_plugin=true
if [[ ${1:-} == --no-enable ]]; then
  enable_plugin=false
elif [[ $# -gt 0 ]]; then
  printf 'Usage: bash install.sh [--no-enable]\n' >&2
  exit 2
fi

for command in cmake pkg-config quickshell btop hyprctl omarchy jq python3; do
  command -v "$command" >/dev/null || { printf 'Missing dependency: %s\n' "$command" >&2; exit 1; }
done
cmake -S "$project_root" -B "$project_root/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$project_root/build" -j "$(nproc)"
omarchy plugin validate "$project_root"
hypr_config=$config_base/hypr/hyprland.lua
[[ -f $hypr_config ]] || { printf 'Hyprland Lua configuration is required.\n' >&2; exit 1; }
mkdir -p -- "$backup_root"
if [[ -f $config_base/omarchy/shell.json ]]; then
  cp -- "$config_base/omarchy/shell.json" "$backup_root/shell-$(date +%Y%m%d-%H%M%S-%N).json"
fi
# Stage a complete plugin outside the watched plugins tree, then swap it in.
mkdir -p -- "$(dirname -- "$plugin_target")"
stage=$(mktemp -d "$config_base/omarchy/.desktop-top-install.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
for file in manifest.json Service.qml hyprland.lua README.md README.zh-CN.md LICENSE; do
  install -m 644 -- "$project_root/$file" "$stage/$file"
done
cp -r -- "$project_root/renderer" "$stage/renderer"
if [[ -d $project_root/assets ]]; then cp -r -- "$project_root/assets" "$stage/assets"; fi
mkdir -- "$stage/qml"
cp -r -- "$project_root/build/qml/DesktopTop" "$stage/qml/DesktopTop"
if [[ -d $plugin_target ]]; then
  mv -- "$plugin_target" "$backup_root/plugin-$(date +%Y%m%d-%H%M%S-%N)"
fi
mv -- "$stage" "$plugin_target"
python3 - "$hypr_config" "$backup_root" <<'PY'
from datetime import datetime
from pathlib import Path
import shutil
import sys
config = Path(sys.argv[1])
text = config.read_text()
if '-- >>> omarchy-desktop-top >>>' not in text:
    shutil.copy2(config, Path(sys.argv[2]) / ('hyprland-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.lua'))
    config.write_text(text.rstrip() + '''

-- >>> omarchy-desktop-top >>>
do
  local path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config"))
    .. "/omarchy/plugins/io.github.manateelazycat.desktop-top/hyprland.lua"
  local file = io.open(path, "r")
  if file then file:close(); dofile(path) end
end
-- <<< omarchy-desktop-top <<<
''')
PY
hyprctl reload >/dev/null
config_errors=$(hyprctl configerrors)
if [[ -n ${config_errors//[[:space:]]/} ]]; then
  printf 'Hyprland config errors:\n%s\n' "$config_errors" >&2
  exit 1
fi
omarchy-shell shell rescanPlugins
discovered=false
for attempt in {1..50}; do
  if omarchy plugin list --json | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' >/dev/null; then
    discovered=true
    break
  fi
  sleep 0.1
done
[[ $discovered == true ]] || { printf 'Plugin discovery timed out.\n' >&2; exit 1; }
if [[ $enable_plugin == true ]]; then
  omarchy plugin enable "$plugin_id"
  printf 'Desktop Top installed and enabled: %s\n' "$plugin_target"
else
  printf 'Desktop Top installed; activation unchanged: %s\n' "$plugin_target"
fi
