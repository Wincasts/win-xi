-- Independent compact-log activity, sizing and opacity. Never removes retained history.
local model = require('log')
local M = {}
function M.Defaults()
    return { resize = { false }, animate = { false }, resizeDuration = { 0.2 }, fade = { false }, idle = { 15 }, duration = { 1 }, minimum = { 0 } }
end
local function Number(value, fallback, low, high)
    local number = tonumber(type(value) == 'table' and value[1])
    if not number or number ~= number then number = fallback end
    return math.max(low, math.min(high, number))
end
function M.Complete(options)
    if type(options) ~= 'table' then options = {} end
    for _, key in ipairs({ 'window1', 'window2' }) do
        local value = type(options[key]) == 'table' and options[key] or M.Defaults()
        for _, flag in ipairs({ 'resize', 'animate', 'fade' }) do
            value[flag] = { type(value[flag]) == 'table' and value[flag][1] == true }
        end
        value.idle = { math.floor(Number(value.idle, 15, 1, 300)) }
        value.duration = { Number(value.duration, 1, 0.1, 10) }
        value.resizeDuration = { Number(value.resizeDuration, 0.2, 0.05, 2) }
        value.minimum = { math.floor(Number(value.minimum, 0, 0, 50)) }
        options[key] = value
    end
    return options
end
function M.Apply(state, options, history, filter, box, maximum, now, active, measure)
    if not box then state.height, state.resizeTarget = nil, nil; return nil, maximum, 1 end
    options = options or M.Defaults()
    local resize, fade = options.resize and options.resize[1], options.fade and options.fade[1]
    if not resize and not fade then
        state.alpha, state.time, state.height, state.resizeTarget = 1, now, nil, nil
        return box, maximum, 1
    end
    local idle = Number(options.idle, 15, 1, 300)
    local recent, latest = {}, nil
    for _, message in ipairs(history.messages) do
        if not filter or filter(message) then
            -- Imported history has time zero, not new-message activity.
            if message.time > 0 and message.time <= now then
                latest = math.max(latest or message.time, message.time)
                if now - message.time < idle then recent[#recent + 1] = message end
            end
        end
    end
    if active then state.lastActive = now end
    latest = math.max(latest or -math.huge, state.lastActive or -math.huge)
    local awake = active or now - latest < idle
    local elapsed = state.time and math.max(0, now - state.time) or 0
    if not awake then elapsed = math.min(elapsed, math.max(0, now - latest - idle)) end
    local target = awake and 1 or 0
    local alpha = state.alpha or target
    if not fade or active then alpha = 1
    elseif target > alpha then alpha = math.min(1, alpha + elapsed / 0.2)
    else alpha = math.max(target, alpha - elapsed / Number(options.duration, 1, 0.1, 10)) end
    state.alpha, state.time = alpha, now
    local rows = maximum
    if resize and not active then
        local minimum = math.floor(Number(options.minimum, 0, 0, 50))
        local count = 0
        if #recent > 0 then
            -- Reuse wrapping until activity, routing or the recent-message boundary changes.
            if state.revision ~= history.revision or state.first ~= recent[1] or state.last ~= recent[#recent] or state.filter ~= filter then
                state.log = { messages = recent, revision = history.revision }
                state.revision, state.first, state.last, state.filter = history.revision, recent[1], recent[#recent], filter
            end
            count = measure(state.log)
        end
        rows = math.min(maximum, math.max(minimum, count))
    end
    -- With both options enabled, keep the last rows long enough to actually fade out.
    if resize and fade and rows == 0 and alpha > 0.01 then rows = math.min(maximum, math.max(1, state.rows or 1)) end
    state.rows = rows
    local height = rows < 1 and 0 or (rows == maximum and box.height or measure(nil, rows))
    local animate = resize and options.animate and options.animate[1] and not active and alpha > 0.01
    if animate then
        if state.height == nil then state.height = height end
        if state.resizeTarget ~= height then
            state.resizeFrom, state.resizeStart, state.resizeTarget = state.height, now, height
            state.resizeRows = math.min(maximum, math.max(rows, state.displayRows or rows))
        end
        local progress = math.max(0, math.min(1, (now - state.resizeStart) / Number(options.resizeDuration, 0.2, 0.05, 2)))
        local eased = progress * progress * (3 - 2 * progress)
        height = state.resizeFrom + (height - state.resizeFrom) * eased
        if progress < 1 then rows = state.resizeRows end
    else
        state.resizeTarget = nil
    end
    state.height, state.displayRows = height, rows
    if alpha <= 0.01 then
        state.height, state.resizeTarget = 0, nil
        return nil, rows, alpha
    end
    if height < 0.01 or rows < 1 then return nil, rows, alpha end
    if height ~= box.height or rows ~= maximum then
        local result = {}
        for k, v in pairs(box) do result[k] = v end
        result.height = height
        result.top, result.rows = result.bottom - result.height, rows
        box = result
    end
    return box, rows, alpha
end
return M
