#!/usr/bin/env python3
"""Build the shared item catalog from Phoenix SQL and enabled module SQL.

No database service or server Lua execution is required. The supported MySQL subset is
replayed in an in-memory SQLite database; unknown item statements fail the build.
Lua behavior is indexed as source evidence, not guessed into unconditional stats.
"""
import hashlib
import json
import re
import shutil
import sqlite3
from collections import defaultdict
from pathlib import Path

import yaml
from phoenix import modules, source

TABLES = {
    'item_basic': 'Basic', 'item_equipment': 'Equipment', 'item_weapon': 'Weapon',
    'item_usable': 'Usable', 'item_furnishing': 'Furnishing', 'item_puppet': 'Puppet',
    'item_mods': 'Mods', 'item_mods_pet': 'PetMods', 'item_latents': 'Latents',
}
MANY = {'Mods', 'PetMods', 'Latents'}
PAGE_SIZE = 256


def statements(text):
    """Split SQL, preserving quoted semicolons, comments and MySQL escaped quotes."""
    token = re.compile(r"'(?:\\.|''|[^'\\])*'|\"(?:\\.|\"\"|[^\"\\])*\"|`[^`]*`|--[^\n]*|\#[^\n]*|/\*[\s\S]*?\*/|;|[^'\"`;#/-]+|.")
    parts = []
    for match in token.finditer(text.lstrip('\ufeff')):
        value = match.group()
        if value.startswith(('--', '#', '/*')):
            parts.append(' ')
        elif value == ';':
            if ''.join(parts).strip():
                yield ''.join(parts).strip()
            parts = []
        else:
            parts.append(value)
    if ''.join(parts).strip():
        raise ValueError('Unterminated SQL statement: ' + ''.join(parts)[:100])


def translate(sql, variables):
    # Convert MySQL strings to SQLite strings and resolve session variables only OUTSIDE strings.
    def replace(match):
        value = match.group()
        if value.startswith(('"', "'")):
            quote = value[0]
            value = value[1:-1].replace(quote * 2, quote)
            value = re.sub(r'\\(.)', lambda m: {'n': '\n', 'r': '\r', 't': '\t', '0': '\0'}.get(m[1], m[1]), value)
            return "'" + value.replace("'", "''") + "'"
        if value.startswith('@'):
            if value.lower() not in variables:
                raise ValueError('Unknown SQL variable ' + value)
            return str(variables[value.lower()])
        return value
    return re.sub(r"'(?:\\.|''|[^'\\])*'|\"(?:\\.|\"\"|[^\"\\])*\"|@[\w]+", replace, sql)


def enabled_files(server, suffix):
    """The module files init.txt loads (phoenix.modules.enabled_files), for the builders that import it here."""
    return modules.enabled_files(server, suffix)


def snapshot(db, table):
    rows = defaultdict(list)
    for row in db.execute('SELECT * FROM ' + table):
        rows[row[0]].append(dict(row))
    return dict(rows)


def replay(db, path, variables, module=False, tables=None, transform=None):
    # Other catalogs reuse the same fail-closed SQL subset with their selected tables.
    tables = TABLES if tables is None else tables
    touched = set()
    for sql in statements(path.read_text(encoding='utf-8-sig')):
        setting = re.fullmatch(r'SET\s+(@\w+)\s*=\s*(.*)', sql, re.I | re.S)
        if setting:
            # Dump housekeeping variables contain @@ and are not item values.
            if '@@' not in setting[2]:
                variables[setting[1].lower()] = db.execute('SELECT ' + translate(setting[2], variables)).fetchone()[0]
            continue
        if re.match(r'(LOCK|UNLOCK|DROP|SET|ALTER)\b', sql, re.I):
            if module and re.search(r'\b(?:' + '|'.join(tables) + r')\b', sql, re.I):
                raise ValueError(f'{path}: unsupported item SQL: {sql[:200]}')
            continue
        create = re.match(r'CREATE TABLE(?: IF NOT EXISTS)?\s+`?(\w+)`?\s*\(', sql, re.I)
        if create and create[1] in tables and not module:
            # Preserve names/order; values are explicitly supplied by the dumps.
            columns = re.findall(r'^\s*`(\w+)`\s+([^\n]+)', sql, re.M)
            defs = [f'`{name}` ' + ('TEXT' if re.search(r'text|char', kind, re.I) else 'NUMERIC') for name, kind in columns]
            primary = re.search(r'PRIMARY KEY\s*(\([^\n]+\))', sql, re.I)
            if primary:
                defs.append('PRIMARY KEY ' + primary[1])
            db.execute(f'CREATE TABLE {create[1]} (' + ','.join(defs) + ')')
            continue
        if create and create[1].lower() in tables:
            raise ValueError(f'{path}: unsupported module item DDL: {sql[:200]}')
        target = re.match(r'(?:INSERT(?: IGNORE)? INTO|REPLACE INTO|UPDATE|DELETE FROM)\s+`?(\w+)`?\b', sql, re.I)
        if target and target[1].lower() in tables:
            table = target[1].lower()
            translated = translate(sql, variables)
            if transform:
                translated = transform(translated, table)
            translated = re.sub(r'^INSERT IGNORE', 'INSERT OR IGNORE', translated, flags=re.I)
            try:
                db.execute(translated)
            except sqlite3.Error as error:
                raise ValueError(f'{path}: {error}: {sql[:200]}') from error
            touched.add(table)
        elif re.search(r'\b(?:' + '|'.join(tables) + r')\b', sql, re.I) and not create:
            raise ValueError(f'{path}: unsupported item SQL: {sql[:200]}')
    return touched


