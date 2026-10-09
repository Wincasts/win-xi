-- What xilite saved for a character, cut down to what xiframes brings over and a little it does not
require('common');

local settings = T{ };
settings["tools"] = T{ };
settings["tools"]["me"] = T{ isEnabled = T{ true }, name = "xilite.me", pos = T{ 12, 34 } };
settings["tools"]["us"] = T{
    isEnabled = T{ true }, hideWhenSolo = T{ true }, showCastbar = T{ true }, xivParty = T{ true },
    xivScale = T{ 130 }, xivNameSize = T{ 110 }, xivShowTp = T{ false }, xivHpOffset = T{ 2, -3 },
    alliance1 = T{ isCompact = T{ true }, name = "xilite.us.1", pos = T{ 40, 500 }, corner = T{ 40, 700 }, size = T{ 276, -1 } },
};
settings["tools"]["tgt"] = T{ compact = T{ true }, mainWindow = T{ name = "xilite.tgt.main", pos = T{ 56, 78 }, showStatus = T{ true } } };
settings["tools"]["pet"] = T{ isEnabled = T{ true }, showParty = T{ false }, name = "xilite.pet", pos = T{ 5, 6 } };
settings["globals"] = T{ };
settings["globals"]["isClickThru"] = T{ true };
settings["globals"]["useSharedTheme"] = false;
settings["globals"]["hide"] = T{ UnderChat = false, UnderMap = true };
settings["globals"]["fade"] = T{ Enabled = true, tools = T{ us = T{ false }, me = T{ true } } };
settings["globals"]["links"] = T{
    T{ child = "xilite.tgt.main", parent = "xilite.us.1", side = "above" },
    T{ child = "xilite.me", parent = "xilite.us.1", side = "right" },
    T{ child = "xilite.us.2", parent = "xilite.pet", side = "below" },
};

return settings;
