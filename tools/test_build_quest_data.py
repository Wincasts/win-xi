import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from build_quest_data import build, tokens, pairs, static_value, quest_enum, function_end, source_name


ENUM = '''xi.quest.area = {
 [xi.questLog.SANDORIA] = 'sandoria',
 [xi.questLog.BASTOK] = 'bastok',
 [xi.questLog.JEUNO] = 'jeuno',
}
xi.quest.id = {
 [xi.quest.area[xi.questLog.SANDORIA]] = { FIRST = 0, ALIAS = 0 },
 [xi.quest.area[xi.questLog.BASTOK]] = { SECOND = 0 },
 [xi.quest.area[xi.questLog.JEUNO]] = { BAG = 27 },
}
'''


def fixture(root):
    def write(name, text):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    write('LICENSE', 'Fixture upstream license')
    for name, values in (('zone', '  SOUTHERN_SAN_DORIA: 230\n  BASTOK_MARKETS: 235'),
                         ('key_item', '  SAMPLE: 4'), ('fame_area', '  SANDORIA: 0'), ('job', '  WAR: 1')):
        write(f'data/enums/{name}.yaml', 'values:\n' + values + '\n')
    for name, text in (
            ('quest_log', 'SANDORIA = 0, BASTOK = 1, JEUNO = 3,'),
            ('quest_status', 'QUEST_AVAILABLE = 0, QUEST_ACCEPTED = 1,'),
            ('item', 'KITE_SHIELD = 12306, ANNIVERSARY_RING = 15793,'),
            ('title', 'SAMPLE = 3,')):
        write(f'scripts/enum/{name}.lua', 'xi.value = { ' + text + ' }')
    write('scripts/globals/quests.lua', ENUM)
    write('scripts/globals/interaction/quest.lua', 'return {}')
    write('scripts/globals/interaction/hidden_quest.lua', 'return {}')
    write('scripts/quests/jeuno/helpers.lua', '''function xi.jeuno.helpers.GobbiebagQuest:new(params)
local quest = Quest:new(xi.questLog.JEUNO, params.questId)
quest.reward = params.reward
quest.sections = { { [xi.zone.BASTOK_MARKETS] = { ['BagNpc'] = quest:event(1) } } }
return quest
end''')
    write('scripts/quests/jeuno/Bag.lua', '''-- The Bag Quest
local params = { questId = xi.quest.id.jeuno.BAG, reward = { gil = 20 } }
local quest = xi.jeuno.helpers.GobbiebagQuest:new(params)
return quest''')
    write('scripts/quests/sandoria/First.lua', '''-- First Quest's Title
local quest = Quest:new(xi.questLog.SANDORIA, xi.quest.id.sandoria.FIRST)
-- Quest:new(xi.questLog.BASTOK, 999)
local fake = "xi.quest.id.bastok.FAKE"
quest.reward = { gil = 150, item = xi.item.KITE_SHIELD, keyItem = xi.keyItem.SAMPLE }
quest.sections = {
 { check = function(player) return player:getMainLvl() >= 18 end,
   [xi.zone.SOUTHERN_SAN_DORIA] = {
     ['Npc_One'] = { onTrigger = function(player)
       player:setCharVar('Prog', 1)
       npcUtil.giveItem(player, xi.item.ANNIVERSARY_RING)
       local nested = { ['Not_An_NPC'] = 1 }
     end },
   },
 },
}
error('This server script must never execute')
return quest''')
    write('scripts/quests/bastok/Second.lua', '''-- Second Quest
local quest = Quest:new(xi.questLog.BASTOK, xi.quest.id.bastok.SECOND)
quest.reward = { gil = calculateReward(), item = { { xi.item.KITE_SHIELD, 2 } } }
quest.sections = { { [xi.zone.BASTOK_MARKETS] = { ['Npc_Two'] = quest:event(1) } } }
return quest''')
    write('scripts/quests/hiddenQuests/Hidden.lua', '''-- Hidden Interaction
local quest = HiddenQuest:new('hiddenId')
quest.sections = { { [xi.zone.BASTOK_MARKETS] = { ['HiddenNpc'] = quest:event(1) } } }
return quest''')
    write('scripts/quests/Incomplete.lua.todo', "this is not valid Lua; don't index it")
    write('modules/init.txt', 'active\n# disabled\n')
    write('modules/active/quests.lua', '''-- modifyInteractionEntry('scripts/quests/bastok/Second', fake)
m:addOverride('xi.server.onServerStart', function()
 xi.module.modifyInteractionEntry('scripts/quests/sandoria/First', function(quest)
   quest.reward.item = xi.item.ANNIVERSARY_RING
 end)
 xi.module.modifyInteractionEntry('scripts/quests/hiddenQuests/Hidden', function(quest) end)
end)
m:addOverride('xi.zones.Bastok_Markets.npcs.Npc_Two.onTrigger', function() end)
''')
    write('modules/disabled/bad.lua', "xi.module.modifyInteractionEntry('scripts/quests/bastok/Second', function(quest) end)")
    return root


