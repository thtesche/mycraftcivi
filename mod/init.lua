-- myCraftCivi Mod Initialisierung
-- Hier werden alle NPCs und Hilfsfunktionen geladen.

local modpath = core.get_modpath("mycraftcivi")

-- 1. Hilfsfunktionen laden
dofile(modpath .. "/common.lua")

-- 2. NPCs laden
dofile(modpath .. "/lumberjack.lua")

-- HIER können später weitere NPCs hinzugefügt werden:
dofile(modpath .. "/miner.lua")
-- dofile(modpath .. "/farmer.lua")

minetest.register_chatcommand("checkpile", {
    description = "Prüft die Struktur des Köhlers (Charcoal Pile) nach Techage-Regeln",
    privs = { interact = true },
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        local pos = vector.round(player:get_pos())

        -- Wir suchen den Zünder (brennend oder nicht) ODER fertige Kohle im Umkreis
        local start_pos = minetest.find_node_near(pos, 20, { "techage:lighter", "techage:lighter_burn", "techage:charcoal" })

        if not start_pos then
            return false, "Kein Meiler (Lighter oder fertige Holzkohle) in der Nähe gefunden!"
        end

        local node = minetest.get_node(start_pos)
        
        if node.name == "techage:charcoal" then
            minetest.chat_send_player(name, ">>> Analyse bei " .. minetest.pos_to_string(start_pos) .. " (FERTIGER MEILER)")
            return true, "Der Meiler ist fertig! Du kannst die Holzkohle jetzt abbauen."
        end

        local is_burning = (node.name == "techage:lighter_burn")
        minetest.chat_send_player(name, ">>> Starte Analyse des Köhlers bei " .. minetest.pos_to_string(start_pos) .. (is_burning and " (BRENNT BEREITS)" or " (BEREIT ZUM ZÜNDEN)"))
        
        if is_burning then
            local meta = minetest.get_meta(start_pos)
            local ignite_time = meta:get_int("ignite")
            local is_running = meta:get_int("running")
            
            if is_running == 1 then
                local elapsed = minetest.get_gametime() - ignite_time
                local total_time = 1200 -- 1200 Sekunden = 20 Minuten nach Techage-Originalcode
                local remaining = total_time - elapsed
                
                if remaining > 0 then
                    local min_left = math.floor(remaining / 60)
                    local sec_left = remaining % 60
                    minetest.chat_send_player(name, "Status: Meiler brennt einwandfrei! Verbleibende Zeit: ca. " .. min_left .. " Min " .. sec_left .. " Sek.")
                    return true
                else
                    minetest.chat_send_player(name, "Status: Meiler ist eigentlich fertig, wartet auf Server-Tick zur Umwandlung in Holzkohle.")
                    return true
                end
            else
                minetest.chat_send_player(name, "Status: Lighter brennt, aber Meiler läuft noch NICHT (running=0). Zählt gleich die Struktur...")
            end
        end

        -- Techage Logik exakt nachbauen:
        -- Holz: 3x3x3 um pos (y bis y+2) -> 27 Blöcke, abzüglich 1x Lighter = 26 Holz
        local wood_pos1 = {x=start_pos.x-1, y=start_pos.y, z=start_pos.z-1}
        local wood_pos2 = {x=start_pos.x+1, y=start_pos.y+2, z=start_pos.z+1}
        local wood_nodes = minetest.find_nodes_in_area(wood_pos1, wood_pos2, "group:wood")
        local num_wood = #wood_nodes

        -- Dirt: 5x5x5 um pos (y-1 bis y+3) -> 125 Blöcke
        local dirt_pos1 = {x=start_pos.x-2, y=start_pos.y-1, z=start_pos.z-2}
        local dirt_pos2 = {x=start_pos.x+2, y=start_pos.y+3, z=start_pos.z+2}
        
        -- Techage nutzt techage.aAnyKindOfDirtBlocks
        local dirt_types = "group:crumbly"
        if techage and techage.aAnyKindOfDirtBlocks then
            dirt_types = techage.aAnyKindOfDirtBlocks
        else
            dirt_types = {"default:dirt", "default:dirt_with_grass", "default:dirt_with_dry_grass", "default:dirt_with_snow", "default:dirt_with_rainforest_litter", "default:dirt_with_coniferous_litter"}
        end
        local dirt_nodes = minetest.find_nodes_in_area(dirt_pos1, dirt_pos2, dirt_types)
        local num_dirt = #dirt_nodes

        minetest.chat_send_player(name, "Ergebnis Techage-Zählung:")
        minetest.chat_send_player(name, "- Holz ('group:wood') gefunden: " .. num_wood .. " (Erwartet: 26)")
        minetest.chat_send_player(name, "- Erde gefunden: " .. num_dirt .. " (Erwartet: 98)")

        if num_wood == 26 and num_dirt == 98 then
            return true, "Struktur perfekt nach Techage-Regeln! Der Meiler sollte funktionieren."
        else
            minetest.chat_send_player(name, "WARNUNG: Es gibt Abweichungen!")
            minetest.chat_send_player(name, "1. Techage sucht Erde auch UNTER dem Lighter (y-1).")
            minetest.chat_send_player(name, "2. Stelle sicher, dass du wirklich 'group:wood' nutzt (manche Baumstämme sind nur 'group:tree'!)")
            return false, "Struktur fehlerhaft."
        end
    end,
})

core.log("action", "[mycraftcivi] Mod geladen!")
