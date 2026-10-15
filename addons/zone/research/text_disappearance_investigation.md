# Shared text disappearance investigation

Reported symptom: zone and name both stopped displaying text, with no error
message available. This has not been reproduced in a live Ashita client, so the
original trigger is not established.

## Findings

- Zoneinfo and name both use ImGui fonts. `name/custom.lua` also reads
  `GetFont().ContainerAtlas` for the Direct3D texture used by namehook, and caches
  baked glyph coordinates. Shared font-atlas changes can therefore affect both.
- Zoneinfo's banner pushes a fading Alpha, window styles, ItemSpacing and fonts.
  Previously an exception during glyph measurement or text drawing skipped
  PopFont, PopStyleVar, End and the winxi style cleanup. An unbalanced shared
  ImGui context is a concrete cross-addon failure path.
- The font-size sliders used SliderFloat with a `%.0f` label. That only formats
  the label: it does not round the value. Dragging sizes while previewing could
  request many fractional baked font sizes, increasing shared atlas churn.
- Name already monitors texture ID changes and probes glyph UV changes. Atlas
  availability is read defensively; without a valid texture it returns before
  claiming the game's names. No evidence here establishes a permanent atlas
  failure, GPU resource exhaustion, or a native renderer bug.

## Hardening implemented

- Banner font/ItemSpacing stacks are unwound even when measurement/drawing fails.
- The ordinary winxi window path ends its window and restores its own styles
  before propagating a callback error. Callbacks still own their local stacks;
  this is not a universal unwind for arbitrary addon code or native crashes.
- Font lookup/loading is done before opening the banner window.
- Font sizes are rounded to whole pixels in validation and before baking.
- Zoneinfo reports banner rendering failures with a traceback, rate-limited to
  once every ten seconds, after the guarded cleanup.

## Offline evidence

`zone_presentation_ui_check.lua` injects failures in CalcTextSize and
GetColorU32 while fonts/styles are pushed. Both failures now propagate with
balanced font/style/color stacks; the failed window is ended and the next draw
succeeds. Existing name rendering and menu checks also pass.

These mocks do not validate native font-atlas rebuilding, device loss, memory
pressure or actual addon event ordering. The original in-game cause remains
unconfirmed.

## If it happens again

Record whether it occurred while selecting a font, dragging a size slider,
previewing a popup, zoning, or changing display resolution. Try Default fonts
in zone and name, then unload zone to distinguish banner interference
from a name-only issue. If the shared renderer remains broken after unload,
a client restart may be needed. Capture any new rate-limited zone traceback.
Deploy the shared `addons/libs/winxi/window.lua` change along with zone.
