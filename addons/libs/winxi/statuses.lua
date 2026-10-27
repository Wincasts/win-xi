-- Every status effect the server has, by number: Name, Symbol, Flags (erasable, waltzable, ...),
-- Element, Overwrite, WearOff (the message that says it wore off). From the server's data (tools/build_action_data.py).
return require('winxi.catalog').New('statuses');
