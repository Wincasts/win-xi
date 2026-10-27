"""The servers the build scripts can make data for: one profile each, every server-specific thing the
tools know in one place.

    from phoenix import profiles
    profiles.use('phoenix')      # what source, modules and the builders read from here on
    profiles.ACTIVE              # the profile in use

A profile says where the server's source is and which branch it runs (source.py fetches it into
.cache/<key>-<branch>), what it is called (the data's manifest carries the name), which expansions'
content it has on (LATEST_ENABLED, for modules' era gates), whether its core takes the YAML patch
for zone files (DATA_PATCH), and the settings it is known or taken to run with where its repository
only has the defaults (LIVE_SETTINGS). Every builder takes --server-profile; phoenix is the default.

Adding a server is adding a profile here: a LandSandBoat fork with the same layout needs nothing more,
and each of its assumptions is written beside it.
"""
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Profile:
    key: str                  # the data's folder (addons/libs/winxi/data/<key>) and the cache's name
    name: str                 # as players know the server
    repository: str
    branch: str
    latest_enabled: str       # the latest expansion whose content is on (xi.pre is true after it)
    data_patch: bool = True   # the core merges module YAML over zone files (modules/temp_patch/lsb-yaml.patch)
    live_settings: dict = field(default_factory=dict)  # 'file.NAME' -> value, where it is not the default
    notes: tuple = ()         # where each assumption comes from


PROFILES = {
    'phoenix': Profile(
        key='phoenix', name='Phoenix', repository='https://github.com/phoenixffxi/Phoenix.git', branch='live',
        latest_enabled='TOAU', data_patch=True,
        live_settings={'main.DELAY_REDUCTION_CAP': 0.93},
        notes=(
            'branch live: the branch the running server is taken to be built from (its name and merges)',
            'latest_enabled TOAU: init.txt applies the era SQL for WotG, Abyssea, SoA and RoV',
            'data_patch: init.txt names data folders (era/data/abyssea/...) only the patch reads',
            'main.DELAY_REDUCTION_CAP 0.93: ToAU\'s cap, tempo\'s note of Phoenix\'s, not confirmed',
        )),
}

DEFAULT = 'phoenix'
ACTIVE = PROFILES[DEFAULT]


def use(key):
    """Make a profile the one in use: source's repository and branch, modules' era and settings."""
    global ACTIVE
    if key not in PROFILES:
        raise SystemExit(f'No server profile {key!r}: the profiles are {", ".join(sorted(PROFILES))} (tools/phoenix/profiles.py)')
    ACTIVE = PROFILES[key]
    from . import modules, source
    source.NAME, source.REPOSITORY, source.BRANCH, source.KEY = ACTIVE.name, ACTIVE.repository, ACTIVE.branch, ACTIVE.key
    modules.LATEST_ENABLED, modules.DATA_PATCH = ACTIVE.latest_enabled, ACTIVE.data_patch
    modules.LIVE_SETTINGS = dict(ACTIVE.live_settings)
    return ACTIVE
