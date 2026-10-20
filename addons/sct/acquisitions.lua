-- Compare game memory after updates: only main Inventory gains can notify.
-- Other bags are read solely to distinguish transfers from genuine receipts.
local acquisitions = {};
acquisitions.__index = acquisitions;

function acquisitions.New(emit)
    return setmetatable({ emit = emit, itemsDirty = true, keysDirty = true, moves = {} }, acquisitions);
end

function acquisitions:Reset()
    self.items, self.owned, self.keys = nil, nil, nil;
    self.itemsDirty, self.keysDirty = true, true;
    self.moves = {};
end

function acquisitions:Packet(id, data)
    if id == 0x00A or id == 0x00B then
        self:Reset();
        self.loading = false;
    elseif id == 0x01D or id == 0x01E or id == 0x01F or id == 0x020 then
        self.itemsDirty = true;
        -- Initial container sync may take longer than the status settle timer.
        if id == 0x01D and type(data) == 'string' and #data >= 5 then
            if data:byte(5) == 0 then
                self.loading = true;
            elseif data:byte(5) == 1 and self.loading then
                self.loading = false;
                self.items, self.owned = nil, nil; -- completed sync is a baseline
            end
        end
    elseif id == 0x055 then
        self.keysDirty = true;
    end
end

-- Track explicit moves into Inventory as well: their two bag updates can arrive
-- on different frames, making an ownership delta alone insufficient.
function acquisitions:Outgoing(id, data, memory)
    if id ~= 0x029 or type(data) ~= 'string' or #data < 12 then return; end
    local source, destination, slot = data:byte(9, 11);
    if source == 0 or destination ~= 0 then return; end
    local item = memory:GetInventory():GetContainerItem(source, slot);
    if not item or item.Id == 0 or item.Count <= 0 then return; end
    local count = 0;
    for i = 8, 5, -1 do count = count * 256 + data:byte(i); end
    if count == 0 then count = item.Count; end -- move all
    self.moves[#self.moves + 1] = { id = item.Id, count = math.min(count, item.Count), expires = os.clock() + 10 };
end

function acquisitions:Update(memory, baseline)
    local inventory, player = memory:GetInventory(), memory:GetPlayer();
    local now = os.clock();
    for i = #self.moves, 1, -1 do
        if self.moves[i].expires <= now then table.remove(self.moves, i); end
    end
    if self.itemsDirty or baseline then
        local main, owned = {}, {};
        for bag = 0, 17 do
            for slot = 1, inventory:GetContainerCountMax(bag) do
                local item = inventory:GetContainerItem(bag, slot);
                if item and item.Id > 0 and item.Count > 0 then
                    owned[item.Id] = (owned[item.Id] or 0) + item.Count;
                    if bag == 0 then main[item.Id] = (main[item.Id] or 0) + item.Count; end
                end
            end
        end
        if self.items and not baseline and not self.loading then
            for id, count in pairs(main) do
                local increase = math.max(0, count - (self.items[id] or 0));
                local transferred = 0;
                for _, move in ipairs(self.moves) do
                    if move.id == id then
                        local used = math.min(increase - transferred, move.count);
                        move.count, transferred = move.count - used, transferred + used;
                    end
                end
                local gained = math.min(increase - transferred, (owned[id] or 0) - (self.owned[id] or 0));
                if gained > 0 then self.emit(id, gained, false); end
            end
        end
        self.items, self.owned, self.itemsDirty = main, owned, false;
    end
    if self.keysDirty or baseline then
        local keys = {};
        for id = 0, 4095 do
            if player:HasKeyItem(id) then
                keys[id] = true;
                if self.keys and not baseline and not self.keys[id] then self.emit(id, 1, true); end
            end
        end
        self.keys, self.keysDirty = keys, false;
    end
end

return acquisitions;
