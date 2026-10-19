"""The lotteries a zone's data sets out: data/zones/<zone>/mobs.yaml's slots.

A slot is a group of spawns of which one stands at a time. Its members with a chance (in percent)
and, mostly, a cooldown (in seconds) are what is drawn; the others are what it is drawn from, the
placeholders. A slot none of whose members has a chance is a rotation, not a lottery.
"""


def from_slots(document):
    """[(NM id, [placeholder ids], {'chance': percent, 'cooldown': seconds or None})] for each drawn member."""
    found = []
    for slot in document.get('slots') or []:
        members = (slot or {}).get('members') or {}
        placeholders = [int(mob_id) for mob_id, rule in members.items() if 'chance' not in (rule or {})]
        for mob_id, rule in members.items():
            rule = rule or {}
            if 'chance' in rule:
                found.append((int(mob_id), placeholders, {'chance': rule['chance'], 'cooldown': rule.get('cooldown')}))
    return found
