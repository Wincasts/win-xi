-- Pure presentation timing/content. Detection and editor state are independent.
local M = {};

function M.alpha(started, now, options)
    if not started then return 0; end
    local age = math.max(0, now - started);
    local hold, fade = options.hold[1], options.fadeOut[1];
    if age >= hold + fade then return 0; end
    -- Fade-in is part of hold; fade-out begins after hold ends.
    local enter = math.min(options.fadeIn[1], hold);
    local alpha = enter > 0 and math.min(1, age / enter) or 1;
    if age > hold and fade > 0 then alpha = alpha * math.max(0, 1 - (age - hold) / fade); end
    return alpha * options.opacity[1];
end

function M.rows(state, tracking, options)
    local rows = {};
    local function add(words, title, key)
        if words and words ~= '' then
            rows[#rows + 1] = { words = words, title = title or false, key = key };
        end
    end

    -- Retain legacy option fallbacks for callers with pre-per-popup settings.
    local zone_region = options.zoneRegion or options.region;
    local zone_weather = options.zoneWeather or options.weather;
    local area_context = options.areaZoneContext or options.zoneContext;
    local area_weather = options.areaWeather or options.weather;
    local area_experimental = options.areaExperimental or options.experimental;
    -- The Vana'diel day and time the popup started at, where it is wanted: 'Firesday 14:20'.
    local function day_time(key)
        if options[key] and options[key][1] and state.vana then add(state.vana, false, key); end
    end

    -- A change of weather: the weather itself as the title, in the sub-zone popup's style.
    if state.banner_is_weather then
        add(state.title, true, 'areaTitle');
        if area_context[1] then add(state.zone_title, false, 'areaContext'); end
        day_time('areaDayTime');
        return rows;
    end

    if (not state.banner_is_area and zone_region[1]) then add(state.region, false, 'zoneRegion'); end
    add(state.title, true, state.banner_is_area and 'areaTitle' or 'zoneTitle');
    if state.banner_is_area then
        local context = area_context[1] and state.zone_title or '';
        if area_experimental[1] then
            context = context ~= '' and (context .. ' (Experimental Area)') or 'Experimental Area';
        end
        add(context, false, 'areaContext');
    end
    if ((state.banner_is_area and area_weather[1]) or (not state.banner_is_area and zone_weather[1])) then
        add('Weather: ' .. state.weather, false, state.banner_is_area and 'areaWeather' or 'zoneWeather');
    end
    day_time(state.banner_is_area and 'areaDayTime' or 'zoneDayTime');
    return rows;
end

return M;
