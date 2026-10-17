-- One layout for the native-backed log and input. Native animation moves the base anchor;
-- only clamp above the input, never subtract its height from an already-lifted log a second time.
local M = {}
function M.New() return {} end
local function Valid(rect, sw, sh)
    if type(rect) ~= 'table' or #rect ~= 4 then return false end
    for _, n in ipairs(rect) do if type(n) ~= 'number' or n ~= n or math.abs(n)==math.huge then return false end end
    return rect[1]>=0 and rect[2]>=0 and rect[3]<=sw and rect[4]<=sh and rect[3]>rect[1] and rect[4]>rect[2]
end
function M.Arrange(state, primary, input, width, sw, sh, height, padding, match)
    if not Valid(primary,sw,sh) then return nil end
    local nativeWidth=primary[3]-primary[1]
    local source=Valid(input.sourceRect,sw,sh) and input.sourceRect or nil
    if source then
        state.widthRatio=(source[3]-source[1])/nativeWidth
        state.leftRatio=(source[1]-primary[1])/nativeWidth
    end
    local left=primary[1]
    if match then
        width=nativeWidth*(state.widthRatio or 1)
        left=left+nativeWidth*(state.leftRatio or 0)
    end
    width=math.min(width,sw-left)
    if left<0 or width<2*padding+32 then return nil end
    -- Both boxes always share their horizontal edges, including native-size mode.
    input.x,input.width=left,width
    state.left,state.width=left,width -- the expanded log keeps these edges
    if not input.active then state.closedBottom=primary[4] end
    if not (match and input.matched) then
        input.bottom=source and source[4] or state.closedBottom or primary[4]
    end
    local bottom=primary[4]
    if input.active then bottom=math.min(bottom,input.bottom-input.height) end
    if bottom<height then return nil end
    return {left=left,bottom=bottom,width=width,height=height,top=bottom-height}
end
-- Whole rows of text that fit in a box of this height, inside its padding.
function M.Fit(height, fontSize, padding, gap)
    if type(height) ~= 'number' or height ~= height then return 0 end
    return math.max(0, math.floor((height - 2 * padding + gap) / (fontSize + gap)))
end
-- As the game's log expands: the compact box grows to the native full log's top and bottom, keeping
-- its own left edge and width (the native full-log's until a compact box has been laid out). Every
-- whole row below the title's headroom is history; compact state is never changed.
function M.Expanded(state, rect, input, sw, sh, fontSize, padding, gap, headroom)
    if not Valid(rect,sw,sh) then return nil end
    local left,top,width,bottom=rect[1],rect[2],rect[3]-rect[1],rect[4]
    if state.left and state.width then
        left,width=state.left,math.min(state.width,sw-state.left)
    end
    input.x,input.width=left,width
    local height=bottom-top
    local rows=M.Fit(height-(headroom or 0),fontSize,padding,gap)
    if rows<10 or width<2*padding+32 then return nil end
    return {left=left,top=top,bottom=bottom,width=width,height=height,rows=rows}
end
return M
