#!/usr/bin/env python3
"""winxi's rules set (addons/libs/winxi/data/rules): the server's game rules that the addons work
out what will happen with, read from its code as live runs it, for winxi.rules.

Each rule is read from the one place the server keeps it: a Lua table, a settings value (as
phoenix.modules.setting has live's), or a constant of its C++. Each reader expects the code as it is
written today and stops the build when it is not, naming the file, so a change on the server is
read again before anything is built from it; and a module that overrides the Lua, or a C++ module or
core patch that names the constant, stops it too (phoenix.modules.guard, cpp_modules_mentioning).

    treasureHunter   drop rate by Treasure Hunter level and the drop's bracket (scripts/combat/basic/treasure_hunter.lua)
    treasurePool     seconds an item stays in the pool (treasure_pool.cpp)
    haste            the magic, ability and gear caps (battle_entity.cpp) and the delay reduction cap (settings)
    hasteEffects     what Haste, Haste II, Hastega, Hasso and Spirit Surge give (the spell table, the effects)
    swing            the first round's wait after engaging, the server's logic tick, a ranged attack's
                     hold after the shot (attack_state.cpp, map_constants.h, range_state.h)
    resting          the healing tick and the effect pass, and what each tick restores, with and without
                     Signet or Sigil (map settings, zone_entities.cpp, scripts/effects/healing.lua)
    bind             the chance a damaging hit breaks bind (battleutils.cpp)

Run by tools/build_winxi_data.py as its 'rules' set.
"""
import io
import re
import sys
from pathlib import Path

from build_action_data import provenance, write_data
from phoenix import modules


def read(server, path):
    return modules.blank_comments((Path(server) / path).read_text(encoding='utf-8-sig'))


def find(server, path, pattern, what, flags=0):
    """The match of pattern in path, or the build stops saying what was looked for."""
    m = re.search(pattern, read(server, path), flags)
    if m is None:
        sys.exit(f'{path}: {what} is not where it was, or not as it was written: read it again')
    return m


def untouched(server, *words):
    """Stops the build where a C++ module or core patch names one of words."""
    found = modules.cpp_modules_mentioning(server, *words)
    if found:
        sys.exit(f'{", ".join(found)} name {", ".join(words)}: read what they change before building the rules')


def lua_override(server, prefix, word):
    """Stops the build where a module overrides what is read here; one whose target is not written
    out ('?') only where its code names word."""
    def handle(override):
        if override.target == '?' and word not in override.body:
            return 'target not written out; nothing of ' + word
        return None
    modules.guard(server, (prefix,), handle, out=io.StringIO())


def treasure_hunter(server):
    path = 'scripts/combat/basic/treasure_hunter.lua'
    lua_override(server, 'xi.combat.treasureHunter.', 'treasureHunter')
    table = find(server, path, r'treasureHunterTable\s*=\s*\{(.*?)\n\}', 'treasureHunterTable', re.S).group(1)
    levels = {int(th): [int(v) for v in values.split(',')] for th, values in re.findall(r'\[\s*(\d+)\]\s*=\s*\{([^}]*)\}', table)}
    brackets = find(server, path, r'dropBracketTable\s*=\s*\{(.*?)\n\}', 'dropBracketTable', re.S).group(1)
    brackets = [int(v) for v in re.findall(r'\{\s*(\d+)\s*\}', brackets)]
    clamp = find(server, path, r'thTier\s*=\s*utils\.clamp\(thTier,\s*0,\s*(\d+)\)', 'the TH level clamp')
    if not levels or any(len(row) != len(brackets) for row in levels.values()):
        sys.exit(f'{path}: the table\'s rows and brackets no longer agree')
    return {'Levels': levels, 'Brackets': brackets, 'MaxLevel': int(clamp.group(1)), 'Source': path}


def treasure_pool(server):
    path = 'src/map/treasure_pool.cpp'
    untouched(server, 'treasure_livetime')
    m = find(server, path, r'treasure_livetime\s*=\s*(\d+)(min|s)\s*;', 'treasure_livetime')
    return {'Seconds': int(m.group(1)) * (60 if m.group(2) == 'min' else 1), 'Source': path}