class QuestDataTest(unittest.TestCase):
    def test_identity_aliases_comments_and_cross_log_collisions(self):
        constants = {'xi.questLog.SANDORIA': 0, 'xi.questLog.BASTOK': 1, 'xi.questLog.JEUNO': 3}
        areas, records, symbols = quest_enum(ENUM, constants)
        self.assertEqual(len(records), 3)
        self.assertIsNot(records['0:0'], records['1:0'])
        self.assertEqual(records['0:0']['Symbols'], ['FIRST', 'ALIAS'])
        self.assertIs(symbols['xi.quest.id.sandoria.FIRST'], records['0:0'])
        self.assertEqual(areas['bastok'], 1)
        with self.assertRaises(ValueError):
            quest_enum(ENUM.replace('SECOND = 0', 'SECOND = calculateId()'), constants)

    def test_lexer_and_literal_tables_never_evaluate_expressions(self):
        text = '''--[[ Quest:new(99,99) ]]\n{ item = { { xi.item.SAMPLE, 2 }, 10 }, gil = scale(), text = "-- fake end" }'''
        ts = tokens(text)
        self.assertFalse(any(t.value == 'Quest' for t in ts))
        value, complete = static_value(ts, {'xi.item.SAMPLE': 123})
        self.assertFalse(complete)
        self.assertEqual(value['item'][1], {1: 123, 2: 2})
        self.assertTrue(value['gil']['Unresolved'])
        self.assertEqual(value['text'], '-- fake end')
        self.assertEqual(static_value(tokens('-3'), {})[0], -3)
        self.assertEqual(static_value(tokens('[[literal end]]'), {})[0], 'literal end')
        with self.assertRaises(ValueError):
            pairs(tokens('{ broken = ( }'))
        duplicate, complete = static_value(tokens('{ gil = 1, gil = 2 }'), {})
        self.assertFalse(complete)
        self.assertTrue(duplicate['Unresolved'])
        dynamic, complete = static_value(tokens('{ callback = function() local a, item = nil, 12306 end }'), {})
        self.assertFalse(complete)
        self.assertTrue(dynamic['Unresolved'])
        self.assertNotIn('item', dynamic)

    def test_function_ranges_and_titles(self):
        ts = tokens('function example() for i=1,3 do if i>1 then local f=function() end end end repeat do local x=1 end until true end trailing()')
        end = function_end(ts, 0)
        self.assertEqual(ts[end].value, 'end')
        self.assertEqual(ts[end + 1].value, 'trailing')
        self.assertEqual(source_name('-- -----\n-- A Knight\'s Test\n-- Log ID: 0', 'fallback'), ("A Knight's Test", 'source-header'))

    def test_complete_fixture_build_modules_factories_evidence_and_rewards(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            server = fixture(root / 'server')
            output = root / 'output'
            metadata = build(server, output)
            catalog = json.loads((output / 'catalog.json').read_text())
            records = {r['Key']: r for r in catalog['Quests']}
            first, second, bag = records['0:0'], records['1:0'], records['3:27']
            self.assertEqual(metadata['Count'], 3)
            self.assertEqual(metadata['HiddenCount'], 1)
            self.assertEqual(first['Name'], "First Quest's Title")
            self.assertEqual(first['DeclaredRewardItems'], [12306])
            self.assertNotIn(15793, metadata['ByDeclaredRewardItem'])
            self.assertEqual(first['RewardDeclarations'][0]['Fields']['gil'], 150)
            self.assertFalse(second['RewardDeclarations'][0]['Complete'])
            self.assertTrue(second['RewardDeclarations'][0]['Fields']['gil']['Unresolved'])
            self.assertEqual({n['Name'] for n in first['NPCs']}, {'Npc_One'})
            self.assertEqual(first['Zones'][0]['Id'], 230)
            self.assertTrue(any(r['Kind'] == 'interaction-edit-declaration' for r in first['References']))
            self.assertFalse(any(r['Kind'] == 'interaction-edit-declaration' for r in second.get('References', [])))
            self.assertTrue(any('NPC-override-association' in r['Kind'] for r in second['References']))
            self.assertTrue(all('disabled' not in p for p in metadata['Scripts']))
            self.assertEqual(bag['Coverage'], 'factory-script')
            self.assertEqual(bag['NPCs'][0]['Name'], 'BagNpc')
            self.assertEqual(bag['RewardDeclarations'][0]['Fields']['gil'], 20)
            self.assertTrue(catalog['Hidden'][0]['Modules'])
            self.assertEqual(len(metadata['TodoFiles']), 1)
            # Source references point at real lines, not preceding tokens/blank lines.
            text = (server / 'scripts/quests/sandoria/First.lua').read_text().splitlines()
            for entry in first['Evidence']:
                self.assertEqual(entry['Text'], text[entry['Line'] - 1].strip())
                if entry['Kind'] == 'condition-reference':
                    self.assertIn('getMainLvl', entry['Text'])
            before = {p.name: p.read_bytes() for p in output.iterdir()}
            second_output = root / 'second'
            build(server, second_output)
            self.assertEqual(before, {p.name: p.read_bytes() for p in second_output.iterdir()})

    def test_failed_shared_build_leaves_previous_quest_set(self):
        import build_winxi_data as shared
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            server = fixture(root / 'server')
            old = root / 'data/quests'
            old.mkdir(parents=True)
            (old / 'sentinel').write_text('previous data')
            (server / 'scripts/globals/quests.lua').write_text('xi.quest.id = {}')
            with patch.object(shared, 'DATA', root / 'data'), patch.object(sys, 'argv', ['build_winxi_data.py', '--server', str(server), '--only', 'quests']):
                with self.assertRaises(ValueError):
                    shared.main()
            self.assertEqual((old / 'sentinel').read_text(), 'previous data')
            self.assertFalse((old / 'index.lua').exists())


if __name__ == '__main__':
    unittest.main()
