"""Build handoff ZIPs from explicit public file lists, never a workspace glob."""

import hashlib
from importlib.metadata import distribution
import json
from pathlib import Path
import sys
import zipfile

from . import __version__

ROOT = Path(__file__).resolve().parent.parent
MARKET_FILES = (
    '__init__.py', 'adapters.py', 'bootstrap.py', 'collector.py', 'contract.py',
    'database.py', 'server.py', 'schema.sql', 'Dockerfile', 'compose.yaml',
    'compose.collector.yaml', 'configure.py', 'New-Config.ps1', 'Start-Local.ps1',
    'Stop-Local.ps1', 'Build-Client.ps1', 'client_main.py', 'package.py',
    'requirements-server.txt', 'requirements-build.txt', 'client-config.example.json',
    'client-config.docker.example.json', 'README.md', 'CLIENT-README.txt',
    'grafana/dashboards/market.json', 'grafana/dashboards/comparison.json', 'grafana/provisioning/datasources/postgres.yaml',
    'grafana/provisioning/dashboards/market.yaml', 'tests/test_pipeline.py',
    'tests/test_integration.py', 'tests/fixtures/ProfitTop.lua', 'tests/fixtures/ProfitMasterAverages.lua',
)
TOOLS_FILES = ('profit_master_saved.py', 'ProfitMasterHistory.py',
               'test_profit_master_saved.py', 'test_profit_master_history.py')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def archive(path, entries):
    manifest = {name: sha(data) for name, data in sorted(entries.items())}
    if any(name.startswith('/') or '..' in Path(name).parts for name in entries):
        raise ValueError('Unsafe archive path')
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as output:
        for name, data in entries.items():
            output.writestr(name, data)
        output.writestr('MANIFEST.sha256.json', json.dumps(manifest, indent=2) + '\n')
    with zipfile.ZipFile(path) as check:
        if check.testzip() is not None or set(check.namelist()) != set(entries) | {'MANIFEST.sha256.json'}:
            raise ValueError('Archive entry verification failed')
        for name, expected in manifest.items():
            if sha(check.read(name)) != expected:
                raise ValueError('Archive content verification failed')
    print(f'{path.name}: {len(entries)} verified files, {path.stat().st_size:,} bytes')


def main():
    destination = ROOT / 'market/dist'
    destination.mkdir(parents=True, exist_ok=True)
    executable = destination / 'ProfitMarketClient.exe'
    if not executable.is_file():
        raise ValueError('Build the Windows EXE using market/Build-Client.ps1 first')
    python_license = Path(sys.base_prefix) / 'LICENSE.txt'
    pyinstaller_license = distribution('pyinstaller').locate_file('pyinstaller-6.22.3.dist-info/licenses/COPYING.txt')
    client = {
        'ProfitMarketClient.exe': executable.read_bytes(),
        'client-config.example.json': (ROOT / 'market/client-config.example.json').read_bytes(),
        'README.txt': (ROOT / 'market/CLIENT-README.txt').read_bytes(),
        'licenses/Python.txt': python_license.read_bytes(),
        'licenses/PyInstaller.txt': pyinstaller_license.read_bytes(),
    }
    server = {'.dockerignore': (ROOT / '.dockerignore').read_bytes()}
    server.update({f'market/{name}': (ROOT / 'market' / name).read_bytes() for name in MARKET_FILES})
    server.update({f'tools/{name}': (ROOT / 'tools' / name).read_bytes() for name in TOOLS_FILES})
    server['README.txt'] = b'Server handoff: read market/README.md. Run Docker Compose from this extracted root. No private configuration or market data is included.\n'
    names = (f'ProfitMarket-Windows-{__version__}.zip', f'ProfitMarket-Server-{__version__}.zip')
    for name, entries in zip(names, (client, server)):
        archive(destination / name, entries)
    hashes = '\n'.join(f'{sha((destination / name).read_bytes())}  {name}' for name in names)
    (destination / 'SHA256SUMS.txt').write_text(hashes + '\n', encoding='ascii')


if __name__ == '__main__':
    main()
