#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 ManateeLazyCat

"""Exercise installer deployment in a fixture without touching the desktop."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = 'io.github.manateelazycat.desktop-top'


def main():
    with tempfile.TemporaryDirectory(prefix='desktop-top-install-test-') as directory:
        fixture = Path(directory)
        config = fixture / 'config'
        target = config / 'omarchy/plugins' / PLUGIN
        target.mkdir(parents=True)
        for name in ['install.sh', 'manifest.json', 'Service.qml', 'hyprland.lua', 'README.md', 'README.zh-CN.md', 'LICENSE', 'CMakeLists.txt']:
            shutil.copy2(ROOT / name, target / name)
        for name in ['renderer', 'native']:
            shutil.copytree(ROOT / name, target / name)
        (target / '.git').mkdir()
        (target / '.git/HEAD').write_text('ref: refs/heads/main\n')
        (target / 'qml/DesktopTop').mkdir(parents=True)
        (target / 'qml/DesktopTop/old-module').write_text('previous build')
        (config / 'hypr').mkdir()
        (config / 'hypr/hyprland.lua').write_text('-- original config\n')
        (config / 'omarchy/shell.json').write_text('{"plugins": []}\n')
        commands = fixture / 'bin'
        commands.mkdir()
        scripts = {
            'cmake': '''#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -S ]]; then
  mkdir -p -- "$4/qml/DesktopTop"
  printf 'module DesktopTop\n' > "$4/qml/DesktopTop/qmldir"
fi
''',
            'omarchy': '''#!/usr/bin/env bash
if [[ ${1:-} == plugin && ${2:-} == list ]]; then
  printf '[{"id":"io.github.manateelazycat.desktop-top"}]\n'
fi
''',
            'hyprctl': '#!/usr/bin/env bash\nexit 0\n',
            'omarchy-shell': '#!/usr/bin/env bash\nexit 0\n',
        }
        for name, text in scripts.items():
            (commands / name).write_text(text)
            (commands / name).chmod(0o755)
        env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ['PATH'],
                   XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(fixture / 'state'))
        source_files = ['install.sh', 'native/Terminal.cpp', 'CMakeLists.txt', '.git/HEAD']
        before = {name: (target / name).read_bytes() for name in source_files}
        for _ in range(2):
            subprocess.run(['bash', str(target / 'install.sh'), '--no-enable'], env=env,
                           cwd=target, check=True, capture_output=True, text=True)
            assert all((target / name).read_bytes() == content for name, content in before.items())
            assert (target / 'qml/DesktopTop/qmldir').read_text() == 'module DesktopTop\n'
            assert not (target / 'qml/DesktopTop/old-module').exists()
        text = (config / 'hypr/hyprland.lua').read_text()
        assert text.count('-- >>> omarchy-desktop-top >>>') == 1
        assert text.startswith('-- original config\n')
        assert list((fixture / 'state/omarchy/desktop-top/backups').glob('shell-*.json'))
        print('PASS: repeated marketplace setup preserves source/Git, replaces the native module and backs up scoped config changes')


if __name__ == '__main__':
    main()
