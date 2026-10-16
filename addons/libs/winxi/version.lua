-- winxi.version: which winxi this is.
--
-- Each addon is released on its own, with its own copy of winxi, so installing one addon can put an
-- older winxi over the one another addon came with. Every addon that is released checks, as it loads,
-- that the winxi it finds is at least the one it was made with, and says so plainly if it is not:
--
--     local winxiNeeded = 1; -- winxi.version's Number this addon was made with
--     do
--         local ok, found = pcall(require, 'winxi.version');
--         local number = ok and type(found) == 'table' and found.Number or 0;
--         if number < winxiNeeded then
--             local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number);
--             print(('\30\68[%s]\30\01 %s'):format(addon.name, text));
--             error(text, 0);
--         end
--     end
--
-- (pcall, because a winxi from before this file has none.)
--
-- Number goes up by one whenever winxi gains something an addon may come to rely on: a function, an
-- option, a setting. An addon that starts using it sets its winxiNeeded to the new Number. winxi
-- keeps what it had, so a newer winxi serves every older addon.
-- 2, 3: fonts.Texture as it was tried, given only to testers
-- 4: fonts.Texture gives the plugins' mark for imgui's font texture, fonts.TextureMark,
--    fonts.TextureDetail
return {
    Number = 4,
};
