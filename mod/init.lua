-- myCraftCivi Mod Initialisierung
-- Hier werden alle NPCs und Hilfsfunktionen geladen.

local modpath = core.get_modpath("mycraftcivi")

-- 1. Hilfsfunktionen laden
dofile(modpath .. "/common.lua")

-- 2. NPCs laden
dofile(modpath .. "/lumberjack.lua")

-- HIER können später weitere NPCs hinzugefügt werden:
-- dofile(modpath .. "/miner.lua")
-- dofile(modpath .. "/farmer.lua")

core.log("action", "[mycraftcivi] Mod geladen!")
