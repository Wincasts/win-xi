-- The colours that mean something, whichever frame they are on
return {
    Blue     = { 0.23, 0.67, 0.91, 1.0 }, -- the member targeted
    Green    = { 0.01, 0.67, 0.07, 1.0 }, -- the member a sub-target or the party cursor is on
    Party    = { 0.90, 0.88, 0.35, 1.0 }, -- a party's: its leader's mark, and an invitation to one
    Alliance = { 0.90, 0.25, 0.22, 1.0 }, -- an alliance's: the same two

    -- the dots by a member's name: who leads the party, who leads the alliance, and the level sync designee
    PartyLeader    = { 1.00, 0.90, 0.25, 1.0 }, -- yellow
    AllianceLeader = { 1.00, 1.00, 1.00, 1.0 }, -- white
    LevelSync      = { 0.95, 0.20, 0.18, 1.0 }, -- red

    -- a target's debuffs, each in the colour of its kind
    StatusGrey   = { 1.00, 1.00, 1.00, 0.5 },
    StatusWhite  = { 0.98, 0.92, 0.84, 1.0 },
    StatusBlack  = { 0.60, 0.20, 0.80, 1.0 },
    StatusYellow = { 0.80, 0.80, 0.80, 1.0 },
    StatusBrown  = { 1.00, 0.96, 0.56, 1.0 },
    StatusGreen  = { 0.60, 0.80, 0.20, 1.0 },
    StatusBlue   = { 0.28, 0.46, 1.00, 1.0 },
    StatusRed    = { 0.80, 0.22, 0.00, 1.0 },
    StatusCyan   = { 0.59, 0.80, 0.80, 1.0 },
}
