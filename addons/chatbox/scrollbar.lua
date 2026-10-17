-- Scroll offsets count visual rows back from the newest (zero is the bottom).
-- Match inventory's 2px white thumb, 2px content gap and hover/drag highlight.
local M = {Width=2, Reserve=4, White={1,1,1,0.35}, Bright={1,1,1,0.7}}
function M.Layout(left, top, bottom, total, visible, offset)
    local maximum = math.max(0,total-visible)
    local height = bottom-top
    if maximum == 0 or height <= 0 then return nil end
    local thumb = math.min(height, math.max(8,height*visible/total))
    local travel = height-thumb
    offset = math.max(0,math.min(maximum,offset))
    local y = top + travel*(1-offset/maximum)
    return {left=left,right=left+M.Width,zoneLeft=left-2,zoneRight=left+M.Width+3,
        top=top,bottom=bottom,thumbTop=y,thumbBottom=y+thumb,
        travel=travel,maximum=maximum,offset=offset,page=visible}
end
function M.Hit(bar,x,y)
    return bar and x and y and x>=bar.zoneLeft and x<bar.zoneRight and y>=bar.top and y<bar.bottom
end
function M.Drag(bar,y,grab)
    if bar.travel <= 0 then return bar.offset end
    local fraction = math.max(0,math.min(1,(y-grab-bar.top)/bar.travel))
    return math.floor(bar.maximum*(1-fraction)+0.5)
end
function M.Page(bar,y)
    return math.max(0,math.min(bar.maximum,bar.offset + (y<bar.thumbTop and bar.page or -bar.page)))
end
return M
