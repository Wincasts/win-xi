"""The Phoenix server's source, as the build scripts read it: fetched from GitHub, never a local copy.

    from phoenix import source, importer, lotteries, modules

    server, commit = source.fetch()     # the live branch of phoenixffxi/Phoenix, up to date
    module = importer.load()            # forks/addons/mobdb/mobdb/import_phoenix.py, as a module
    lotteries.from_slots(zone_document)  # a zone's lottery slots: each NM, its placeholders, chance, cooldown
    modules.guard(server, prefixes, handle)  # the module overrides live loads over what a script reads

The server's scripts are not what live runs: modules/init.txt loads modules that replace parts of
them, gated on the era. Every build script that reads the server hands the overrides of what it
reads to modules.guard, which stops the build on any the script does not account for;
tools/test_phoenix_modules.py fails for a build script that does not.

The fetch is a shallow, sparse clone of only what the scripts read (data, scripts, modules,
settings, sql) into .cache/phoenix-<branch> at the project's root. That folder is the scripts' own:
each fetch moves it to the branch's newest commit and throws away anything changed in it, so it
is never a place to work. A script's --server still reads another checkout, for trying something
against a server change that is not on GitHub yet.
"""
from . import source, importer, lotteries, modules, profiles  # noqa: F401
