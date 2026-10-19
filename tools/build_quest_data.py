#!/usr/bin/env python3
"""Static Phoenix quest index. Never executes server Lua or invents quest eligibility.

Quest identity is (log ID, quest ID). Hidden interactions are path-keyed separately.
Facts, declared reward tables and conditional/source-reference evidence remain distinct.
Called by build_winxi_data.py --only quests.
"""
import bisect
import hashlib
import json
import re
import shutil
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import yaml
from build_item_data import enabled_files, lua
from build_action_data import provenance


@dataclass
class Token:
    value: str
    start: int
    end: int
    line: int
    string: bool = False


def tokens(text):
    # Match comments/strings before punctuation. Long-bracket strings are opaque too.
    pattern = re.compile(r"--\[(=*)\[[\s\S]*?\]\1\]|--[^\n]*|\[(=*)\[[\s\S]*?\]\2\]|'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"|[A-Za-z_][\w]*|0[xX][\da-fA-F]+|\d+(?:\.\d+)?|\.\.\.|==|~=|>=|<=|\.\.|\S")
    result, line, previous = [], 1, 0
    for match in pattern.finditer(text):
        line += text[previous:match.start()].count('\n')
        previous = match.start()
        value = match[0]
        if value.startswith('--'):
            continue
        result.append(Token(value, match.start(), match.end(), line,
                            value.startswith(('"', "'")) or bool(re.match(r'^\[=*\[', value))))
    return result


def string(token):
    value = token.value
    if value.startswith(('"', "'")):
        # Static strings needed here are names/paths. Preserve unknown escapes literally.
        return re.sub(r"\\([\\'\"])", r'\1', value[1:-1])
    opening = re.match(r'^\[(=*)\[', value)
    return value[opening.end():-(len(opening[1]) + 2)]


def pairs(ts):
    stack, found = [], {}
    closing = {')': '(', ']': '[', '}': '{'}
    for i, token in enumerate(ts):
        if token.string:
            continue
        if token.value in ('(', '[', '{'):
            stack.append((i, token.value))
        elif token.value in closing:
            if not stack or stack[-1][1] != closing[token.value]:
                raise ValueError(f'Unbalanced Lua delimiter on line {token.line}')
            start, _ = stack.pop()
            found[start] = i
    if stack:
        raise ValueError('Unclosed Lua delimiter')
    return found


def code(ts):
    return ''.join(t.value for t in ts)


def fields(ts):
    """Split a table's top-level fields, never commas inside nested expressions."""
    matched, start, i = pairs(ts), 0, 0
    while i < len(ts):
        if i in matched:
            i = matched[i] + 1
            continue
        if ts[i].value in (',', ';'):
            if i > start:
                yield ts[start:i]
            start = i + 1
        i += 1
    if start < len(ts):
        yield ts[start:]


def static_value(ts, constants):
    """Resolve only literals, enum symbols and nested literal tables; never evaluate code."""
    raw = code(ts)
    if len(ts) == 1:
        token = ts[0]
        if token.string:
            return string(token), True
        if raw in ('true', 'false'):
            return raw == 'true', True
        if raw == 'nil':
            return None, True
        if re.fullmatch(r'0[xX][\da-fA-F]+|\d+(?:\.\d+)?', raw):
            return (float(raw) if '.' in raw else int(raw, 0) if raw.lower().startswith('0x') else int(raw)), True
    if len(ts) == 2 and ts[0].value == '-':
        value, ok = static_value(ts[1:], constants)
        if ok and type(value) in (int, float):
            return -value, True
    if raw in constants:
        return constants[raw], True
    if ts and ts[0].value == '{' and pairs(ts).get(0) == len(ts) - 1:
        # Function/statement bodies can contain top-level commas that are NOT table
        # separators. Withhold the whole table rather than manufacture sibling fields.
        if any(not t.string and t.value in ('function', 'if', 'for', 'while', 'repeat', 'do', 'end', 'until') for t in ts[1:-1]):
            return {'Expression': raw, 'Unresolved': True}, False
        result, complete, position = {}, True, 1
        for field in fields(ts[1:-1]):
            if len(field) > 2 and field[1].value == '=' and not field[0].string:
                key, value_tokens = field[0].value, field[2:]
            elif field[0].value == '[' and (end := pairs(field).get(0)) is not None and end + 1 < len(field) and field[end + 1].value == '=':
                key, known = static_value(field[1:end], constants)
                if not known or not isinstance(key, (str, int)) or isinstance(key, bool):
                    return {'Expression': raw, 'Unresolved': True}, False
                value_tokens = field[end + 2:]
            else:
                key, value_tokens = position, field
                position += 1
            value, known = static_value(value_tokens, constants)
            if key in result:
                return {'Expression': raw, 'Unresolved': True}, False
            result[key] = value
            complete = complete and known
        return result, complete
    return {'Expression': raw, 'Unresolved': True}, False


def read_enums(server):
    constants = {}
    for name, namespace in (('zone', 'xi.zone'), ('key_item', 'xi.keyItem'), ('fame_area', 'xi.fameArea'), ('job', 'xi.job')):
        values = yaml.safe_load((server / f'data/enums/{name}.yaml').read_text())['values']
        constants.update({namespace + '.' + symbol.upper(): value for symbol, value in values.items()})
    for filename, namespace in (('item', 'xi.item'), ('title', 'xi.title'), ('quest_log', 'xi.questLog'), ('quest_status', 'xi.questStatus')):
        text = (server / f'scripts/enum/{filename}.lua').read_text()
        ts = tokens(text)
        for i in range(len(ts) - 2):
            if ts[i + 1].value == '=' and re.fullmatch(r'[A-Z][A-Z_\d]*', ts[i].value):
                end = i + 4 if ts[i + 2].value == '-' else i + 3
                value, known = static_value(ts[i + 2:end], {})
                if known and type(value) is int:
                    constants[namespace + '.' + ts[i].value] = value
    return constants


def quest_enum(text, constants):
    ts = tokens(text)
    matched = pairs(ts)
    areas, records, by_symbol = {}, {}, {}
    for i in range(len(ts) - 5):
        if code(ts[i:i + 5]) == 'xi.quest.area' and ts[i + 5].value == '=':
            start = i + 6
            for field in fields(ts[start + 1:matched[start]]):
                end = pairs(field).get(0)
                if end is None or len(field) != end + 3 or not field[-1].string:
                    raise ValueError('Unsupported quest-area declaration')
                log, known = static_value(field[1:end], constants)
                if not known or type(log) is not int:
                    raise ValueError('Unknown quest log')
                areas[string(field[-1])] = log
            break
    for i in range(len(ts) - 5):
        if code(ts[i:i + 5]) == 'xi.quest.id' and ts[i + 5].value == '=':
            start = i + 6
            for field in fields(ts[start + 1:matched[start]]):
                end = pairs(field).get(0)
                if end is None or field[end + 1].value != '=':
                    raise ValueError('Unsupported quest ID group')
                # xi.quest.area[xi.questLog.NAME] -> log enum value
                group = code(field[1:end])
                match = re.fullmatch(r'xi\.quest\.area\[(xi\.questLog\.\w+)\]', group)
                if not match or match[1] not in constants:
                    raise ValueError('Unknown quest ID group: ' + group)
                log = constants[match[1]]
                area = next(name for name, value in areas.items() if value == log)
                for entry in fields(field[end + 3:-1]):
                    if len(entry) != 3 or entry[1].value != '=':
                        raise ValueError('Unsupported quest ID declaration: ' + code(entry))
                    ident, known = static_value(entry[2:], constants)
                    if not known or type(ident) is not int or not 0 <= ident < 65536:
                        raise ValueError('Invalid quest ID')
                    symbol = entry[0].value
                    key = f'{log}:{ident}'
                    record = records.setdefault(key, {'Key': key, 'Log': log, 'Id': ident, 'Area': area, 'Kind': 'quest', 'Name': symbol.replace('_', ' ').title(), 'NameSource': 'enum-symbol', 'Symbols': []})
                    record['Symbols'].append(symbol)
                    path = f'xi.quest.id.{area}.{symbol}'
                    if path in by_symbol:
                        raise ValueError('Duplicate quest symbol: ' + path)
                    by_symbol[path] = record
                    constants[path] = ident
            break
    if not areas or not records:
        raise ValueError('No quest enum entries; source layout may have changed')
    return areas, records, by_symbol


def function_end(ts, start):
    """Match a function's end without evaluating conditions or loop bodies."""
    stack = []
    for i in range(start, len(ts)):
        if ts[i].string:
            continue
        word = ts[i].value
        if word in ('function', 'if', 'for', 'while', 'repeat'):
            stack.append([word, word in ('for', 'while')])
        elif word == 'do':
            if stack and stack[-1][1]:
                stack[-1][1] = False
            else:
                stack.append(['do', False])
        elif word in ('end', 'until'):
            if not stack or (word == 'until') != (stack[-1][0] == 'repeat'):
                raise ValueError('Unsupported Lua block structure')
            stack.pop()
            if not stack:
                return i
    raise ValueError('Unclosed Lua function')


def source_name(text, fallback):
    for line in text.splitlines()[:12]:
        match = re.fullmatch(r'\s*--\s+([^\s-].*)', line)
        if match and not re.match(r'(?:Log ID|!|NPC:|Source:|Note:)', match[1], re.I):
            return match[1].strip(), 'source-header'
    return fallback.replace('_', ' '), 'source-filename'


def write_data(path, value):
    path.write_text('-- Generated by tools/build_quest_data.py; references are not eligibility or a walkthrough.\nreturn ' + lua(value) + ';\n', encoding='utf-8')


def build(server, output, settings=()):
    server, output = Path(server), Path(output)
    constants = read_enums(server)
    areas, records, symbols = quest_enum((server / 'scripts/globals/quests.lua').read_text(), constants)
    scripts, owners, hidden = {}, defaultdict(list), {}
    unresolved, unowned, todos, module_paths = [], [], [], []

    def read(path):
        text = path.read_text(encoding='utf-8-sig')
        ts = tokens(text)
        try:
            matched = pairs(ts)
        except ValueError as error:
            raise ValueError(f'{path}: {error}') from error
        return text, ts, matched

    def evidence(path, text=None):
        key = str(path.relative_to(server))
        if key not in scripts:
            text = text if text is not None else path.read_text(encoding='utf-8-sig')
            scripts[key] = {'Path': key, 'SHA256': hashlib.sha256(text.encode()).hexdigest(), 'Text': text}
        return key

    def add_source(record, path, field='Sources'):
        sources = record.setdefault(field, [])
        if path not in sources:
            sources.append(path)

    def reference(record, path, line, kind):
        value = {'Source': path, 'Line': line, 'Kind': kind}
        if value not in record.setdefault('References', []):
            record['References'].append(value)

    def zone_ref(record, ident, symbol, path, line):
        ref = {'Id': ident, 'Symbol': symbol, 'Source': path, 'Line': line}
        if ref not in record.setdefault('Zones', []):
            record['Zones'].append(ref)

    def inspect(record, path, text, ts, matched, declared=False):
        # All zone mentions are references. Only structural zone/NPC table keys are paired.
        for i in range(len(ts) - 4):
            name = code(ts[i:i + 5])
            if name.startswith('xi.zone.') and name in constants:
                zone_ref(record, constants[name], ts[i + 4].value, path, ts[i].line)
            if ts[i].value == '[' and i in matched:
                end = matched[i]
                symbol = code(ts[i + 1:end])
                if symbol.startswith('xi.zone.') and symbol in constants and end + 2 < len(ts) and code(ts[end + 1:end + 3]) == '={':
                    start, stop = end + 2, matched[end + 2]
                    j = start + 1
                    while j < stop:
                        if ts[j].value == '[' and j in matched:
                            close = matched[j]
                            if close == j + 2 and ts[j + 1].string and close + 1 < stop and ts[close + 1].value == '=':
                                npc = {'Name': string(ts[j + 1]), 'Zone': constants[symbol], 'ZoneSymbol': symbol.rsplit('.', 1)[1], 'Source': path, 'Line': ts[j].line}
                                if npc not in record.setdefault('NPCs', []):
                                    record['NPCs'].append(npc)
                        if j in matched:
                            j = matched[j] + 1
                        else:
                            j += 1
        if declared:
            # Only direct quest.reward = { ... } declarations are parsed; modifications,
            # functions and calculated fields retain unresolved expression evidence.
            for i in range(len(ts) - 4):
                if code(ts[i:i + 4]) == 'quest.reward=' and ts[i + 4].value == '{':
                    start, end = i + 4, matched[i + 4]
                    value, complete = static_value(ts[start:end + 1], constants)
                    record.setdefault('RewardDeclarations', []).append({'Source': path, 'Line': ts[i].line, 'Fields': value, 'Complete': complete, 'Scope': 'base-script declaration; not effective reward', 'Raw': text[ts[start].start:ts[end].end]})
        # Conditional references are not advertised as prerequisites or guaranteed rewards.
        lines = text.splitlines()
        seen = set()
        patterns = {
            'condition-reference': r':(?:hasCompletedQuest|getQuestStatus|getMainLvl|getMainJob|getFameLevel|getFame|getCurrentMission|getMissionStatus|hasKeyItem|hasItem)\(',
            'reward-call': r'(?:npcUtil\.(?:giveItem|giveKeyItem|completeQuest)|:(?:addGil|addExp|addTitle|unlockJob|addFame|addKeyItem|addItem))\(',
            'time-reference': r'\b(?:JstMidnight|VanadielUniqueDay|GetSystemTime|mustZone|Timer|NEXT_REAL_DAY)\b',
            'state-reference': r':(?:getCharVar|setCharVar|getVar|setVar)\(',
            'setting-reference': r'xi\.settings\.\w+\.\w+',
        }
        offsets, length, chunks = [], 0, []
        for token in ts:
            offsets.append(length)
            chunks.append(' ' * len(token.value) if token.string else token.value)
            length += len(token.value)
        joined = ''.join(chunks)
        for kind, pattern in patterns.items():
            for match in re.finditer(pattern, joined):
                line = ts[bisect.bisect_right(offsets, match.start()) - 1].line
                marker = (kind, line)
                if marker not in seen:
                    seen.add(marker)
                    record.setdefault('Evidence', []).append({'Kind': kind, 'Source': path, 'Line': line, 'Text': lines[line - 1].strip()})

    # First assign only literal framework constructors as owners.
    for path in sorted((server / 'scripts/quests').rglob('*')):
        if path.name.endswith('.todo'):
            todos.append(str(path.relative_to(server)))
        if path.suffix != '.lua':
            continue
        text, ts, matched = read(path)
        source_path = str(path.relative_to(server))
        for i in range(len(ts) - 4):
            if code(ts[i:i + 4]) == 'Quest:new(':
                end = matched[i + 3]
                args = list(fields(ts[i + 4:end]))
                if len(args) != 2:
                    unresolved.append({'Source': source_path, 'Line': ts[i].line, 'Expression': code(ts[i:end + 1])})
                    continue
                log, known = static_value(args[0], constants)
                ident, id_known = static_value(args[1], constants)
                record = records.get(f'{log}:{ident}') if known and id_known else None
                if record is None:
                    unresolved.append({'Source': source_path, 'Line': ts[i].line, 'Expression': code(ts[i:end + 1])})
                    continue
                # Guard against a mismatched quest log/ID symbol accidentally aliasing another quest.
                symbolic = symbols.get(code(args[1]))
                if symbolic is not None and symbolic is not record:
                    raise ValueError(f'{path}: quest constructor log/ID mismatch')
                owners[source_path].append(record)
            elif code(ts[i:i + 4]) == 'HiddenQuest:new(':
                end = matched[i + 3]
                name, known = static_value(ts[i + 4:end], constants)
                if not known or not isinstance(name, str):
                    unresolved.append({'Source': source_path, 'Line': ts[i].line, 'Expression': code(ts[i:end + 1])})
                    continue
                key = 'hidden:' + source_path.removesuffix('.lua')
                record = hidden.setdefault(key, {'Key': key, 'Kind': 'hidden', 'HiddenId': name, 'Name': path.stem.replace('_', ' '), 'NameSource': 'source-filename'})
                owners[source_path].append(record)
        if not owners[source_path]:
            unowned.append(source_path)
            evidence(path, text)
        if owners[source_path]:
            evidence(path, text)
            for record in owners[source_path]:
                add_source(record, source_path)
                record['Name'], record['NameSource'] = source_name(text, path.stem)
                inspect(record, source_path, text, ts, matched, True)

    # Recognize three explicit Jeuno factories without running them. A changed helper
    # constructor/formula stops this association, rather than guessing an identity.
    helper_file = server / 'scripts/quests/jeuno/helpers.lua'
    helper_text, helper_ts, _ = read(helper_file)
    methods = {}
    for i in range(len(helper_ts) - 10):
        if helper_ts[i].value == 'function' and code(helper_ts[i + 1:i + 6]) == 'xi.jeuno.helpers':
            name = helper_ts[i + 7].value if code(helper_ts[i + 6:i + 7]) == '.' else None
            if name in ('GobbiebagQuest', 'BorghertzQuests', 'UnlockingAMyth') and code(helper_ts[i + 8:i + 11]) == ':new(':
                end = function_end(helper_ts, i)
                methods[name] = helper_ts[i:end + 1]
    for source_path in list(unowned):
        path = server / source_path
        text, ts, matched = read(path)
        for i in range(len(ts) - 10):
            if code(ts[i:i + 5]) != 'xi.jeuno.helpers' or code(ts[i + 7:i + 10]) != ':new(':
                continue
            factory = ts[i + 6].value
            method = methods.get(factory)
            if not method:
                continue
            method_code = code(method)
            record, params, complete = None, None, False
            if factory in ('GobbiebagQuest', 'BorghertzQuests') and 'Quest:new(xi.questLog.JEUNO,params.questId)' in method_code:
                if code(ts[i + 10:matched[i + 9]]) != 'params':
                    continue
                for j in range(len(ts) - 3):
                    if code(ts[j:j + 3]) == 'params={':
                        params, complete = static_value(ts[j + 2:matched[j + 2] + 1], constants)
                        ident = params.get('questId') if isinstance(params, dict) else None
                        if type(ident) is int:
                            record = records.get(f'{areas["jeuno"]}:{ident}')
                        break
            elif factory == 'UnlockingAMyth' and 'xi.quest.id.jeuno.UNLOCKING_A_MYTH_WARRIOR-1+jobId' in method_code:
                job, known = static_value(ts[i + 10:matched[i + 9]], constants)
                if known and type(job) is int:
                    ident = constants['xi.quest.id.jeuno.UNLOCKING_A_MYTH_WARRIOR'] - 1 + job
                    record = records.get(f'{areas["jeuno"]}:{ident}')
                    params, complete = {'jobId': job}, True
            if record is None:
                continue
            owners[source_path].append(record)
            unowned.remove(source_path)
            evidence(path, text)
            helper_path = evidence(helper_file, helper_text)
            add_source(record, source_path)
            add_source(record, helper_path, 'HelperSources')
            record['Factory'] = {'Name': factory, 'Arguments': params, 'Complete': complete, 'Source': source_path, 'Line': ts[i].line, 'Helper': helper_path, 'HelperLine': method[0].line, 'HelperEndLine': method[-1].line}
            record['Name'], record['NameSource'] = source_name(text, path.stem)
            inspect(record, source_path, text, ts, matched, True)
            inspect(record, helper_path, helper_text, method, pairs(method))
            if factory == 'GobbiebagQuest' and isinstance(params.get('reward'), dict) and 'quest.reward=params.reward' in method_code:
                record.setdefault('RewardDeclarations', []).append({'Source': source_path, 'Line': ts[i].line, 'Fields': params['reward'], 'Complete': not any(isinstance(v, dict) and v.get('Unresolved') for v in params['reward'].values()), 'Scope': 'base factory parameter declaration; not effective reward'})
            break

    all_records = {**records, **hidden}
    # Legacy NPC scripts and helper modules can reference several quests: association only.
    scan = sorted((server / 'scripts/zones').glob('*/npcs/*.lua'))
    scan += sorted((server / 'scripts/quests').rglob('*.lua'))
    scan += enabled_files(server, '.lua')
    enabled = set(enabled_files(server, '.lua'))
    for path in dict.fromkeys(scan):
        text, ts, matched = read(path)
        source_path = str(path.relative_to(server))
        referenced = {}
        for i in range(len(ts) - 8):
            target = code(ts[i:i + 9])
            if target.startswith('xi.quest.id.') and re.fullmatch(r'xi\.quest\.id\.\w+\.\w+', target):
                record = symbols.get(target)
                if record:
                    referenced[record['Key']] = record
                    reference(record, source_path, ts[i].line, 'quest-id-reference')
                else:
                    unresolved.append({'Source': source_path, 'Line': ts[i].line, 'Expression': target})
        # Literal interaction edits/paths (including paths in dynamic loop tables) are evidence.
        for i, token in enumerate(ts):
            if token.string:
                target_path = string(token).removesuffix('.lua')
                if target_path.startswith('scripts/quests/'):
                    for record in owners.get(target_path + '.lua', []):
                        referenced[record['Key']] = record
                        direct = i >= 2 and ts[i - 1].value == '(' and ts[i - 2].value == 'modifyInteractionEntry'
                        reference(record, source_path, token.line, 'interaction-edit-declaration' if direct else 'interaction-path-reference')
        if referenced:
            evidence(path, text)
            if path in enabled:
                module_paths.append(source_path)
            for record in referenced.values():
                add_source(record, source_path, 'RelatedSources')
                if path in enabled:
                    add_source(record, source_path, 'Modules')
                if source_path.startswith('scripts/zones/'):
                    zone_name, npc_name = path.parts[-3], path.stem
                    zone_symbol = 'xi.zone.' + zone_name.upper()
                    if zone_symbol in constants:
                        zone_ref(record, constants[zone_symbol], zone_name.upper(), source_path, 1)
                        npc = {'Name': npc_name, 'Zone': constants[zone_symbol], 'ZoneSymbol': zone_name.upper(), 'Source': source_path, 'Line': 1, 'Association': 'legacy NPC file references quest; not necessarily its starter'}
                        if npc not in record.setdefault('NPCs', []):
                            record['NPCs'].append(npc)
                # Conditions/grants in related files are only file associations; retain text
                # once in evidence pages rather than misattribute every branch to every quest.
        elif path in enabled and ('quests' in path.parts or any('modifyInteractionEntry' == t.value for t in ts)):
            evidence(path, text)
            module_paths.append(source_path)

    # Associate literal NPC overrides with records that reference that zone/NPC. This is
    # deliberately distinct from a direct interaction edit and is never treated as applied.
    npc_index = defaultdict(set)
    for key, record in all_records.items():
        for npc in record.get('NPCs', []):
            npc_index[(npc['ZoneSymbol'].lower(), npc['Name'].lower())].add(key)
    for path in sorted(enabled):
        text, ts, _ = read(path)
        for i, token in enumerate(ts):
            if not token.string or i < 2 or ts[i - 1].value != '(' or ts[i - 2].value not in ('addOverride', 'addOverrideByEra'):
                continue
            target = string(token)
            match = re.fullmatch(r'xi\.zones\.([^.]+)\.npcs\.([^.]+)\.(\w+)', target)
            if match:
                keys = npc_index.get((match[1].lower(), match[2].lower()), ())
                for key in sorted(keys):
                    source_path = evidence(path, text)
                    record = all_records[key]
                    add_source(record, source_path, 'Modules')
                    add_source(record, source_path, 'RelatedSources')
                    reference(record, source_path, token.line, 'NPC-override-association; runtime gate unresolved')
                    module_paths.append(source_path)

    for filename in ('scripts/globals/quests.lua', 'scripts/globals/interaction/quest.lua', 'scripts/globals/interaction/hidden_quest.lua', 'scripts/enum/quest_log.lua'):
        evidence(server / filename)

    # Reward item index is ONLY from literal base declaration item fields. It excludes
    # incidental item mentions, trades and conditional giveItem calls.
    def declared_items(value):
        if type(value) is int:
            return [value]
        if isinstance(value, dict) and not value.get('Unresolved'):
            found = []
            for ident, entry in value.items():
                if type(ident) is int and isinstance(entry, dict) and type(entry.get(1)) is int:
                    found.append(entry[1])
                elif type(ident) is int and type(entry) is int:
                    found.append(entry)
            return found
        return []
    by_zone, by_item, by_log = defaultdict(list), defaultdict(list), defaultdict(list)
    ordered = sorted(records.values(), key=lambda r: (r['Log'], r['Id'])) + [hidden[key] for key in sorted(hidden)]
    for record in ordered:
        key = record['Key']
        record['Coverage'] = 'factory-script' if record.get('Factory') else 'framework-script' if record.get('Sources') else 'reference-only' if record.get('References') else 'enum-only'
        item_ids = set()
        for reward in record.get('RewardDeclarations', []):
            for ident in declared_items(reward['Fields'].get('item') if isinstance(reward['Fields'], dict) else None):
                item_ids.add(ident)
        if item_ids:
            record['DeclaredRewardItems'] = sorted(item_ids)
        for zone in sorted({z['Id'] for z in record.get('Zones', [])}):
            by_zone[zone].append(key)
        for ident in sorted(item_ids):
            by_item[ident].append(key)
        if record['Kind'] == 'quest':
            by_log[record['Log']].append(key)

    output.mkdir(parents=True, exist_ok=True)
    logs = defaultdict(dict)
    for record in records.values():
        logs[record['Log']][record['Id']] = record
    for log, entries in sorted(logs.items()):
        write_data(output / f'{log}.lua', entries)
    write_data(output / 'hidden.lua', hidden)
    script_index, batches = {}, defaultdict(dict)
    for n, (path, entry) in enumerate(sorted(scripts.items())):
        script_index[path] = n // 24
        batches[n // 24][path] = entry
    for page, entries in sorted(batches.items()):
        write_data(output / f'script_{page}.lua', entries)
    metadata = {
        'Schema': 1, 'Count': len(records), 'HiddenCount': len(hidden), 'Keys': [r['Key'] for r in ordered],
        'Symbols': {symbol.removeprefix('xi.quest.id.'): record['Key'] for symbol, record in sorted(symbols.items())},
        'Logs': {log: {'Id': log, 'Area': area, 'Name': area} for area, log in areas.items()},
        'ByLog': dict(by_log), 'ByZone': dict(by_zone), 'ByDeclaredRewardItem': dict(by_item),
        'Scripts': script_index, 'Source': provenance(server), 'Settings': list(settings),
        'Modules': sorted(set(module_paths)),
        'UnassociatedModules': sorted(set(module_paths) - {path for record in all_records.values() for path in record.get('Modules', [])}),
        'Unresolved': unresolved, 'UnownedQuestScripts': sorted(unowned), 'TodoFiles': todos,
        'Coverage': {label: sum(r['Coverage'] == label for r in records.values()) for label in ('framework-script', 'factory-script', 'reference-only', 'enum-only')},
        'Limitations': [
            'Public-source definitions, not private live database state or character progress.',
            'Names are source headers/filenames or humanized enum symbols, not localized client journal text.',
            'NPCs/zones and conditions are source references, not verified starting instructions or prerequisites.',
            'Reward tables are base declarations. Module gates, dynamic edits and runtime reward scaling are not evaluated.',
            'Modules are declarations/reference associations, not a list of confirmed applied edits.',
            'Hidden interactions use path keys and are not numbered quest-log entries.',
            'Presence in the catalog or source does not prove implementation, availability, repeatability or obtainability.',
        ],
    }
    write_data(output / 'index.lua', metadata)
    (output / 'catalog.json').write_text(json.dumps({'Metadata': metadata, 'Quests': list(records.values()), 'Hidden': list(hidden.values())}, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
    shutil.copyfile(server / 'LICENSE', output / 'LICENSE-Phoenix')
    (output / 'NOTICE.txt').write_text('Generated from Phoenix (https://github.com/phoenixffxi/Phoenix).\nEmbedded scripts retain the upstream GPL v3 license; see LICENSE-Phoenix.\nNot relicensed under winxi\'s MIT license. index.lua records revision and script evidence paths/hashes.\n', encoding='utf-8')
    print(f'quests: {len(records)} numbered definitions; {len(hidden)} hidden interactions; {len(scripts)} sources; coverage {metadata["Coverage"]}')
    return metadata
