-- Best-effort local guards. Unknown context is unsafe, not permission to infer.
local bit = require('bit')
local M = {}
local blocked = { [54]=true, [168]=true, [170]=true, [270]=true, [271]=true, [272]=true, [273]=true,
    [310]=true, [321]=true, [334]=true, [340]=true, [342]=true, [408]=true, [410]=true,
    [468]=true, [472]=true, [483]=true, [502]=true, [801]=true }
-- Without a complete trait/modifier view, reject these jobs conservatively even
-- at levels where a trait may not yet apply: WAR/THF/BLU multi-attacks; RNG/DRG/DNC Conserve TP.
local unsafeJobs = { [1]=true, [6]=true, [11]=true, [14]=true, [16]=true, [19]=true }
function M.Context(memory, resources)
    local result = { id = memory:GetParty():GetMemberServerId(0), safe = false, reason = 'unavailable local context' }
    local ok = pcall(function()
        local party, player, inventory = memory:GetParty(), memory:GetPlayer(), memory:GetInventory()
        result.hp = party:GetMemberHP(0)
        if not result.hp or result.hp <= 0 or player:GetIsZoning() ~= 0 then result.reason = 'HP/zoning context'; return end
        if unsafeJobs[player:GetMainJob()] or unsafeJobs[player:GetSubJob()] then result.reason = 'multi-attack/Conserve TP job'; return end
        local icons = player:GetStatusIcons()
        for i = 1, 32 do if blocked[icons[i]] then result.reason = 'TP/multi-attack buff'; return end end
        local signature, weapons = {}, {}
        for slot = 0, 15 do
            local equipped = inventory:GetEquippedItem(slot)
            local index = equipped and equipped.Index or 0
            local item = index ~= 0 and inventory:GetContainerItem(bit.band(bit.rshift(index, 8), 255), bit.band(index, 255)) or nil
            signature[#signature + 1] = tostring(index) .. ':' .. tostring(item and item.Id or 0)
            if slot < 2 and item then weapons[slot] = resources:GetItemById(item.Id) end
        end
        if not weapons[0] or weapons[0].Type ~= 5 or type(weapons[0].Skill) ~= 'number'
            or weapons[0].Skill < 2 or weapons[0].Skill > 12 then result.reason = 'unsupported weapon/H2H'; return end
        if weapons[1] and weapons[1].Type == 5 and weapons[1].Skill ~= 0 then result.reason = 'dual wield'; return end -- grips have skill 0
        result.signature, result.safe, result.reason = table.concat(signature, '/'), true, nil
    end)
    if not ok then result.safe = false end
    return result
end
function M.U32(data, offset)
    if type(data) ~= 'string' or #data < offset + 4 then return nil end
    local a,b,c,d = data:byte(offset + 1, offset + 4)
    return a + b*256 + c*65536 + d*16777216
end
function M.TP(data)
    local id, hp, tp = M.U32(data, 4), M.U32(data, 8), M.U32(data, 16)
    if not id or id == 0 or not tp or tp > 3000 then return nil end
    return id, tp, hp
end
return M
