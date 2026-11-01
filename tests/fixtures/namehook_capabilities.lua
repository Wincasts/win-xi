-- Keep the returned cdata alive for as long as a mocked DLL can be scanned.
local ffi = require('ffi')
local caps = ffi.new('namehook_capabilities_t')
ffi.copy(caps.Magic, 'NAMEHOOKCAPS', 12)
caps.Size, caps.Version, caps.Features, caps.Build = ffi.sizeof(caps), 1, 7 + 64, 135 -- 64: FontEachFrame (namehook 1.52)
return caps
