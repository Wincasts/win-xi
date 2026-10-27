# d3dcount 0.1

A diagnostic. Counts the d3d8 device's `SetLight`, `LightEnable`, `BeginStateBlock`, `EndStateBlock`,
`ApplyStateBlock`, `CaptureStateBlock`, `DeleteStateBlock`, `CreateStateBlock` and `Reset` calls a
frame, with the module and offset of each caller, by patching the device's vtable. `SetLight` is also
counted by light index, `LightEnable` by index and on or off, `CreateStateBlock` by type.

```text
/load d3dcount
/d3dcount             last frame's counts and the totals since load, in the chat and Ashita's log
/d3dcount reset       zero the totals
```

Written for the light record leak of 2026-10-27 (see [blockpool](../blockpool)): it showed one
`CreateStateBlock(ALL)` a frame from Ashita's core and one more for every font object drawn, and the
leak following that count. Unload it before unloading any plugin loaded after it that patches the
same slots, or it stays loaded with its slots left in place.
