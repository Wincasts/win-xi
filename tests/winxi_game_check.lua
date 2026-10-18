-- winxi.game on its own: the menu on top is read once for as long as it stays, and whether it is the
-- map is worked out once for each name, as both are asked every frame
local game = require('winxi.game')
local header, name, reads = 0x1000, 'menu    map     \0\0', 0
ashita.memory.find = function() return 0x400000 end
ashita.memory.read_uint32 = function(at) if at == 0x1004 then return header end return 0x1000 end
ashita.memory.read_string = function() reads = reads + 1; return name end

H.print('the map on top, its zeros gone', game.MenuName() == 'menu    map     ', game.IsMapOpen())
game.IsHidden({ UnderMap = true }); game.IsHidden({ UnderMap = true })
H.print('read once while it stays', reads == 1)
header, name = 0x2000, 'menu    inventor'
H.print('another menu: read again, not the map', game.MenuName() == 'menu    inventor', game.IsMapOpen() == false, reads == 2)
header, name = 0x1000, 'menu    map     \0\0'
H.print('the map again: read again, and the map', game.IsMapOpen(), reads == 3)
header = 0
H.print('no menu on top: nothing, and nothing read', game.MenuName() == '', game.IsMapOpen() == false, reads == 3)
