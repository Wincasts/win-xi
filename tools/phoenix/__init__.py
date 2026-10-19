"""The Phoenix server's source, as the build scripts read it: fetched from GitHub, never a local copy.

    from phoenix import source, importer, lotteries

    server, commit = source.fetch()     # the live branch of phoenixffxi/Phoenix, up to date
    module = importer.load()            # forks/addons/mobdb/mobdb/import_phoenix.py, as a module
    lotteries.from_slots(zone_document)  # a zone's lottery slots: each NM, its placeholders, chance, cooldown

The fetch is a shallow, sparse clone of only what the scripts read (data, scripts, modules,
settings, sql) into .cache/phoenix-<branch> at the project's root. That folder is the scripts' own:
each fetch moves it to the branch's newest commit and throws away anything changed in it, so it
is never a place to work. A script's --server still reads another checkout, for trying something
against a server change that is not on GitHub yet.
"""
from . import source, importer, lotteries  # noqa: F401