def lua(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + '"'
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in value.items()) + '}'


def write_lua(path, value):
    path.write_text('-- Generated by tools/build_item_data.py; do not edit.\nreturn ' + lua(value) + ';\n', encoding='utf-8')


def build(server, output, settings=()):
    server, output = Path(server), Path(output)
    db = sqlite3.connect(':memory:')
    db.row_factory = sqlite3.Row
    variables = {}
    for table in TABLES:
        replay(db, server / 'sql' / (table + '.sql'), variables)
    baseline = {table: snapshot(db, table) for table in TABLES}
    sql_files = enabled_files(server, '.sql')
    applied = []
    for path in sql_files:
        touched = replay(db, path, variables, True)
        if touched:
            applied.append(str(path.relative_to(server)))
    records = {}
    for row in db.execute('SELECT * FROM item_basic ORDER BY itemid'):
        records[row[0]] = {'Id': row[0], 'Name': row['sortname'].replace('_', ' '), 'Basic': dict(row)}
    changes = defaultdict(set)
    for table, field in TABLES.items():
        current = snapshot(db, table)
        for ident, rows in current.items():
            if ident not in records:
                continue
            if field != 'Basic':
                records[ident][field] = rows if field in MANY else rows[0]
        for ident in baseline[table].keys() | current.keys():
            if baseline[table].get(ident) != current.get(ident) and ident in records:
                changes[ident].add(field)
    for ident, fields in changes.items():
        records[ident]['Changed'] = sorted(fields)

    # Keep exact script evidence in its own pages. No source code is executed by readers.
    scripts = {}
    by_name = defaultdict(list)
    for record in records.values():
        by_name[record['Basic']['name']].append(record)
    def evidence(path):
        key = str(path.relative_to(server))
        text = path.read_text(encoding='utf-8-sig')
        scripts[key] = {'Path': key, 'SHA256': hashlib.sha256(text.encode()).hexdigest(), 'Text': text}
        return key, text
    for name, items in by_name.items():
        path = server / 'scripts/items' / (name + '.lua')
        if path.is_file():
            key, text = evidence(path)
            # A deliberately narrow, auditable extraction: ONLY a straight list of literal
            # effect:addMod calls. Conditional/calculated food effects remain source-only.
            clean = re.sub(r'--[^\n]*', '', text)
            gain = re.search(r'itemObject\.onEffectGain\s*=\s*function\(target, effect\)(.*?)\bend\b', clean, re.S)
            mods = []
            if gain:
                pattern = r'effect:addMod\(xi\.mod\.(\w+),\s*(-?\d+)\s*\)'
                if not re.sub(pattern, '', gain[1]).strip():
                    mods = [{'Name': name, 'Value': int(value)} for name, value in re.findall(pattern, gain[1])]
            use = re.search(r'itemObject\.onItemUse\s*=\s*function\([^)]*\)(.*?)\bend\b', clean, re.S)
            duration = None
            if use and not re.search(r'\b(if|for|while|return|local|function)\b', use[1]):
                duration = re.search(r'addStatusEffect\(xi\.effect\.FOOD,\s*\{\s*duration\s*=\s*(\d+)', use[1])
            for record in items:
                record['Script'] = key
                if mods and duration:
                    record['Food'] = {'Duration': int(duration[1]), 'Mods': mods, 'Source': key}
    # Every module override of an item's script, as live has it (phoenix.modules): its gate
    # evaluated, one made in a loop found by its row; those off on live are left out.
    declarations = []

    def handle(override):
        if override.target == '?':
            # a target not written out: only one whose code is an item's would matter here
            return None if re.search(r'\b(onItem)', override.body) else 'target not written out; not an item\'s code'
        name, _, callback = override.target.removeprefix('xi.items.').rpartition('.')
        key, _ = evidence(server / 'modules' / override.path)
        status = 'on live' if override.applies else f'gate not understood, taken as on: {override.condition}'
        declarations.append({'Path': key, 'Target': override.target, 'Status': status})
        for record in by_name.get(name, []):
            record.setdefault('Overrides', []).append({'Path': key, 'Callback': callback, 'Status': status})
            # An override may replace either the food use duration or effect modifiers.
            record.pop('Food', None)
        return f'{callback} replaced on {len(by_name.get(name, []))} item(s)' if name in by_name else 'no item of that name'

    modules.guard(server, ('xi.items.',), handle)
    pages = defaultdict(dict)
    for ident, record in records.items():
        pages[ident // PAGE_SIZE][ident] = record
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(server / 'LICENSE', output / 'LICENSE-Phoenix')
    (output / 'NOTICE.txt').write_text(
        'Generated from Phoenix (https://github.com/phoenixffxi/Phoenix).\n'
        'Embedded server script sources retain their upstream GNU GPL v3 license; see LICENSE-Phoenix.\n'
        'This is not a relicensing of upstream sources under winxi\'s MIT license.\n'
        'index.lua records the source revision; script evidence records original paths and SHA256.\n', encoding='utf-8')
    for page, rows in sorted(pages.items()):
        write_lua(output / f'{page}.lua', rows)
    # Script files use numbered pages as well; index maps source paths to those pages.
    script_index = {}
    script_pages = defaultdict(dict)
    for number, (key, data) in enumerate(sorted(scripts.items())):
        page = number // 64
        script_index[key] = page
        script_pages[page][key] = data
    for page, data in script_pages.items():
        write_lua(output / f'script_{page}.lua', data)
    enums = {}
    for name in ('mod', 'latent', 'job', 'skill_type', 'element'):
        enums[name] = modules.load_yaml(server, f'enums/{name}')['values']
    found = source.read(server)
    metadata = {
        'Schema': 1, 'Count': len(records), 'PageSize': PAGE_SIZE,
        'Source': {'Repository': found.repository, 'Branch': found.branch, 'Commit': found.commit, 'Committed': found.committed},
        'Settings': list(settings), 'SQL': applied, 'Scripts': script_index, 'Declarations': declarations,
        'Enums': enums, 'ChangedCount': len(changes),
        'Limitations': [
            'All item_basic IDs, including later-era and unavailable items; presence is not obtainability.',
            'SQL replay models a clean import, not private live database edits.',
            'Lua overrides are listed with their module gates evaluated for live (expansions from WotG on taken as off); what they do is not, nor their super chains.',
            'Script text is evidence, not a complete tooltip or unconditional stat list.',
            'Display descriptions/icons/localized names come from client resources; may differ from server behavior.',
            'Modifiers retain server units; latents and pet modifiers are conditional, never summed into base stats.',
        ],
    }
    write_lua(output / 'index.lua', metadata)
    # Portable full list, convenient for auditing and tooling; Lua readers only load pages they need.
    (output / 'catalog.json').write_text(json.dumps({'Metadata': metadata, 'Items': list(records.values())}, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
    db.close()
    print(f'Items: {len(records)}, SQL-changed: {len(changes)}, script sources: {len(scripts)}, item override declarations: {len(declarations)}')
    return metadata


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    source.add_arguments(parser)
    parser.add_argument('--out', type=Path, default=Path(__file__).resolve().parents[1] / 'addons/libs/winxi/data/items')
    args = parser.parse_args()
    found = source.from_arguments(args)
    # A standalone build also discards stale pages only after generation succeeds.
    import tempfile
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.out.parent) as scratch:
        made = Path(scratch) / 'items'
        build(found.path, made)
        if args.out.exists():
            shutil.rmtree(args.out)
        shutil.move(str(made), str(args.out))
