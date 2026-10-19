"""mobdb's Phoenix importer, which every build script resolves monster names and zone ids with."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'forks/addons/mobdb/mobdb/import_phoenix.py'
CLIENT_NAMES = ROOT / 'forks/addons/mobdb/mobdb/client_names.json'


def load(name='phoenix_import'):
    spec = importlib.util.spec_from_file_location(name, SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def generator(server, out, settings=(), module=None):
    """An importer Generator over a server checkout, writing <zoneId>.lua files to out."""
    module = module or load()
    return module.Generator(SimpleNamespace(
        server=str(server), out=str(out), set=list(settings), no_module_data=False,
        names=str(CLIENT_NAMES), elements='rank', zone=None, include_steal=False))
