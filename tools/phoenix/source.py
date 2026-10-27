"""Fetch the Phoenix server's source from GitHub for the build scripts.

    python3 tools/phoenix/source.py              fetch, and print the folder and the commit
    python3 tools/phoenix/source.py --offline    the folder and commit as last fetched

See phoenix/__init__.py.
"""
import argparse
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# the server the data is made for: its name as players know it, where its source is, and the branch
# live runs
NAME = 'Phoenix'
REPOSITORY = 'https://github.com/phoenixffxi/Phoenix.git'
BRANCH = 'live'
# What the build scripts read of the server, and nothing else: the navmeshes alone are larger than all of it
PATHS = ('data', 'scripts', 'modules', 'settings', 'sql', 'src/map')


def cache_for(branch):
    return ROOT / '.cache' / f'phoenix-{branch}'


def git(*args, cwd=None):
    result = subprocess.run(('git',) + args, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f'git {" ".join(args)} failed:\n{result.stderr.strip()}')
    return result.stdout.strip()


class Source:
    """A server checkout to read: where it is, and what it was made from."""

    def __init__(self, path, repository, branch, commit, committed):
        self.path, self.repository, self.branch = Path(path), repository, branch
        self.commit, self.committed = commit, committed

    def __iter__(self):  # server, commit = source.fetch()
        return iter((self.path, self.commit))

    def describe(self):
        return f'{self.repository} {self.branch} at {self.commit[:9]} ({self.committed})'


def read(path, repository=None, branch=None):
    """What a checkout is at, fetched or not."""
    path = Path(path)
    if not (path / '.git').exists():
        return Source(path, repository or str(path), branch or '', '', '')
    commit = git('rev-parse', 'HEAD', cwd=path)
    committed = git('show', '-s', '--format=%cI', 'HEAD', cwd=path)
    if repository is None:
        repository = subprocess.run(('git', 'remote', 'get-url', 'origin'), cwd=path, capture_output=True, text=True).stdout.strip() or str(path)
    if branch is None:
        branch = subprocess.run(('git', 'rev-parse', '--abbrev-ref', 'HEAD'), cwd=path, capture_output=True, text=True).stdout.strip()
    return Source(path, repository, branch, commit, committed)


def fetch(branch=BRANCH, repository=REPOSITORY, offline=False):
    """The branch's newest commit, in the cache: cloned the first time, moved on after that."""
    path = cache_for(branch)
    if offline:
        if not (path / '.git').exists():
            sys.exit(f'{path} has never been fetched: run without --offline first')
        return read(path, repository, branch)
    if not (path / '.git').exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        print(f'Cloning {repository} {branch} into {path} ...', file=sys.stderr)
        git('clone', '--depth', '1', '--branch', branch, '--filter=blob:none', '--sparse', repository, str(path))
        git('sparse-checkout', 'set', *PATHS, cwd=path)
    else:
        print(f'Fetching {repository} {branch} ...', file=sys.stderr)
        git('remote', 'set-url', 'origin', repository, cwd=path)
        git('sparse-checkout', 'set', *PATHS, cwd=path)
        git('fetch', '--depth', '1', 'origin', branch, cwd=path)
        git('reset', '--hard', 'FETCH_HEAD', cwd=path)
        git('clean', '-fdq', cwd=path)
    return read(path, repository, branch)


def resolve(server=None, branch=BRANCH, offline=False):
    """A script's --server if it was given, or the fetched branch."""
    if server is not None:
        return read(server)
    return fetch(branch, offline=offline)


def add_arguments(parser):
    """--server, --branch and --offline, the same for every build script."""
    parser.add_argument('--server', type=Path,
                        help='Read this server checkout instead of fetching from GitHub (for a change not pushed yet).')
    parser.add_argument('--branch', default=BRANCH, help=f'The branch of {REPOSITORY} to fetch; default {BRANCH}.')
    parser.add_argument('--offline', action='store_true', help='Use the copy fetched last time, without fetching.')


def from_arguments(args):
    return resolve(args.server, args.branch, args.offline)


def now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_arguments(parser)
    found = from_arguments(parser.parse_args())
    print(found.path)
    print(found.describe())
