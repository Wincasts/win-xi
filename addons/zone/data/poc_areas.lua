-- Experimental, manually traced feature envelopes on XICombinedMaps-2048 rasters.
-- These are conservative FEATURE polygons, NOT verified boundaries or official subzones.
-- Runtime expands them with a world-distance approach buffer (default 30 yalms).
-- Keep the feature footprints here; tune approach distance rather than inflating these vertices.
-- Coordinates: 0..512 image space, top-left origin. No world coordinates are guessed.
-- Single-map outdoor zones only; map table indices from Boussole zonesFloors.lua.
return {
    [100] = {
        name = 'West Ronfaure', table_index = 0, floor_id = 0,
        texture = 'm_100_00', dat = 'ROM/17/24.DAT', image = 'maps/100.png',
        areas = {
            { id = 'knightwell', name = 'Knightwell', polygon = {
                { 226, 331 }, { 237, 330 }, { 250, 334 }, { 251, 340 },
                { 241, 344 }, { 231, 341 }, { 225, 337 },
            } },
        },
    },
    [103] = {
        name = 'Valkurm Dunes', table_index = 3, floor_id = 0,
        texture = 'm_103_00', dat = 'ROM/17/27.DAT', image = 'maps/103.png',
        areas = {
            { id = 'secret_sands', name = 'Secret Sands', polygon = {
                { 42, 208 }, { 64, 211 }, { 78, 223 }, { 73, 238 },
                { 55, 247 }, { 33, 239 }, { 34, 219 },
            } },
            { id = 'whitebone_sands', name = 'Whitebone Sands', polygon = {
                { 148, 275 }, { 179, 282 }, { 182, 309 }, { 166, 319 },
                { 148, 315 }, { 141, 292 },
            } },
            { id = 'siren_sands', name = 'Siren Sands', polygon = {
                { 270, 275 }, { 299, 281 }, { 303, 304 }, { 291, 318 },
                { 268, 323 }, { 260, 308 },
            } },
        },
    },
    [107] = {
        name = 'South Gustaberg', table_index = 7, floor_id = 0,
        texture = 'm_107_00', dat = 'ROM/17/31.DAT', image = 'maps/107.png',
        areas = {
            { id = 'fumaroles', name = 'The Fumaroles', polygon = {
                { 132, 248 }, { 163, 247 }, { 172, 258 }, { 165, 279 },
                { 145, 286 }, { 127, 279 },
            } },
            { id = 'vomp_hill', name = 'Vomp Hill', polygon = {
                { 279, 236 }, { 303, 232 }, { 327, 245 }, { 331, 270 },
                { 313, 289 }, { 288, 298 }, { 266, 282 }, { 264, 258 },
            } },
            { id = 'morhen_lighthouse', name = 'Morhen Lighthouse', polygon = {
                { 398, 299 }, { 407, 299 }, { 413, 309 }, { 411, 319 },
                { 402, 324 }, { 396, 315 },
            } },
        },
    },
}
