-- Main-hand combat skill, rather than item ID: all swords share a weapon palette.
local weapon = {};
local names = {
    'Hand-to-Hand', 'Dagger', 'Sword', 'Great Sword', 'Axe', 'Great Axe',
    'Scythe', 'Polearm', 'Katana', 'Great Katana', 'Club', 'Staff',
};

function weapon.Label(skill)
    return names[skill] or 'Unavailable';
end

function weapon.Current()
    local memory = AshitaCore:GetMemoryManager();
    if not memory.GetParty then return 0; end
    local index = memory:GetParty():GetMemberTargetIndex(0);
    if not index or index == 0 or not memory.GetInventory then return 0; end
    local inventory = memory:GetInventory();
    local equipped = inventory:GetEquippedItem(0);
    if not equipped then return 0; end
    -- Empty main hand is the unarmed / hand-to-hand category.
    if equipped.Index == 0 then return 1; end
    local item = inventory:GetContainerItem(math.floor(equipped.Index / 256), equipped.Index % 256);
    if not item or not item.Id or item.Id == 0 or item.Id == 65535 then return 0; end
    local resource = AshitaCore:GetResourceManager():GetItemById(item.Id);
    local skill = resource and resource.Skill;
    return names[skill] and skill or 0;
end

return weapon;
