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
    burden           an automaton's burden: what it spawns with, what a maneuver adds, when it may
                     overload and the chance, how fast it falls, what Cooldown takes off
                     (scripts/globals/automaton.lua, pets/automaton.lua, automaton_entity.cpp,
                     job_utils/puppetmaster.lua)
    era              the expansions in the order they came, and the latest whose content live has on
                     (phoenix.modules.LATEST_ENABLED, inferred from what init.txt loads), with the
                     server's name: for what an addon shows of later content
    corsairRolls     each roll's lucky and unlucky number, by its ability: where its power peaks and falls
                     among 1 to 10, from job_utils/corsair.lua's rollData with the era modules' powers on
                     live put over it in the order they apply
    preventAction    the statuses that stop a player acting, auto-attacks among it (status_effect_container.cpp's
                     HasPreventActionEffect, as the player's AI asks it, charm aside), by number
    skillchain       when a skillchain can be closed: from so long after the weapon skill, for how long,
                     and how much shorter each step of a chain makes it (battleutils.cpp)
    magicCost        what changes a spell's MP: Light and Dark Arts' and the Addenda's fixed part of the white
                     and black magic cost mods (their effects' scripts), Penury and Parsimony halving it,
                     Manafont taking it (battleutils.cpp's CalculateSpellCost, magic_state.cpp); and the
                     ninja tools a NIN may use in place of a spell's own, by tool (HasNinjaTool), whose own
                     is its spell_list mpCost (winxi.spells)
    merits           the limit points a merit point is (merit.cpp's MAX_LIMIT_POINTS)
    weaponskillTp    the TP a weapon skill's extra hits return, each, before Store TP (scripts/globals/weaponskills.lua)
    automaton        what an automaton casts and uses: each spell's magic skill and the heads that cast it
                     (automaton_spells, module SQL over it), each frame's weapon skills with the skill
                     they need and the element whose maneuvers bring them on (its pet's skill list,
                     mob_skills, the skill's own script), and each head's magic timers (the era
                     module's on live, pets/automaton.lua's otherwise)

Run by tools/build_winxi_data.py as its 'rules' set.
"""
import io
import re
import sys
from pathlib import Path

from build_action_data import provenance, write_data
from phoenix import modules


def read(server, path):
    text = (Path(server) / path).read_text(encoding='utf-8-sig')
    if path.endswith(('.cpp', '.h')):
        return modules.blank_cpp_comments(text)
    return modules.blank_comments(text)


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


def burden(server):
    def handle(override):
        # what is read here, rewritten by a module, is read again before it is trusted
        if re.search(r'[Bb]urden', override.body):
            return None
        return 'nothing of burden'
    modules.guard(server, ('xi.automaton.', 'xi.pets.automaton.', 'xi.job_utils.puppetmaster.'), handle, out=io.StringIO())
    untouched(server, 'burdenTick', 'addBurden', 'overloadChance', 'OVERLOAD_THRESH')
    spawn = find(server, 'scripts/globals/pets/automaton.lua', r'for element = 0, 7 do\s*master:addBurden\(element,\s*(\d+)\)', 'the burden it spawns with')
    automaton = 'scripts/globals/automaton.lua'
    dark = find(server, automaton, r'VALOREDGE\s+or\s+frameEquipped == xi\.automaton\.frame\.SHARPSHOT\s+then\s+return (\d+)\s+end\s+return (\d+)',
                'a Dark maneuver\'s burden')
    stat = find(server, automaton, r'if statDifference >= (\d+) then\s+return (\d+)\s+elseif statDifference >= 0 then\s+return (\d+) - statDifference\s+else\s+return (\d+)',
                'a maneuver\'s burden by the stat')
    entity = 'src/map/entities/automaton_entity.cpp'
    thresh = find(server, entity, r'const int16 thresh = (\d+) \+ PMaster->getMod\(xi::Mod::OVERLOAD_THRESH\);\s*if \(burden_\[element\] > thresh\)', 'the overload threshold')
    offset = find(server, entity, r'GetRandomNumber\(100\) < \(burden_\[element\] - thresh \+ (\d+)\)', 'the overload chance')
    find(server, entity, r'burden -= std::clamp<uint8>\(1 \+ PMaster->getMod\(xi::Mod::BURDEN_DECAY\) \+ this->getMod\(xi::Mod::BURDEN_DECAY\)', 'the burden\'s fall')
    find(server, 'src/map/status_effect_container.cpp', r'PAutomaton->burdenTick\(\)', 'the fall on the master\'s regen pass')
    cooldown = find(server, 'scripts/globals/job_utils/puppetmaster.lua', r'onAbilityUseCooldown = function.*?player:reduceBurden\((\d+)', 'what Cooldown takes off', re.S)
    passes = find(server, 'src/map/zone_entities.cpp', r'm_EffectCheckTime\s*=\s*m_EffectCheckTime\s*\+\s*(\d+)s', 'the effect pass')
    return {'Spawn': int(spawn.group(1)), 'DarkSmallFrames': int(dark.group(1)), 'Dark': int(dark.group(2)),
            'StatLeast': int(stat.group(2)), 'StatEven': int(stat.group(3)), 'StatMost': int(stat.group(4)), 'StatAhead': int(stat.group(1)),
            'OverloadPast': int(thresh.group(1)), 'ChanceOffset': int(offset.group(1)),
            'FallPerPass': 1, 'Pass': int(passes.group(1)), 'CooldownPercent': int(cooldown.group(1))}


def head_tables(text):
    """{ [xi.automaton.head.X] = { key = n, ... } } as { X = { key: n } }."""
    return {head: {k: int(v) for k, v in re.findall(r'(\w+)\s*=\s*(\d+)', body)}
            for head, body in re.findall(r'\[xi\.automaton\.head\.(\w+)\s*\]\s*=\s*\{([^{}]*)\}', text)}


def automaton(server):
    import sqlite3
    from build_item_data import enabled_files, replay
    enum = read(server, 'scripts/enum/automaton.lua')
    heads = {k: int(v, 0) for k, v in re.findall(r'(\w+)\s*=\s*(0x[0-9A-Fa-f]+|\d+)', find(server, 'scripts/enum/automaton.lua', r'xi\.automaton\.head\s*=\s*\{([^}]*)\}', 'the heads').group(1))}
    frames = {k: int(v, 0) for k, v in re.findall(r'(\w+)\s*=\s*(0x[0-9A-Fa-f]+|\d+)', find(server, 'scripts/enum/automaton.lua', r'xi\.automaton\.frame\s*=\s*\{([^}]*)\}', 'the frames').group(1))}

    # the tables as live has them: the server's SQL and the module SQL over it
    db = sqlite3.connect(':memory:')
    tables = ('automaton_spells', 'mob_skill_lists', 'mob_skills', 'pet_list')
    variables = {}
    for table in tables:
        replay(db, Path(server) / f'sql/{table}.sql', variables, tables=tables)
    pool_changes = []
    for path in enabled_files(server, '.sql'):
        replay(db, path, variables, True, tables=tables)
        pool_changes += [(path, statement) for statement in re.findall(r'[^;]*\bmob_pools\b[^;]*;', path.read_text(encoding='utf-8-sig'))]
    spells = {sid: {'Skill': skill, 'Heads': heads_mask, 'Enfeeble': enfeeble}
              for sid, skill, heads_mask, enfeeble in db.execute('SELECT spellid, skilllevel, heads, enfeeble FROM automaton_spells')}

    # each frame's pet, its pool's skill list (mob_pools: two columns by name), the skills on it
    petids = find(server, 'src/map/utils/petutils.h', r'PETID_HARLEQUINFRAME\s*=\s*(\d+)', 'the first frame\'s pet')
    pools_text = (Path(server) / 'sql/mob_pools.sql').read_text(encoding='utf-8-sig')
    columns = re.findall(r'^\s*`(\w+)`', pools_text[pools_text.index('CREATE TABLE'):pools_text.index(') ENGINE')], re.M)
    pool_skill_list = {}
    for row in re.finditer(r'^INSERT INTO `mob_pools` VALUES \((.*)\);', pools_text, re.M):
        values = [v.strip() for v in re.findall(r"'(?:[^'\\]|\\.)*'|[^,]+", row.group(1))]
        pool_skill_list[int(values[columns.index('poolid')])] = int(values[columns.index('skill_list_id')])
    # module SQL over mob_pools is not replayed here: it must leave the frames' pools alone
    frame_pools = {db.execute('SELECT poolid FROM pet_list WHERE petid = ?', (int(petids.group(1)) + offset,)).fetchone()[0] for offset in range(4)}
    for path, statement in pool_changes:
        if any(re.search(r'\b' + str(pool) + r'\b', statement) for pool in frame_pools) or 'Frame' in statement:
            sys.exit(f'{path}: module SQL changes an automaton frame\'s mob_pools row, which is read here as the server\'s file has it')
    weaponskills = {}
    for name in ('HARLEQUIN', 'VALOREDGE', 'SHARPSHOT', 'STORMWAKER'):
        petid = int(petids.group(1)) + frames[name] - frames['HARLEQUIN']
        pool = db.execute('SELECT poolid FROM pet_list WHERE petid = ?', (petid,)).fetchone()
        if pool is None or pool[0] not in pool_skill_list:
            sys.exit(f'no skill list for the {name} frame\'s pet {petid}')
        skills = []
        for skill_id, skill_name, param in db.execute(
                'SELECT s.mob_skill_id, s.mob_skill_name, s.mob_skill_param FROM mob_skill_lists l JOIN mob_skills s ON s.mob_skill_id = l.mob_skill_id '
                'WHERE l.skill_list_id = ? ORDER BY s.mob_skill_id', (pool_skill_list[pool[0]],)):
            script = Path(server) / f'scripts/actions/abilities/pets/automaton/{skill_name}.lua'
            text = modules.blank_comments(script.read_text()) if script.is_file() else ''
            check = re.search(r'onAutomatonAbilityCheck\s*=\s*', text)
            element = re.search(r'xi\.effect\.(\w+)_MANEUVER', modules.function_body(text, check.end())) if check else None
            if element is None:
                sys.exit(f'{script}: the maneuver its check counts is not as it was')
            skills.append({'Id': skill_id, 'Name': skill_name.replace('_', ' ').title(), 'Skill': param,
                           'Element': element.group(1).lower(), 'Usable': param != 999 and param != -1})
        weaponskills[frames[name]] = skills

    # each head's magic timers: the module's onServerStart on live that puts its own in place, or the server's
    cooldowns = head_tables(find(server, 'scripts/globals/pets/automaton.lua', r'xi\.pets\.automaton\.magicCooldowns\s*=\s*\{(.*?)\n\}', 'magicCooldowns', re.S).group(1))
    source = 'scripts/globals/pets/automaton.lua'
    for override in modules.overrides(server):
        if override.applies and override.target == 'xi.server.onServerStart':
            text = override.text
            for name in re.findall(r'xi\.pets\.automaton\.magicCooldowns\[\w+\]\s*=\s*\w+', text):
                pass
            assigner = re.search(r'local function (\w+)\(\)\s*for head, cooldowns in pairs\((\w+)\) do\s*xi\.pets\.automaton\.magicCooldowns\[head\] = cooldowns', text)
            if assigner and any(re.search(r'\b' + assigner.group(1) + r'\(\)', body) for _, body in override.cases()):
                table = re.search(r'local\s+' + assigner.group(2) + r'\s*=\s*\{(.*?)\n\}', text, re.S)
                cooldowns.update(head_tables(table.group(1)))
                source = override.path
            elif 'magicCooldowns' in text and 'magicCooldowns' in override.body:
                sys.exit(f'{override.path}: changes the automaton\'s magic timers in a way not read here')
    kinds = {'global': 'magic', 'healing': 'heal', 'enfeebling': 'enfeeble', 'elemental': 'elemental',
             'enhancing': 'enhance', 'statusRemoval': 'status'}
    timers = {heads[head]: {kinds.get(k, k): v for k, v in values.items()} for head, values in cooldowns.items()}
    return {'Spells': spells, 'WeaponSkills': weaponskills, 'MagicTimers': timers, 'MagicTimersSource': source,
            'Heads': {v: k.title() for k, v in heads.items()}, 'Frames': {v: k.title() for k, v in frames.items()}}


def weaponskill_tp(server):
    path = 'scripts/globals/weaponskills.lua'
    def handle(override):
        return None if re.search(r'extraHitsLanded|takeWeaponskillDamage', override.body) else 'nothing of TP'
    modules.guard(server, ('xi.weaponskills.',), handle, out=io.StringIO())
    extra = find(server, path, r'local extraHitsTP\s*=\s*\(wsResults\.extraHitsLanded \* (\d+) \* storeTPModifier\) \+ wsResults\.bonusTP', 'the extra hits\' TP')
    find(server, path, r'local storeTPModifier\s*=\s*1 \+ \(attacker:getMod\(xi\.mod\.STORETP\) \+ attacker:getMerit\(xi\.merit\.STORE_TP_EFFECT\)\) / 100', 'Store TP on them')
    return {'ExtraHitTp': int(extra.group(1)), 'StoreTpScalesExtra': True, 'Source': path}


def era(server):
    from phoenix import source
    return {'Server': source.NAME, 'Expansions': list(modules.EXPANSIONS), 'LatestEnabled': modules.LATEST_ENABLED,
            'Inferred': True}


def corsair_rolls(server):
    path = 'scripts/globals/job_utils/corsair.lua'
    abilities = {k: int(v) for k, v in re.findall(r'^\s*(\w+)\s*=\s*(\d+),', read(server, 'scripts/enum/job_ability.lua'), re.M)}
    text = read(server, path)
    block = find(server, path, r'xi\.job_utils\.corsair\.rollData\s*=\s*\{(.*?)\n\}', 'rollData', re.S).group(1)
    powers = {}
    for name, body in re.findall(r'\[xi\.jobAbility\.(\w+)\]\s*=\s*\{(.*?)\n    \}', block, re.S):
        m = re.search(r'powers\s*=\s*\{([^}]*)\}', body)
        if m:
            powers[name] = [int(v) for v in m.group(1).split(',')]
    if len(powers) < 20:
        sys.exit(f'{path}: rollData has only {len(powers)} rolls with powers: read it again')
    # a module on live that sets rolls' powers in onServerStart: each case that applies, the oldest era
    # last (it wraps the rest, calling super first)
    for override in modules.overrides(server):
        if not (override.applies and override.target == 'xi.server.onServerStart' and 'corsair.rollData' in override.body):
            continue
        cases = override.cases()
        cases.sort(key=lambda case: -modules.EXPANSIONS.index(case[0]) if case[0] else 0)
        for era, body in cases:
            table = re.search(r'for abilityId, data in pairs\((\w+)\) do\s*local rollInfo\s*=\s*\w+\[abilityId\]\s*rollInfo\.powers\s*=\s*data\.powers', body)
            if table is None:
                if 'rollData' in body:
                    sys.exit(f'{override.path}: changes rollData in a way not read here')
                continue
            data = re.search(r'local\s+' + table.group(1) + r'\s*=\s*\{(.*?)\n\}', override.text, re.S).group(1)
            for name, values in re.findall(r'\[xi\.jobAbility\.(\w+)\]\s*=\s*\{\s*powers\s*=\s*\{([^}]*)\}', data):
                powers[name] = [int(v) for v in values.split(',')]
    rolls = {}
    for name, values in powers.items():
        if name not in abilities:
            sys.exit(f'{path}: xi.jobAbility.{name} is not in the enum')
        first = values[:10]
        if all(v <= 0 for v in first):
            first = [-v for v in first]  # a roll that takes away (Blitzer's): its best is its least
        best, worst = max(first), min(first)
        if first.count(best) == 1 and first.count(worst) == 1 and first.index(best) < 9:
            lucky, unlucky, how = first.index(best) + 1, first.index(worst) + 1, 'powers'
        else:
            # the powers do not say (one that only rises, or two alike at the top): the roll's own script
            script = Path(server) / f'scripts/actions/abilities/{name.lower()}.lua'
            header = script.read_text() if script.is_file() else ''  # its header comment says them
            said = re.search(r'Lucky Number:\s*(\d+)', header)
            unsaid = re.search(r'Unlucky Number:\s*(\d+)', header)
            if not said or not unsaid:
                sys.exit(f'{name}: its powers do not say its lucky number, nor does its script')
            lucky, unlucky, how = int(said.group(1)), int(unsaid.group(1)), 'script'
        rolls[abilities[name]] = {'Name': name.replace('_', ' ').title(), 'Lucky': lucky, 'Unlucky': unlucky, 'From': how}
    return rolls


def merits(server):
    untouched(server, 'MAX_LIMIT_POINTS')
    m = find(server, 'src/map/merit.cpp', r'#define MAX_LIMIT_POINTS (\d+)', 'MAX_LIMIT_POINTS')
    return {'LimitPointsPerMerit': int(m.group(1)), 'Source': 'src/map/merit.cpp'}


def prevent_action(server):
    untouched(server, 'HasPreventActionEffect')
    path = 'src/map/status_effect_container.cpp'
    m = find(server, path, r'bool CStatusEffectContainer::HasPreventActionEffect\(bool ignoreCharm\)\s*\{\s*if \(ignoreCharm\)\s*\{\s*return HasStatusEffect\(\s*\{([^}]*)\}',
             'the statuses that prevent acting')
    find(server, 'src/map/ai/ai_container.cpp', r'HasPreventActionEffect\(true\)', 'the AI asking it with charm aside')
    def squash(text):
        return re.sub(r'[^a-z0-9]', '', text.lower())
    numbers = {squash(key): entry['id'] for key, entry in modules.load_yaml(server, 'status_effects')['status_effects'].items()
               if isinstance(entry, dict) and 'id' in entry}
    statuses = []
    for name in re.findall(r'xi::StatusEffect::(\w+)', m.group(1)):
        if squash(name) not in numbers:
            sys.exit(f'{path}: StatusEffect::{name} is not in data/status_effects.yaml')
        statuses.append(numbers[squash(name)])
    return {'Statuses': statuses, 'Source': path}


def skillchain(server):
    untouched(server, 'StatusEffect::Skillchain', 'FormSkillchain')
    path = 'src/map/utils/battleutils.cpp'
    opens = find(server, path, r'PSCEffect && PSCEffect->GetStartTime\(\) \+ (\d+)s < timer::now\(\)', 'when the window opens')
    lasts = find(server, path, r'AddStatusEffect\(xi::StatusEffect::Skillchain, 0, combined_properties, 0s, (\d+)s', 'how long the resonance lasts')
    shorter = find(server, path, r'if \(skillchain != SC_NONE\)\s*\{\s*PSCEffect->SetStartTime\(timer::now\(\)\);\s*PSCEffect->SetDuration\(PSCEffect->GetDuration\(\) - (\d+)s\);',
                   'each step of a chain shortening it')
    # what a closing property on an opening one makes: skillchain_map, { closing, opening } -> made
    table = find(server, path, r'skillchain_map = \{(.*?)\n\};', 'skillchain_map', re.S).group(1)
    find(server, path, r'skillchain_map\.find\(\{ skill_element, resonance_element \}\)', 'the map asked closing first')
    pairs = [{'Close': close, 'Open': opening, 'Makes': made} for close, opening, made in
             re.findall(r'\{\s*\{\s*SC_(\w+),\s*SC_(\w+)\s*\},\s*SC_(\w+)\s*\}', table)]
    if len(pairs) < 20:
        sys.exit(f'{path}: skillchain_map has only {len(pairs)} pairs: read it again')
    return {'OpenAfter': int(opens.group(1)), 'Lasts': int(lasts.group(1)), 'ShorterPerStep': int(shorter.group(1)),
            'Pairs': pairs, 'Source': path}


def magic_cost(server):
    def handle(override):
        return None if re.search(r'MAGIC_COST', override.body) else 'nothing of MP costs'
    modules.guard(server, ('xi.effects.light_arts', 'xi.effects.dark_arts', 'xi.effects.addendum_'), handle, out=io.StringIO())
    untouched(server, 'CalculateSpellCost', 'HasNinjaTool', 'BLACK_MAGIC_COST', 'WHITE_MAGIC_COST')
    def squash(text):
        return re.sub(r'[^a-z0-9]', '', text.lower())
    statuses = {squash(key): entry['id'] for key, entry in modules.load_yaml(server, 'status_effects')['status_effects'].items()
                if isinstance(entry, dict) and 'id' in entry}
    arts = {}
    for effect in ('light_arts', 'dark_arts', 'addendum_white', 'addendum_black'):
        text = read(server, f'scripts/effects/{effect}.lua')
        gain = modules.function_body(text, find(server, f'scripts/effects/{effect}.lua', r'onEffectGain\s*=\s*', 'onEffectGain').end())
        fixed = {kind: int(value) for kind, value in re.findall(r'addMod\(xi\.mod\.(WHITE|BLACK)_MAGIC_COST,\s*(-?\d+)\)', gain)}
        if set(fixed) != {'WHITE', 'BLACK'}:
            sys.exit(f'scripts/effects/{effect}.lua: its white and black magic cost are not as they were')
        arts[statuses[squash(effect)]] = {'White': fixed['WHITE'], 'Black': fixed['BLACK']}
    path = 'src/map/utils/battleutils.cpp'
    for halved in ('Parsimony', 'Penury'):
        find(server, path, r'HasStatusEffect\(xi::StatusEffect::' + halved + r'\)\)\s*\{\s*cost /= 2;', f'{halved} halving the cost')
    find(server, path, r'cost \+= \(int16\)\(base \* \(PEntity->getMod\(xi::Mod::BLACK_MAGIC_COST\) / 100\.0f\)\);', 'the black magic cost mod')
    find(server, 'src/map/ai/states/magic_state.cpp', r'!m_PEntity->StatusEffectContainer->HasStatusEffect\(xi::StatusEffect::Manafont\)', 'Manafont')
    items = {k: int(v) for k, v in re.findall(r'^\s*(\w+)\s*=\s*(\d+),', read(server, 'src/map/items.h'), re.M)}
    switch = find(server, path, r'bool HasNinjaTool\(.*?switch \(toolID\)\s*\{(.*?)default:', 'the universal tools', re.S).group(1)
    universal, cases = {}, []
    for token in re.finditer(r'case ITEMID::(\w+):|toolID = ITEMID::(\w+);', switch):
        if token.group(1):
            cases.append(items[token.group(1)])
        else:
            for tool in cases:
                universal[tool] = items[token.group(2)]
            cases = []
    return {'Arts': arts, 'HalvedWhite': statuses['penury'], 'HalvedBlack': statuses['parsimony'],
            'Free': [statuses['manafont']], 'UniversalTools': universal, 'Source': path}


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
        'burden': burden(server),
        'automaton': automaton(server),
        'weaponskillTp': weaponskill_tp(server),
        'era': era(server),
        'corsairRolls': corsair_rolls(server),
        'merits': merits(server),
        'preventAction': prevent_action(server),
        'skillchain': skillchain(server),
        'magicCost': magic_cost(server),
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
