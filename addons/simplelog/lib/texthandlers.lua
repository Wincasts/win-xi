local texthandlers = {}

-- Timestamps, an option: the time in front of every line that goes into the chat log, the game's as
-- well as this addon's own. This is what Ashita's timestamp addon (by atom0s) does, done here so that
-- one addon need not be loaded for the other; with both loaded every line is stamped twice.
local stampIgnored = {
	[190] = true, -- NPC chat reinjections
	[600] = true, [702] = true, [909] = true, [919] = true, -- synergy messages
}

local function Stamp(e)
	local mex = bit.band(e.mode_modified, 0xFFFFFF00)
	local mid = bit.band(e.mode_modified, 0x000000FF)
	if stampIgnored[mid] then
		return
	end

	-- NPC chat is not indented under its stamp
	if mid == 150 then
		e.mode_modified = bit.bor(mex, 151)
	end

	-- an indented line is indented by hand, after the stamp
	local stamp = os.date(gProfileSettings.text.timestamp or '[%H:%M:%S]')
	if e.indent then
		e.indent_modified = false
		stamp = stamp .. '  '
	end

	-- auto-translate tags are spelt out first, so that nothing in them is taken for a line break
	local msg = AshitaCore:GetChatManager():ParseAutoTranslate(e.message_modified, true)

	-- every line of the message gets the stamp: it is split at its line breaks, but for one that is
	-- part of a colour code
	local parts = {}
	local start = 1
	local pos = msg:find('[\x0A\x0D]', 1)
	while pos do
		local prev = msg:sub(pos - 1, pos - 1)
		if prev ~= '\x1E' and prev ~= '\x1F' then
			if pos > start then
				parts[#parts + 1] = stamp .. ' ' .. msg:sub(start, pos - 1)
			end
			start = pos + 1
		end
		pos = msg:find('[\x0A\x0D]', pos + 1)
	end
	if start <= #msg then
		parts[#parts + 1] = stamp .. ' ' .. msg:sub(start)
	end
	msg = table.concat(parts, '\n')

	-- NPC chat breaks its lines with the bell character: those get the stamp too
	local spacing = mid == 150 and '   ' or ' '
	msg = msg:gsub('[^\x1E\x1F][\x07]', function (s)
		return s:sub(1, 1) .. '\n' .. stamp .. spacing
	end)

	e.message_modified = msg
end

texthandlers.HandleIncomingText = function(e)
	local redcol = e.mode%256
	
	if (redcol == 121 and gProfileSettings.mode.cancelmultimsg) then
		a,z = string.find(e.message,'Equipment changed')

		if (a and not block_equip) then
			flip_block_equip:once(1)
			--ashita.tasks.once(1, flip_block_equip)
			block_equip = true
		elseif (a and block_cannot) then
			e.blocked = true
			return
		end
	elseif (redcol == 123 and gProfileSettings.mode.cancelmultimsg) then
		a,z = string.find(e.message, 'You were unable to change your equipped items')
		b,z = string.find(e.message, 'You cannot use that command while viewing the chat log')
		c,z = string.find(e.message, 'You must close the currently open window to use that command')
		
		if ((a or b or c) and not block_cannot) then
			flip_block_cannot:once(1)
			--ashita.tasks.once(1, flip_block_cannot)
			block_cannot = true
		elseif ((a or b or c) and block_cannot) then
			e.blocked = true
			return
		end
	end
	
	if (block_modes:contains(e.mode)) then
		local endline = string.char(0x7F, 0x31)
		local item = string.char(0x1E)
		if (not bm_message(e.message)) then
			if (e.message:endswith(endline)) then --allow add_to_chat messages with the modes we blocking
				e.blocked = true
				return
			end
		elseif (e.message:endswith(endline) and string.find(e.message, item)) then --block items action messages
			e.blocked = true
			return
		end
	end

	-- whatever is left goes into the log, with the time in front of it if that is wanted
	if gProfileSettings ~= nil and gProfileSettings.mode.timestamps then
		Stamp(e)
	end
end

function bm_message(original)
    local check = string.char(0x1E)
    local check2 = string.char(0x1F)
    if string.find(original, check) or string.find(original, check2) then
        return true
    end
end

function flip_block_equip()
	block_equip = not block_equip
end

function flip_block_cannot()
	block_cannot = not block_cannot
end

return texthandlers;