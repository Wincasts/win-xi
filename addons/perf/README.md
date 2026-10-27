# perf 0.2

What each addon costs a frame, live: the time its event handlers take, one row an addon, so a change
of settings can be seen for what it is. Every winxi addon reports (winxi 63's `winxi.perf`, which
`winxi.shell` loads; damage, party and targetlines load it themselves); a third-party addon reports
after one line, `pcall(require, 'winxi.perf')`, before it registers its events.

```text
/addon load perf
/perf                 shows or hides the window
/perf mark [name]     keeps this moment's numbers; the table then shows Was and Change for each addon
/perf mark clear      forgets them
/perf reset           starts the longest calls over
/perf config          the settings
```

The top line is the frame: how long one took from one present to the next over the Sample Window,
the rate that makes, and how much of it all the addons' handlers took together. The table, costliest
first:

- Present: milliseconds a frame in the addon's `d3d_present` handler.
- Longest: the longest single handler call seen, in milliseconds, since the addon loaded or `/perf reset`.
- Packets and Packets/s: milliseconds a frame in `packet_in` and `packet_out`, and how many a second.
- Other: `text_in`, `command`, the keys, mouse and controller, and anything else.
- Total: all of it.

To weigh a setting: `/perf mark before`, change the setting, wait a Sample Window or two, and read
Change. Settings: Visible, Lock Window and Position under Window; Sample Window (1 to 10 s), Show Idle Addons
and Show Packet Columns under Readings.

It is CPU time inside the handlers. What an addon draws is drawn by Ashita after the handlers, and
the GPU's share is in the frame but in no row; a setting that draws more shows up in the frame time
more than in its addon's row. Plugins are not rows; truefps shows their time with the addons' as one.
