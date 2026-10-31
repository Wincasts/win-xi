-- How thick a name's dark edge is, and how solid, shared by its text, icons and bars.
--
--   outline.Of(width, size, scale, fit) -> radius, weight
--       width  the chosen thickness, None (0) to 3 px; size the name's size now, scale the render
--       target's; fit how far it has shrunk (1 at its largest). The radius is whole render-target
--       pixels as at the name's largest, no thicker than its letters allow, and stays so with
--       distance: a distant name's edge fades instead (weight 1 to 0), as solid as the thinner edge
--       it would have been, so it never steps from one thickness to the next.
local outline = {};

function outline.Of(width, size, scale, fit)
    if width <= 0 then return 0, 1; end
    fit = math.max(0, math.min(1, fit or 1));
    local largest = fit < 1 and fit > 0 and size / fit or size;
    local radius = math.max(1, math.floor(math.min(width, math.max(1, math.floor(largest / 8 + 0.5))) * scale));
    return radius, math.max(1, radius * fit) / radius;
end

return outline;