def haste(server):
    path = 'src/map/entities/battle_entity.cpp'
    untouched(server, 'HASTE_MAGIC', 'hasteMagic', 'DELAY_REDUCTION_CAP')
    caps = {}
    for name, var in (('Magic', 'hasteMagic'), ('Ability', 'hasteAbility')):
        caps[name] = float(find(server, path, var + r'\s*=\s*std::clamp<float>\(' + var + r',\s*-?[\d.]+f,\s*([\d.]+)f\)', f'{var}\'s clamp').group(1))
    caps['Gear'] = float(find(server, path, r'hasteGear\s*=\s*std::min\(hasteGear,\s*([\d.]+)f\)', 'hasteGear\'s cap').group(1))
    find(server, path, r'getMod\(xi::Mod::HASTE_MAGIC\)\s*/\s*10000\.0f', 'haste in ten-thousandths')
    reduction = modules.setting(server, 'main.DELAY_REDUCTION_CAP')
    return {'MagicCap': caps['Magic'], 'AbilityCap': caps['Ability'], 'GearCap': caps['Gear'],
            'DelayReductionCap': reduction, 'Assumed': 'main.DELAY_REDUCTION_CAP' in modules.LIVE_SETTINGS, 'Source': path}


def haste_effects(server, spell_ids):
    """Status -> the haste it gives, as parts of 1 (magic) or ability: the spells' powers where the
    spell table fixes them, and the effects that add a fixed amount."""
    effects = {}
    table = read(server, 'scripts/globals/spells/enhancing_spell.lua')
    spells = {}
    for name in ('HASTE', 'HASTE_II', 'HASTEGA'):
        m = re.search(r'\[xi\.magic\.spell\.' + name + r'\s*\]\s*=\s*\{\s*\d+,\s*xi\.effect\.HASTE,\s*\d+,\s*(\d+),', table)
        if m is None:
            sys.exit(f'scripts/globals/spells/enhancing_spell.lua: {name}\'s row is not as it was')
        spells[spell_ids[name]] = int(m.group(1)) / 10000
    effects['Spells'] = spells
    # an effect that adds a fixed amount: its own script, or the module's override of its onEffectGain on live
    fixed = {}
    for effect, status, mod in (('hasso', 'HASSO', 'TWOHAND_HASTE_ABILITY'), ('spirit_surge', 'SPIRIT_SURGE', None)):
        value, kind = None, None
        for override in modules.overrides(server):
            if override.applies and override.target in (f'xi.effects.{effect}.onEffectGain', f'xi.job_utils.dragoon.useSpiritSurge'):
                for _, body in override.cases():
                    m = re.search(r'addMod\(xi\.mod\.(HASTE_MAGIC|HASTE_ABILITY|TWOHAND_HASTE_ABILITY),\s*(\d+)\)', body)
                    if m:
                        kind, value = m.group(1), int(m.group(2))
        if value is None:
            text = read(server, f'scripts/effects/{effect}.lua')
            m = re.search(r'addMod\(xi\.mod\.(HASTE_MAGIC|HASTE_ABILITY|TWOHAND_HASTE_ABILITY),\s*(\d+)\)', text)
            if m is None:
                sys.exit(f'scripts/effects/{effect}.lua: no fixed haste in it, nor in a module\'s override of it')
            kind, value = m.group(1), int(m.group(2))
        fixed[status] = {'Haste': value / 10000, 'Kind': 'magic' if kind == 'HASTE_MAGIC' else 'ability',
                         'TwoHanded': kind == 'TWOHAND_HASTE_ABILITY'}
    effects['Fixed'] = fixed
    return effects


def swing(server):
    untouched(server, 'kEngageDelay', 'kLogicUpdateRate', 'm_returnWeaponDelay')
    engage = find(server, 'src/map/ai/states/attack_state.cpp', r'kEngageDelay\s*=\s*(\d+)s\s*;', 'kEngageDelay')
    rate = find(server, 'src/map/map_constants.h', r'kLogicUpdateRate\s*=\s*([\d.]+)f\s*;', 'kLogicUpdateRate')
    ranged = find(server, 'src/map/ai/states/range_state.h', r'm_returnWeaponDelay\s*=\s*(\d+)ms\s*;', 'm_returnWeaponDelay')
    find(server, 'src/map/ai/states/ability_state.cpp', r'GetEntryTime\(\)\s*\+\s*m_castTime\s*\+\s*m_PAbility->getAnimationTime\(\)',
         'an ability holding the swing for its animation time')
    return {'EngageDelay': int(engage.group(1)), 'Tick': round(1 / float(rate.group(1)), 3),
            'RangedHold': int(ranged.group(1)) / 1000, 'ActionHold': 'animationTime',
            'Note': 'a spell, ability or weapon skill holds the swing for its own animationTime (winxi.spells, abilities, weaponskills)'}


