-- Clock keeps its existing icon-set directory; chatbox uses the shared panel icons.
local icons = require('winxi.infopanel.icons')
icons.Root(('%s\\addons\\clock\\icons\\'):format(AshitaCore:GetInstallPath()))
return icons
