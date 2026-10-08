-- Shared between the tracker and the renderer: version goes up whenever a line is added, pointed
-- somewhere new or removed, so that work derived from the set of lines is redone only when it changes.
return { version = 0 };
