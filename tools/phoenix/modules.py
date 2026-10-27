"""Phoenix's modules as the live server loads them, for the build scripts.

The server's scripts are only the start: modules/init.txt loads modules over them, and those
replace functions (addOverride, addOverrideByEra) behind gates on the era (xi.pre). A build script
that reads the scripts and not the modules builds the wrong numbers wherever a module changed them,
so every build script that reads the server goes through guard():

    from phoenix import modules

    def handle(override):                  # an override of something the script reads, gated on
        ...                                # (or with a gate not known): say what was done with it,
        return 'applied: Blind 80-300 s'   # or None when the script does not know what it does

    modules.guard(server, ('xi.spells.enfeebling.',), handle)

guard stops the build, listing them, when any override the script reads is one it cannot account
for, so a new module on live is never passed over without someone deciding what it means.

    modules.enabled_files(server, '.lua')   the files init.txt loads, in its order
    modules.files_on_live(server)           those of them with a module on live (not all gated off)
    modules.overrides(server)               every override in them: Override below
    modules.pre(name)                       xi.pre(xi.expansion.NAME) on live, as taken here
    modules.function_body(text, start)      the text of a Lua function, for reading what it sets
    modules.seconds(expr, body)             a duration expression as (least, most) seconds, or None

The data is patched as well: a module's data/<name>.yaml is an RFC 7396 merge patch over the
server's data/<name>.yaml (objects merge by key, lists are replaced whole, null takes a key out),
zone files (data/zones/<zone>/mobs.yaml and the like) included, in init.txt's order:

    modules.load_yaml(server, 'zones/west_ronfaure/zone')   the file as live loads it, or None
    modules.data_patches(server, name)      the module files patching it, in order
    modules.data_roots(server)              the data folders init.txt names

Which init.txt entries name a data folder is modules/temp_patch/lsb-yaml.patch's rule (an entry
with a data folder in its path, or a bare module name), the core's own being the module's first
path segment's data folder for whole files and nothing for zone files: that live is built with the
patch is inferred (init.txt names data folders like era/data/abyssea/job_adjustments, which only it
reads), and DATA_PATCH says so.

The live server's settings are not in the repository, so which expansions it has is inferred:
init.txt applies the era SQL for WotG, Abyssea, SoA and RoV, so content from WotG on is taken to be
off (xi.pre true) and Treasures of Aht Urhgan and before on. LATEST_ENABLED is that one assumption.
"""
import re
import sys
from pathlib import Path

DATA_PATCH = True  # modules/temp_patch/lsb-yaml.patch is taken to be applied on live
EXPANSIONS = ('ROTZ', 'COP', 'TOAU', 'WOTG', 'ACP', 'AMK', 'ASA', 'ABYSSEA', 'VOIDWATCH', 'SOA', 'ROV', 'TVR')
LATEST_ENABLED = 'TOAU'


def pre(name):
    """xi.pre(xi.expansion.NAME): whether that expansion's content is off on live."""
    return EXPANSIONS.index(name) > EXPANSIONS.index(LATEST_ENABLED)


def gate(expression):
    """A Module:new condition on live: True, False, or None for one not understood."""
    expression = ' '.join(expression.split())
    if not expression:
        return True
    for joiner, combine in ((' or ', any), (' and ', all)):
        parts = expression.split(joiner)
        if len(parts) > 1:
            each = [gate(part) for part in parts]
            return None if None in each else combine(each)
    m = re.fullmatch(r'(not\s+)?xi\.pre\(\s*xi\.expansion\.(\w+)\s*\)', expression)
    if m and m.group(2) in EXPANSIONS:
        return pre(m.group(2)) != bool(m.group(1))
    return None


def enabled_files(server, suffix):
    """The files modules/init.txt loads with that suffix, in its order, each folder sorted; none
    where there is no init.txt, as for the server."""
    server = Path(server)
    files = []
    if not (server / 'modules/init.txt').is_file():
        return files
    for line in (server / 'modules/init.txt').read_text().splitlines():
        entry = line.split('#', 1)[0].strip()
        if not entry:
            continue
        path = server / 'modules' / entry
        candidates = sorted(path.rglob('*' + suffix)) if path.is_dir() else [path] if path.suffix == suffix and path.is_file() else []
        for candidate in candidates:
            if candidate not in files:
                files.append(candidate)
    return files


