-- civi_core: init.lua
-- Standalone Luanti Game – kein minetest_game benötigt

print("[myCraftCivi] Lade civi_core...")

-- =========================================================
-- SPAWN-SYSTEM: Spieler sicher auf dem Boden platzieren
-- =========================================================

local function find_ground(pos)
    -- Nach unten suchen bis auf einen festen Block getroffen wird
    local p = {x = pos.x, y = pos.y, z = pos.z}
    for i = 1, 200 do
        p.y = pos.y - i
        local node = minetest.get_node_or_nil(p)
        if node and node.name ~= "air" and node.name ~= "ignore" and
           node.name ~= "civi_core:water_source" and node.name ~= "civi_core:water_flowing" then
            return {x = p.x, y = p.y + 2, z = p.z}  -- 2 Blöcke über dem Boden
        end
    end
    return nil
end

local function safe_spawn(player)
    -- Mapgen kurz warten lassen, dann Spawn-Position suchen
    minetest.after(0.5, function()
        if not player or not player:is_valid() then return end
        local pos = player:get_pos()
        -- Erzeuge Terrain an Spawn-Position
        minetest.emerge_area(
            {x = pos.x - 16, y = pos.y - 64, z = pos.z - 16},
            {x = pos.x + 16, y = pos.y + 16, z = pos.z + 16},
            function()
                minetest.after(0.5, function()
                    if not player or not player:is_valid() then return end
                    local ground = find_ground({x = pos.x, y = pos.y + 50, z = pos.z})
                    if ground then
                        player:set_pos(ground)
                    else
                        -- Fallback: Setze an bekannte sichere Höhe
                        player:set_pos({x = pos.x, y = 10, z = pos.z})
                    end
                end)
            end
        )
    end)
end

minetest.register_on_newplayer(function(player)
    safe_spawn(player)
end)

minetest.register_on_respawnplayer(function(player)
    safe_spawn(player)
    return true  -- true = wir übernehmen den Respawn selbst
end)

-- Fallschaden deaktivieren (optional, zum Testen komfortabler)
minetest.register_on_player_hpchange(function(player, hp_change, reason)
    if reason and reason.type == "fall" then
        return 0  -- Keinen Fallschaden
    end
    return hp_change
end, true)

-- =========================================================
-- 1. TERRAIN-BLÖCKE (werden vom Welt-Generator benötigt)
-- =========================================================

minetest.register_node("civi_core:stone", {
    description = "Stein",
    tiles = {"civi_stone.png"},
    groups = {cracky = 3, stone = 1},
})

minetest.register_node("civi_core:dirt", {
    description = "Erde",
    tiles = {"civi_dirt.png"},
    groups = {crumbly = 3, soil = 1},
})

minetest.register_node("civi_core:dirt_with_grass", {
    description = "Erde mit Gras",
    tiles = {"civi_grass.png", "civi_dirt.png", "civi_grass_side.png"},
    groups = {crumbly = 3, soil = 1},
})

minetest.register_node("civi_core:water_source", {
    description = "Wasser (stehend)",
    drawtype = "liquid",
    tiles = {"civi_water.png"},
    alpha = 160,
    paramtype = "light",
    walkable = false,
    pointable = false,
    diggable = false,
    buildable_to = true,
    is_ground_content = false,
    liquidtype = "source",
    liquid_alternative_flowing = "civi_core:water_flowing",
    liquid_alternative_source = "civi_core:water_source",
    liquid_viscosity = 1,
    groups = {water = 3, liquid = 3},
})

minetest.register_node("civi_core:water_flowing", {
    description = "Wasser (fließend)",
    drawtype = "flowingliquid",
    tiles = {"civi_water.png"},
    alpha = 160,
    paramtype = "light",
    paramtype2 = "flowingliquid",
    walkable = false,
    pointable = false,
    diggable = false,
    buildable_to = true,
    is_ground_content = false,
    liquidtype = "flowing",
    liquid_alternative_flowing = "civi_core:water_flowing",
    liquid_alternative_source = "civi_core:water_source",
    liquid_viscosity = 1,
    groups = {water = 3, liquid = 3, not_in_creative_inventory = 1},
    special_tiles = {{name = "civi_water.png", backface_culling = false}},
})

-- =========================================================
-- 2. MAPGEN-ALIASES (sagen dem Weltgenerator welche Blöcke
--    er für Boden, Stein und Wasser verwenden soll)
-- =========================================================

minetest.register_alias("mapgen_stone",          "civi_core:stone")
minetest.register_alias("mapgen_dirt",           "civi_core:dirt")
minetest.register_alias("mapgen_dirt_with_grass","civi_core:dirt_with_grass")
minetest.register_alias("mapgen_water_source",   "civi_core:water_source")

-- =========================================================
-- 3. DER ASPHALT-BLOCK (Kern-Feature)
-- =========================================================

minetest.register_node("civi_core:asphalt", {
    description = "Civi-Asphalt (Speed: 1.8x)",
    tiles = {"civi_asphalt.png"},
    groups = {cracky = 2, stone = 1},
})

-- =========================================================
-- 4. SPEED-LOGIK: Schneller auf Asphalt
-- =========================================================

minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local pos = player:get_pos()
        pos.y = pos.y - 0.5
        local node = minetest.get_node_or_nil(pos)
        if node and node.name == "civi_core:asphalt" then
            player:set_physics_override({speed = 1.8})
        else
            player:set_physics_override({speed = 1.0})
        end
    end
end)

print("[myCraftCivi] civi_core erfolgreich geladen!")