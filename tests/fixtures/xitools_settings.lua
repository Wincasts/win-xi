-- What xitools saved for a character, cut down to what the addons that left it bring over
require('common');

local settings = T{ };
settings["tools"] = T{ };
settings["tools"]["inv"] = T{ };
settings["tools"]["inv"]["isVisible"] = T{ false };
settings["tools"]["inv"]["isUnified"] = T{ true };
settings["tools"]["inv"]["showEmptySlots"] = T{ true };
settings["tools"]["inv"]["maxHeight"] = T{ 400 };
settings["tools"]["inv"]["pos"] = T{ 30, 675 };
settings["tools"]["inv"]["controller"] = T{ true };
settings["tools"]["inv"]["controllerSounds"] = T{ true };
settings["tools"]["inv"]["controllerInfo"] = "verbose";
settings["tools"]["inv"]["controllerInfoPlace"] = "window";
settings["tools"]["inv"]["controllerType"] = "xinput";
settings["tools"]["inv"]["manualOrder"] = T{ };
settings["tools"]["treas"] = T{ };
settings["tools"]["treas"]["isVisible"] = T{ true };
settings["tools"]["treas"]["showAllSlots"] = T{ false };
settings["tools"]["treas"]["pos"] = T{ 338, 675 };
settings["tools"]["me"] = T{ };
settings["tools"]["me"]["isEnabled"] = T{ true };
settings["tools"]["me"]["name"] = "xitools.me";
settings["tools"]["me"]["pos"] = T{ 12, 34 };
settings["tools"]["tgt"] = T{ };
settings["tools"]["tgt"]["isEnabled"] = T{ false };
settings["tools"]["tgt"]["mainWindow"] = T{ };
settings["tools"]["tgt"]["mainWindow"]["name"] = "xitools.tgt.main";
settings["tools"]["tgt"]["mainWindow"]["pos"] = T{ 56, 78 };
settings["globals"] = T{ };
settings["globals"]["isClickThru"] = T{ true };
settings["globals"]["links"] = T{
    T{ child = "xitools.tgt.main", parent = "xitools.me", side = "below" },
    T{ child = "xitools.tracker", parent = "xitools.me", side = "right" },
};
settings["globals"]["useSharedTheme"] = true;
settings["globals"]["theme"] = T{ };
settings["globals"]["hideUnderMap"] = T{ true };
settings["globals"]["hideUnderChat"] = T{ false };
settings["globals"]["hideWhileLoading"] = T{ true };
settings["globals"]["hideDuringEvent"] = T{ true };
settings["globals"]["hideWithInterface"] = T{ true };
settings["globals"]["fade"] = T{ };
settings["globals"]["fade"]["Enabled"] = true;
settings["globals"]["fade"]["tools"] = T{ };
settings["globals"]["fade"]["tools"]["inv"] = T{ false };
settings["globals"]["fade"]["tools"]["treas"] = T{ true };
settings["globals"]["fade"]["tools"]["me"] = T{ false };

return settings;
