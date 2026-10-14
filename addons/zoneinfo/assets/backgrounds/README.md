# Banner backgrounds

Place your own PNG, JPG/JPEG or BMP images here. Transparent PNGs are recommended.
The only artwork bundled is the nation flags in `flags/`, shown in a nation's own
regions when Use Region Flags is on (see the addon's README).

In `/zoneinfo config` → **Appearance → Background Image**, enable the image and
enter its filename (for example `banner.png`, not a full path). Set the size,
offset and opacity, then use a banner preview. Images stretch to the chosen size.
Reload Background Image refreshes an image replaced under the same filename.

The image follows banner alignment, position, visibility and fade in both the
ImGui and experimental GDI renderers. Settings are saved per character. A missing
or unreadable image leaves the text banner usable and reports an error in settings.
