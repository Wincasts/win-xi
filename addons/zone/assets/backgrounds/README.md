# Banner backgrounds

Put your own pictures in this folder to show them behind the zone addon's banner (the name that shows
when you enter an area). PNG, JPG/JPEG and BMP files work. PNG files with a transparent background
look best. The only pictures that come with the addon are the nation flags in `flags/`. They show in
a nation's own regions when **Use Region Flags** is on (see the zone addon's README).

## Using a picture

1. Type `/zone` to open the settings, and go to the **Appearance** tab.
2. Open the **Flag And Background Image** section. It is there only while a banner style is
   **Classic Text**.
3. Turn on **Show Background Image**.
4. In **Image Filename**, type the file's name only, for example `banner.png`, not the full path.
5. Set **Image Size**, **Image Offset** and **Image Opacity** (how solid the picture is).
6. Use one of the preview buttons to see the banner.

The picture is stretched to the size you choose. If you replace a picture with a new file of the same
name, press **Reload Background Image** to see it.

The picture follows the banner's alignment, position, visibility and fade. This works with both text
renderers (ways of drawing the text): ImGui and the experimental GDI Fonts. Settings are saved for
each character. If the picture is missing or cannot be read, the banner still shows its text, and the
settings show an error.