def resting(server):
    path = 'scripts/effects/healing.lua'
    lua_override(server, 'xi.effects.healing.', 'healing')
    untouched(server, 'HEALING_TICK_DELAY', 'm_EffectCheckTime')
    passes = find(server, 'src/map/zone_entities.cpp', r'm_EffectCheckTime\s*=\s*m_EffectCheckTime\s*\+\s*(\d+)s', 'the effect pass')
    mp = find(server, path, r'local healMP\s*=\s*(\d+)\s*\+\s*\(\(healtime\s*-\s*2\)\s*\*\s*\(1\s*\+', 'the MP a tick restores')
    signet = find(server, path, r'healHP\s*=\s*(\d+)\s*\+\s*\((\d+)\s*\*\s*math\.floor\(target:getMainLvl\(\)\s*/\s*(\d+)\)\)\s*\+\s*'
                  r'\(healtime\s*-\s*2\)\s*\*\s*\(1\s*\+\s*math\.floor\(target:getMaxHP\(\)\s*/\s*(\d+)\)\)', 'the HP under Signet or Sigil')
    plain = find(server, path, r'healHP\s*=\s*(\d+)\s*\+\s*\(healtime\s*-\s*2\)\s*\+\s*target:getMod', 'the HP without Signet')
    find(server, path, r'target:hasStatusEffect\(xi\.effect\.SIGNET\)', 'Signet\'s part')
    find(server, path, r'target:hasStatusEffect\(xi\.effect\.SIGIL\)', 'Sigil\'s part')
    return {'Tick': modules.setting(server, 'map.HEALING_TICK_DELAY'), 'EffectPass': int(passes.group(1)),
            'Mp': {'Base': int(mp.group(1)), 'PerTick': 1},
            'Hp': {'Base': int(plain.group(1)), 'PerTick': 1},
            'HpSignet': {'Base': int(signet.group(1)), 'PerTenLevels': int(signet.group(2)), 'Levels': int(signet.group(3)),
                         'MaxHpPerTick': int(signet.group(4))},
            'Source': path}


def bind(server):
    path = 'src/map/utils/battleutils.cpp'
    untouched(server, 'BindBreakChance', 'BindBreakCheck')
    m = find(server, path, r'uint16\s+BindBreakChance\s*=\s*(\d+);', 'BindBreakChance')
    find(server, path, r'BindBreakChance\s*>\s*xirand::GetRandomNumber\(1000\)', 'the chance out of 1000')
    return {'BreakChance': int(m.group(1)) / 1000, 'Source': path}


def build(server, output, settings=()):
    server, output = Path(server), Path(output)
    from build_debuff_durations import enum_block
    spell_ids = enum_block((server / 'scripts/enum/magic.lua').read_text(), 'xi.magic.spell')
    rules = {
        'treasureHunter': treasure_hunter(server),
        'treasurePool': treasure_pool(server),
        'haste': haste(server),
        'hasteEffects': haste_effects(server, spell_ids),
        'swing': swing(server),
        'resting': resting(server),
        'bind': bind(server),
    }
    output.mkdir(parents=True, exist_ok=True)
    write_data(output / 'index.lua', {'Schema': 1, 'Source': provenance(server), 'Settings': list(settings),
                                      'LiveSettings': dict(modules.LIVE_SETTINGS), 'Rules': rules})
    print(f'rules: {", ".join(rules)}')


if __name__ == '__main__':
    import argparse
    from phoenix import source
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source.add_arguments(parser)
    args = parser.parse_args()
    found = source.from_arguments(args)
    print(f'Server: {found.describe()}')
    build(found.path, Path(__file__).resolve().parents[1] / 'addons/libs/winxi/data/rules')