def files_on_live(server):
    """The Lua files init.txt loads, in its order, but those whose every module is off on live: for a
    build script that reads a module's text rather than its overrides one by one."""
    off = {}
    for override in overrides(server):
        off.setdefault(override.path, []).append(override.applies is False)
    server = Path(server)
    kept = []
    for path in enabled_files(server, '.lua'):
        flags = off.get(path.relative_to(server / 'modules').as_posix())
        if not flags or not all(flags):
            kept.append(path)
    return kept


def blank_comments(text):
    """The text with its Lua comments turned to spaces, strings and line numbers kept."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in '\'"':
            j = i + 1
            while j < n and text[j] != c and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith('--', i):
            long = re.match(r'--\[(=*)\[', text[i:])
            end = text.find(']' + long.group(1) + ']', i) + len(long.group(1)) + 2 if long else text.find('\n', i)
            if end < i or (long and end < len(long.group(0))):
                end = n
            out.append(re.sub(r'[^\n]', ' ', text[i:end]))
            i = end
        elif text.startswith('[[', i) or re.match(r'\[=+\[', text[i:]):
            level = re.match(r'\[(=*)\[', text[i:]).group(1)
            end = text.find(']' + level + ']', i)
            end = n if end < 0 else end + len(level) + 2
            out.append(text[i:end])
            i = end
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def closing(text, start):
    """Where the bracket opened at start closes (comments already blanked), or len(text)."""
    pairs = {'(': ')', '{': '}', '[': ']'}
    stack, i = [], start
    while i < len(text):
        c = text[i]
        if c in '\'"':
            j = i + 1
            while j < len(text) and text[j] != c:
                j += 2 if text[j] == '\\' else 1
            i = j
        elif c in pairs:
            stack.append(pairs[c])
        elif stack and c == stack[-1]:
            stack.pop()
            if not stack:
                return i
        i += 1
    return len(text)


BLOCK_OPENERS = re.compile(r'\b(function|if|for|while|do|repeat|end|until)\b')


def function_body(text, start):
    """From a 'function' keyword at or after start, the text up to its matching end."""
    first = text.find('function', start)
    if first < 0:
        return ''
    # 'for ... do' and 'while ... do' open one block, not two: their do is waited for
    depth, waiting = 0, 0
    for m in BLOCK_OPENERS.finditer(text, first):
        word = m.group(1)
        if word in ('for', 'while'):
            depth, waiting = depth + 1, waiting + 1
        elif word == 'do':
            if waiting:
                waiting -= 1
            else:
                depth += 1
        elif word in ('function', 'if', 'repeat'):
            depth += 1
        else:
            depth -= 1
            if depth == 0:
                return text[first:m.end()]
    return text[first:]


def arguments(text, start):
    """The arguments of the call whose ( is at start, split at its own commas, each stripped."""
    close = closing(text, start)
    parts, depth, begin = [], 0, start + 1
    i = start + 1
    while i < close:
        c = text[i]
        if c in '\'"':
            j = i + 1
            while j < close and text[j] != c:
                j += 2 if text[j] == '\\' else 1
            i = j
        elif c in '({[':
            depth += 1
        elif c in ')}]':
            depth -= 1
        elif c == ',' and depth == 0:
            parts.append(text[begin:i].strip())
            begin = i + 1
        i += 1
    last = text[begin:close].strip()
    if last or parts:
        parts.append(last)
    return parts


def fields(table):
    """A Lua table's name = value fields, the values as written."""
    inner = table.strip()[1:-1] if table.strip().startswith('{') else table
    found = {}
    for part in arguments('(' + inner + ')', 0):
        m = re.fullmatch(r'(\w+)\s*=\s*(.+)', part, re.S)
        if m:
            found[m.group(1)] = m.group(2).strip()
    return found


class Override:
    """One addOverride or addOverrideByEra: what it replaces, where, and whether it is on on live.

    body is the function (or, for addOverrideByEra, the table of a function for each era) and text
    the whole file it is in, comments blanked. An override made in a loop over a table of targets
    (addOverride(entry.path, ...)) is one Override for each row, row its fields; when its targets
    cannot be found it is one whose target is '?', which every guard is handed; one whose target is
    made with string.format has the format as its target, each %s a *.
    """

    def __init__(self, target, path, line, module, condition, applies, body, eras=(), text='', row=None):
        self.target, self.path, self.line = target, path, line
        self.module, self.condition, self.applies = module, condition, applies
        self.body, self.eras, self.text, self.row = body, eras, text, row or {}

    def cases(self):
        """For addOverrideByEra, [(era, its function)], the ones used on live; else [(None, body)]."""
        if not self.eras:
            return [(None, self.body)]
        found = []
        for m in re.finditer(r'\[\s*xi\.expansion\.(\w+)\s*\]\s*=\s*', self.body):
            if m.group(1) in EXPANSIONS and pre(m.group(1)):
                found.append((m.group(1), function_body(self.body, m.end())))
        return found

    def digest(self):
        """A short hash of the override's code, whitespace aside: for a decision taken on reading it,
        which a change to it should send back to be read again."""
        import hashlib
        return hashlib.sha1(' '.join(self.body.split()).encode()).hexdigest()[:10]

    def where(self):
        return f'{self.path}:{self.line}'

    def __repr__(self):
        return f'<Override {self.target} at {self.where()}>'


MODULE = re.compile(r"\blocal\s+(\w+)\s*=\s*Module:new\(\s*['\"]([^'\"]+)['\"]\s*(?:,\s*)?")
CALL = re.compile(r"\b(\w+)\s*:\s*(addOverride|addOverrideByEra)\s*\(")


def overrides(server):
    server = Path(server)
    found = []
    for path in enabled_files(server, '.lua'):
        text = blank_comments(path.read_text(encoding='utf-8-sig'))
        relative = path.relative_to(server / 'modules').as_posix()
        declared = {}
        for m in MODULE.finditer(text):
            close = closing(text, text.index('(', m.start()))
            declared[m.group(1)] = (m.group(2), text[m.end():close])
        for m in CALL.finditer(text):
            name, condition = declared.get(m.group(1), (m.group(1), None))
            applies = gate(condition) if condition is not None else None
            close = closing(text, m.end() - 1)
            args = arguments(text, m.end() - 1)
            if not args:
                continue
            first = args[0]
            body = text[m.end():close].split(first, 1)[1].lstrip().removeprefix(',')
            eras = ()
            if m.group(2) == 'addOverrideByEra':
                # a case for each era, used while that era's content is off
                eras = tuple(re.findall(r'\[\s*xi\.expansion\.(\w+)\s*\]\s*=', body))
                if applies is not False:
                    on = [pre(era) for era in eras if era in EXPANSIONS]
                    applies = (any(on) if on else None) if applies else applies
            line = text.count('\n', 0, m.start()) + 1
            pattern = target_pattern(first)
            if pattern is not None and pattern.strip('*.'):
                targets = [(pattern, None)]
            else:
                targets = rows_of(text, first, m.start())
            for target, row in targets:
                found.append(Override(target, relative, line, name, condition, applies, body, eras, text, row))
    return found


def target_pattern(expression):
    """An override's target as written: a string; string.format('...%s...') or fmt('...{}...'); or
    pieces joined with '..'. What is not written out is a '*'. None for anything else."""
    expression = expression.strip()
    literal = re.fullmatch(r"(['\"])([^'\"]*)\1", expression)
    if literal:
        return literal.group(2)
    formatted = re.fullmatch(r"(?:string\.format|fmt)\(\s*(['\"])([^'\"]+)\1.*\)", expression, re.S)
    if formatted:
        return re.sub(r'%[sd]|\{\}', '*', formatted.group(2))
    if '..' in expression:
        pieces = [piece.strip() for piece in expression.split('..')]
        return ''.join(re.fullmatch(r"(['\"])([^'\"]*)\1", piece).group(2)
                       if re.fullmatch(r"(['\"])([^'\"]*)\1", piece) else '*' for piece in pieces)
    return None


def concerns(target, prefixes):
    """Whether an override of target (a pattern where it has a *, or '?') may be of something
    starting with one of prefixes."""
    if target == '?':
        return True
    written = target.split('*', 1)[0]
    if '*' not in target:
        return target.startswith(tuple(prefixes))
    return any(written.startswith(prefix) or prefix.startswith(written) for prefix in prefixes)


def rows_of(text, expression, at):
    """The targets of an override made in a loop: for 'entry.path' inside
    'for _, entry in ipairs(TABLE) do', each row of TABLE's path, with the row; or [('?', None)]."""
    m = re.fullmatch(r'(\w+)\.(\w+)', expression)
    loops = list(re.finditer(r'for\s+\w+\s*,\s*(\w+)\s+in\s+i?pairs\(\s*(\w+)\s*\)\s*do', text[:at]))
    if m and loops and loops[-1].group(1) == m.group(1):
        table = re.search(r'\blocal\s+' + loops[-1].group(2) + r'\s*=\s*\{', text)
        if table:
            close = closing(text, table.end() - 1)
            rows = []
            for row in re.finditer(r'\{', text[table.end():close]):
                start = table.end() + row.start()
                if text[start - 1:start] == '{' and start - 1 == table.end() - 1:
                    continue
                values = fields(text[start:closing(text, start) + 1])
                target = values.get(m.group(2), '').strip('\'"')
                if target.startswith('xi.'):
                    rows.append((target, values))
            if rows:
                return rows
    return [('?', None)]


def seconds(expression, body=''):
    """A duration as written: a number, math.random(a, b), math.randomInt(a, b),
    xi.mobskills.calculateDuration(tp, a, b), or a local of the body set to one of those; as
    (least, most), or None when it is anything else."""
    expression = expression.strip()
    if re.fullmatch(r'\d+', expression):
        return int(expression), int(expression)
    m = re.fullmatch(r'math\.random(?:Int)?\(\s*(\d+)\s*,\s*(\d+)\s*\)', expression)
    if m:
        return int(m.group(1)), int(m.group(2))
    # by the TP of a monster's move: the least at 1000, the most at 3000
    m = re.fullmatch(r'xi\.mobskills\.calculateDuration\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', expression)
    if m:
        return int(m.group(1)), int(m.group(2))
    if re.fullmatch(r'[A-Za-z_]\w*', expression) and body:
        sets = re.findall(r'\blocal\s+' + expression + r'\s*=\s*([^\n]+)', body)
        if len(sets) == 1:
            return seconds(sets[0], '')
    return None


def guard(server, prefixes, handle, out=sys.stdout):
    """Every override on live of something starting with one of prefixes, handed to handle; the
    build stops when handle returns None for any. Returns [(override, what handle said)]."""
    done, unknown = [], []
    for override in overrides(server):
        if not concerns(override.target, prefixes):
            continue
        if override.applies is False:
            done.append((override, f'off on live ({override.condition.strip() or "no gate"})'))
            continue
        what = handle(override)
        if what is None:
            unknown.append(override)
        else:
            if override.applies is None:
                what += f'; its gate is not understood, taken as on: {override.condition}'
            done.append((override, what))
    for override, what in done:
        print(f'  module {override.target} ({override.where()}): {what}', file=out)
    if unknown:
        lines = [f'  {o.target} ({o.where()}, module {o.module})' for o in unknown]
        sys.exit('Phoenix modules override what this build reads, and it does not say what to do with them:\n'
                 + '\n'.join(lines) + '\nRead each and teach the build script about it (its handle function).')
    return done


def data_roots(server):
    """The data folders init.txt names, in its order, each once; none without an init.txt."""
    server = Path(server)
    roots = []
    if not (server / 'modules/init.txt').is_file():
        return roots
    for line in (server / 'modules/init.txt').read_text().splitlines():
        entry = line.split('#', 1)[0].strip().rstrip('/')
        if not entry:
            continue
        parts = entry.split('/')
        if DATA_PATCH:
            if 'data' in parts:
                root = server / 'modules' / entry
            elif len(parts) == 1:
                root = server / 'modules' / entry / 'data'
            else:
                continue
        else:
            root = server / 'modules' / parts[0] / 'data'
        if root not in roots:
            roots.append(root)
    return roots


def data_patches(server, name):
    """The module files that patch data/<name>.yaml on live, in order."""
    if not DATA_PATCH and name.startswith('zones/'):
        return []
    return [root / f'{name}.yaml' for root in data_roots(server) if (root / f'{name}.yaml').is_file()]


def merge_patch(target, patch):
    """RFC 7396: patch merged into target, a new value."""
    if not isinstance(patch, dict):
        return patch
    merged = dict(target) if isinstance(target, dict) else {}
    for key, value in patch.items():
        if value is None:
            merged.pop(key, None)
        else:
            merged[key] = merge_patch(merged.get(key), value)
    return merged


def load_yaml(server, name):
    """data/<name>.yaml as live loads it, its module patches merged in; None when the server has no
    such file (a zone without one declares none of that kind, whatever a module has)."""
    import yaml
    loader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)
    core = Path(server) / 'data' / f'{name}.yaml'
    if not core.is_file():
        return None
    document = yaml.load(core.read_text(encoding='utf-8-sig'), Loader=loader)
    for path in data_patches(server, name):
        document = merge_patch(document, yaml.load(path.read_text(encoding='utf-8-sig'), Loader=loader))
    return document
