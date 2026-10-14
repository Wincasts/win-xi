-- Visually transcribed from decoded XICombinedMaps-2048 rasters, not Phoenix spawn data.
-- Proposed names are descriptive addon labels, NOT official FFXI sub-zone names.
-- map_x/map_y: approximate leader-line endpoints/marker centers in 0..512 image space,
-- origin top-left, x right, y down. NOT world coordinates or text-box positions.
-- candidate_radius: suggested map-space proximity radius, not a verified area boundary.
-- Requires the correct map and a calibrated world-to-map transform before runtime use.
return {
    zone_id = 190,
    zone_name = "King Ranperre's Tomb",
    source_pack = 'XICombinedMaps-2048',
    extraction_method = 'DXT3 decode with Pillow; visual transcription and leader-line review',
    coordinate_space = 'map_image_512',
    official_subzone_names = false,
    world_calibrated = false,
    maps = {
        {
            id = 'map_1',
            dat = 'ROM/18/11.DAT',
            texture = 'm_190_01',
            width = 2048, height = 2048,
            duplicate_dat = 'ROM/18/13.DAT',
            raw_labels = {
                'East Ronfaure', 'Jugner Forest', 'Goblin Gruel', 'Crypt Ghost',
                'Cemetery Cherry', 'Corrupted Soffeil', 'Corrupted Ulbrig',
                'Corrupted Yorgos', 'Spook', 'Tomb Stone',
            },
        },
        {
            id = 'map_2',
            dat = 'ROM/18/12.DAT',
            texture = 'm_190_02',
            width = 2048, height = 2048,
            raw_labels = { 'Strange Apparatus', 'Cemetery Cherry', 'Vrtra' },
        },
        {
            id = 'apparatus_fragment',
            dat = 'ROM/18/8.DAT',
            texture = 'm_190_14',
            width = 2048, height = 2048,
            raw_labels = {}, -- Only zone title/grid; no named landmark text on this fragment.
            note = 'Visually matches the western apparatus branch of map 2.',
        },
    },
    candidate_areas = {
        {
            id = 'tomb_stone_chamber', map = 'map_1',
            name = 'Tomb Stone Chamber',
            source_labels = { 'Tomb Stone', 'Spook' },
            map_x = 272, map_y = 312, candidate_radius = 16,
            kind = 'landmark_chamber',
            note = 'Both leader lines point to the eastern chamber in the southern rectangular complex.',
        },
        {
            id = 'goblin_gruel_grotto', map = 'map_1',
            name = 'Goblin Gruel Grotto',
            source_labels = { 'Goblin Gruel' },
            map_x = 249, map_y = 206, candidate_radius = 14,
            kind = 'mob_landmark',
            note = 'Circled northern-central pocket; Grotto is a proposed descriptor, not map text.',
        },
        {
            id = 'crypt_ghost_passage', map = 'map_1',
            name = 'Crypt Ghost Passage',
            source_labels = { 'Crypt Ghost' },
            map_x = 231, map_y = 249, candidate_radius = 14,
            kind = 'mob_landmark',
            note = 'Circled western-central passage/chamber.',
        },
        {
            id = 'cemetery_cherry_upper', map = 'map_1',
            name = 'Cemetery Cherry Passage (Map 1)',
            source_labels = {
                'Cemetery Cherry', 'Corrupted Soffeil', 'Corrupted Ulbrig', 'Corrupted Yorgos',
            },
            map_x = 264, map_y = 260, candidate_radius = 14,
            kind = 'mob_landmark',
            note = 'Shared label group points to one circled area, not four separately located POIs.',
        },
        {
            id = 'ronfaure_west_approach', map = 'map_1',
            name = 'East Ronfaure Approach (West Entrance)',
            source_labels = { 'East Ronfaure' },
            map_x = 220, map_y = 167, candidate_radius = 18,
            kind = 'exit_approach',
            note = 'Western northbound exit/rectangular entrance hall. Destination, not a KRT area name.',
        },
        {
            id = 'ronfaure_east_approach', map = 'map_1',
            name = 'East Ronfaure Approach (East Entrance)',
            source_labels = { 'East Ronfaure' },
            map_x = 296, map_y = 166, candidate_radius = 14,
            kind = 'exit_approach',
            note = 'Second northbound exit branch.',
        },
        {
            id = 'jugner_approach', map = 'map_1',
            name = 'Jugner Forest Approach',
            source_labels = { 'Jugner Forest' },
            map_x = 340, map_y = 150, candidate_radius = 14,
            kind = 'exit_approach',
            note = 'Northeastern corridor heading east toward the exit arrow.',
        },
        {
            id = 'strange_apparatus_alcove', map = 'map_2',
            name = 'Strange Apparatus Alcove',
            source_labels = { 'Strange Apparatus' },
            map_x = 152, map_y = 217, candidate_radius = 12,
            kind = 'landmark_chamber',
            note = 'Blue marker at the dead end of the western branch.',
        },
        {
            id = 'cemetery_cherry_lower', map = 'map_2',
            name = 'Cemetery Cherry Chamber (Map 2)',
            source_labels = { 'Cemetery Cherry' },
            map_x = 263, map_y = 267, candidate_radius = 18,
            kind = 'mob_landmark',
            note = 'Circled central rectangular chamber. Same mob label also occurs on map 1.',
        },
        {
            id = 'vrtra_chamber', map = 'map_2',
            name = 'Vrtra Chamber',
            source_labels = { 'Vrtra' },
            map_x = 345, map_y = 282, candidate_radius = 20,
            kind = 'mob_landmark',
            note = 'Large circled chamber at the eastern dead end.',
        },
    },
}
