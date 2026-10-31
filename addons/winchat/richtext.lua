-- UTF-8 byte-range colour metadata; visible text stays free of protocol escapes.
local M = {}
function M.Slice(spans, first, length)
    if not spans then return nil end
    local result = {}
    for _, span in ipairs(spans) do
        local a, b = math.max(first, span.first), math.min(first + length - 1, span.last)
        if a <= b then result[#result + 1] = {first=a-first+1,last=b-first+1,bank=span.bank,slot=span.slot} end
    end
    return #result > 0 and result or nil
end
function M.Insert(spans, after, length)
    if not spans then return nil end
    local result = {}
    for _, s in ipairs(spans) do
        result[#result + 1] = {first=s.first > after and s.first+length or s.first,
            last=s.last > after and s.last+length or s.last,bank=s.bank,slot=s.slot}
    end
    return result
end
-- Replace a range's colour without overlapping source spans; surrounding source colours survive.
function M.Paint(spans, first, last, bank, slot)
    local result = {}
    for _, s in ipairs(spans or {}) do
        if s.last < first or s.first > last then
            result[#result+1] = {first=s.first,last=s.last,bank=s.bank,slot=s.slot}
        else
            if s.first < first then
                result[#result+1] = {first=s.first,last=first-1,bank=s.bank,slot=s.slot}
            end
            if s.last > last then
                result[#result+1] = {first=last+1,last=s.last,bank=s.bank,slot=s.slot}
            end
        end
    end
    result[#result+1] = {first=first,last=last,bank=bank,slot=slot}
    table.sort(result,function(a,b) return a.first < b.first end)
    return result
end
return M
