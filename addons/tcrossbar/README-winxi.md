# tcrossbar (winxi's change)

This folder is not the whole of tcrossbar: it holds only the files of Thorny's addon that differ from, or
are needed to recognise, the copy in the Ashita folder. `controller.lua` has one addition, marked
`winxi:`. While a winxi addon's window has the controller (the `winxi_controller_focus` plugin event),
tcrossbar ignores button presses, so the triggers do not bring up the crossbar and no macro fires behind
the window. `tcrossbar.lua` is unchanged and is here only so that `deploy.sh` knows the folder for an addon.

If tcrossbar is updated, copy the new `controller.lua` and `tcrossbar.lua` here and put the `winxi:`
addition back, or pushing this folder will put the old files over the new.
