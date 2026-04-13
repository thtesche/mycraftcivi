local common = dofile(core.get_modpath("mycraftcivi") .. "/common.lua")

local trunk_to_sapling = {
    ["default:tree"] = "default:sapling",
    ["default:acacia_tree"] = "default:acacia_sapling",
    ["default:aspen_tree"] = "default:aspen_sapling",
    ["default:jungletree"] = "default:jungle_sapling",
    ["default:pine_tree"] = "default:pine_sapling",
}

local lumberjack_count = 0

--- Setzt den Status des NPCs speziell für den Holzfäller.
local function set_state(self, new_state)
    common.set_state(self, "_lumberjack_state", "_lumberjack_id", "Lumberjack", new_state)
end


local function get_soil_y(x, z, start_y)
    for dy = 5, -5, -1 do
        local p = { x = x, y = start_y + dy, z = z }
        local name = core.get_node(p).name
        if core.get_item_group(name, "soil") > 0 or
            core.get_item_group(name, "dirt") > 0 or
            core.get_item_group(name, "sand") > 0 then
            return p.y
        end
    end
    return nil
end


--- Interaktion mit der Truhe (Einlagern von gesammeltem Holz/Items).
local function lumberjack_chest_interaction(self, dtime, pos)
    if self.target_chest then
        local target_node = core.get_node(self.target_chest)
        local tname = target_node.name

        if tname == "ignore" then
            -- Block nicht geladen, warten.
        elseif tname ~= "default:chest" and tname ~= "default:chest_locked" and
            tname ~= "default:chest_open" and tname ~= "default:chest_locked_open" then
            core.log("action", "[civi_npc] ERROR: Chest rejected! Node: " .. tostring(tname))
            self.target_chest = nil
            self.stand_target = nil
        else
            -- Distanzprüfung zur Truhe
            local chest_center = { x = self.target_chest.x + 0.5, y = self.target_chest.y + 0.5, z = self.target_chest.z +
            0.5 }
            local d2d = vector.distance({ x = pos.x, y = 0, z = pos.z },
                { x = chest_center.x, y = 0, z = chest_center.z })
            local dy = math.abs(pos.y - self.target_chest.y)

            if d2d <= 2.5 and dy <= 3.0 then
                set_state(self, "Depositing in chest")
                self:set_velocity(0)
                self.path_way = nil
                self:set_animation("punch")
                self.deposit_timer = (self.deposit_timer or 0) + dtime

                -- Truhe optisch öffnen
                if self.deposit_timer < 0.1 then
                    local node = core.get_node(self.target_chest)
                    if not self.original_chest_name then
                        self.original_chest_name = node.name
                        if node.name == "default:chest" or node.name == "default:chest_locked" then
                            core.swap_node(self.target_chest, { name = node.name .. "_open", param2 = node.param2 })
                            core.sound_play("default_chest_open",
                                { pos = self.target_chest, gain = 0.3, max_hear_distance = 10 })
                        end
                    end
                end

                -- Nach 2 Sekunden wird das Inventar übertragen
                if self.deposit_timer >= 2.0 then
                    local meta = core.get_meta(self.target_chest)
                    local inv = meta:get_inventory()
                    local wood_amount = (self.inv.wood or 0)

                    if wood_amount > 0 then
                        -- Holz verarbeiten: Häfte wird zu Brettern
                        local half_wood = math.floor(wood_amount / 2)
                        local boards = half_wood * 4
                        local remaining_wood = wood_amount - half_wood
                        if boards > 0 then inv:add_item("main", ItemStack("default:wood " .. boards)) end
                        if remaining_wood > 0 then inv:add_item("main", ItemStack("default:tree " .. remaining_wood)) end
                        self.inv.wood = 0
                    end

                    -- Sonstige Items (Äpfel, sticks etc.) ablegen
                    for name, count in pairs(self.inv.items) do
                        if count > 0 then
                            -- Müll-Filter: Blätter, Gras und Blumen werden entsorgt statt eingelagert
                            local is_trash = core.get_item_group(name, "leaves") > 0 or
                                core.get_item_group(name, "grass") > 0 or
                                core.get_item_group(name, "flora") > 0

                            if not is_trash then
                                inv:add_item("main", ItemStack(name .. " " .. count))
                            end
                            self.inv.items[name] = 0
                        end
                    end

                    -- Truhe wieder schließen
                    if self.original_chest_name then
                        local node = core.get_node(self.target_chest)
                        core.swap_node(self.target_chest, { name = self.original_chest_name, param2 = node.param2 })
                        core.sound_play("default_chest_close",
                            { pos = self.target_chest, gain = 0.3, max_hear_distance = 10 })
                        self.original_chest_name = nil
                    end

                    self.target_chest = nil
                    self.stand_target = nil
                    self.deposit_timer = 0
                    self.search_timer = 1.0
                end
                return true
            end
        end
    end
    return false
end

local function get_connected_wood(pos, max_nodes)
    local visited = {}
    local nodes = {}
    local queue = { pos }
    local root = vector.new(pos)
    local min_y = pos.y

    local function pos_to_hash(p)
        return p.x .. "," .. p.y .. "," .. p.z
    end

    visited[pos_to_hash(pos)] = true

    while #queue > 0 do
        local p = table.remove(queue, 1)
        table.insert(nodes, p)

        if p.y < min_y then
            min_y = p.y
            root = vector.new(p)
        end

        if #nodes >= (max_nodes or 400) then
            break
        end

        for dx = -1, 1 do
            for dy = -1, 1 do
                for dz = -1, 1 do
                    if dx ~= 0 or dy ~= 0 or dz ~= 0 then
                        local np = { x = p.x + dx, y = p.y + dy, z = p.z + dz }
                        local hash = pos_to_hash(np)
                        if not visited[hash] then
                            local name = core.get_node(np).name
                            if name ~= "ignore" and core.get_item_group(name, "tree") > 0 then
                                visited[hash] = true
                                table.insert(queue, np)
                            end
                        end
                    end
                end
            end
        end
    end

    return nodes, root
end

--- Interaktion mit Bäumen (Fällen und Aufforsten).
local function lumberjack_tree_interaction(self, dtime, pos)
    if self.target_tree then
        local tnode = core.get_node(self.target_tree)
        if tnode.name == "ignore" then
            -- Warten auf Laden
        elseif core.get_item_group(tnode.name, "tree") == 0 then
            -- Baum existiert nicht mehr
            self.target_tree = nil
            self.stand_target = nil
        else
            local tree_center = { x = self.target_tree.x + 0.5, y = self.target_tree.y + 0.5, z = self.target_tree.z +
            0.5 }
            local dist_2d = vector.distance({ x = pos.x, y = 0, z = pos.z },
                { x = tree_center.x, y = 0, z = tree_center.z })
            local dist_y = math.abs(pos.y - self.target_tree.y)

            if dist_2d <= 3.0 and dist_y <= 15.0 then
                set_state(self, "Chopping tree")
                self:set_velocity(0)
                self.path_way = nil
                self:set_animation("punch")
                self.chopping_timer = (self.chopping_timer or 0) + dtime

                if self.chopping_timer > 2.0 then
                    self.chopping_timer = 0


                    -- Identifiziere alle zusammenhängenden Holzblöcke auch diagonal
                    local tree_blocks, root_pos = get_connected_wood(self.target_tree, 400)

                    for _, p in ipairs(tree_blocks) do
                        local node = core.get_node(p)
                        local drops = core.get_node_drops(node.name, "")
                        for _, item in ipairs(drops) do
                            local stack = ItemStack(item)
                            local iname = stack:get_name()
                            local is_sapling = core.get_item_group(iname, "sapling") > 0 or iname:find("sapling")

                            if core.get_item_group(iname, "tree") > 0 or iname == "default:tree" then
                                self.inv.wood = (self.inv.wood or 0) + stack:get_count()
                            elseif is_sapling then
                                self.inv.saplings[iname] = (self.inv.saplings[iname] or 0) + stack:get_count()
                            else
                                self.inv.items[iname] = (self.inv.items[iname] or 0) + stack:get_count()
                            end
                        end
                        -- Nur diese Holzblöcke entfernen
                        core.remove_node(p)
                    end

                    -- Fülle die Wurzel (tiefster Block) mit passendem Dirt auf und setze einen Setzling
                    if root_pos then
                        local fill_mat = "default:dirt"
                        local neighbor_offsets = {
                            { x = 1, y = 0, z = 0 }, { x = -1, y = 0, z = 0 }, { x = 0, y = 0, z = 1 }, { x = 0, y = 0, z = -1 },
                            { x = 0, y = -1, z = 0 }, { x = 1, y = -1, z = 0 }, { x = -1, y = -1, z = 0 }, { x = 0, y = -1, z = 1 }, { x = 0, y = -1, z = -1 }
                        }
                        for _, moff in ipairs(neighbor_offsets) do
                            local npos = vector.add(root_pos, moff)
                            local nname = core.get_node(npos).name
                            if core.get_item_group(nname, "soil") > 0 or core.get_item_group(nname, "dirt") > 0 then
                                fill_mat = nname
                                break
                            end
                        end
                        core.set_node(root_pos, { name = fill_mat })

                        -- Setzling auf die Wurzel pflanzen
                        local plant_pos = { x = root_pos.x, y = root_pos.y + 1, z = root_pos.z }
                        if core.get_node(plant_pos).name == "air" then
                            local sapling_to_plant = nil
                            for s_name, count in pairs(self.inv.saplings) do
                                if count > 0 then
                                    sapling_to_plant = s_name
                                    break
                                end
                            end

                            if sapling_to_plant then
                                core.set_node(plant_pos, { name = sapling_to_plant })
                                self.inv.saplings[sapling_to_plant] = self.inv.saplings[sapling_to_plant] - 1
                                core.sound_play("default_place_node", { pos = plant_pos, gain = 0.5 })
                            end
                        end
                    end

                    --[[ Auskommentiert auf User-Wunsch: Pflanzen der Setzlinge und Bodenausgleich
                    -- Wiederaufforstung: Max 2 Setzlinge an zufälligen Orten im 7x7 Grid
                    local sapling_list = {}
                    for s_name, count in pairs(self.inv.saplings) do
                        if count > 0 then
                            for i = 1, count do table.insert(sapling_list, s_name) end
                        end
                    end

                    if #sapling_list > 0 then
                        -- Erstelle Liste aller 49 Koordinaten im 7x7 Grid
                        local candidates = {}
                        for dx = -3, 3 do
                            for dz = -3, 3 do
                                table.insert(candidates, {dx = dx, dz = dz})
                            end
                        end

                        -- Mische die Liste zufällig
                        for i = #candidates, 2, -1 do
                            local j = math.random(i)
                            candidates[i], candidates[j] = candidates[j], candidates[i]
                        end

                        local planted_count = 0
                        for _, cand in ipairs(candidates) do
                            if planted_count >= 2 or #sapling_list == 0 then break end

                            local sx = self.target_tree.x + cand.dx
                            local sz = self.target_tree.z + cand.dz
                            local sy = get_soil_y(sx, sz, self.target_tree.y)

                            if sy then
                                -- Loch-Check: Sind mindestens 6 Nachbarn höher?
                                local higher_neighbors = 0
                                local neighbor_offsets = {
                                    {x=1,z=0}, {x=-1,z=0}, {x=0,z=1}, {x=0,z=-1},
                                    {x=1,z=1}, {x=-1,z=-1}, {x=1,z=-1}, {x=-1,z=1}
                                }
                                for _, off in ipairs(neighbor_offsets) do
                                    local nsy = get_soil_y(sx + off.x, sz + off.z, sy)
                                    if nsy and nsy > sy then
                                        higher_neighbors = higher_neighbors + 1
                                    end
                                end

                                if higher_neighbors >= 6 then
                                    -- Stelle um 1 erhöhen (Loch auffüllen)
                                    local fill_pos = { x = sx, y = sy + 1, z = sz }
                                    if core.get_node(fill_pos).name == "air" then
                                        -- Passendes Material suchen
                                        local fill_mat = "default:dirt"
                                        for _, moff in ipairs({{x=1,z=0}, {x=-1,z=0}, {x=0,z=1}, {x=0,z=-1}, {x=0,y=-1}}) do
                                            local npos = vector.add(fill_pos, moff)
                                            local nname = core.get_node(npos).name
                                            if core.get_item_group(nname, "soil") > 0 or core.get_item_group(nname, "dirt") > 0 then
                                                fill_mat = nname
                                                break
                                            end
                                        end
                                        core.set_node(fill_pos, { name = fill_mat })
                                        sy = sy + 1
                                    end
                                end

                                -- Jetzt Setzling pflanzen
                                local plant_pos = { x = sx, y = sy + 1, z = sz }
                                if core.get_node(plant_pos).name == "air" then
                                    local s_name = table.remove(sapling_list, 1)
                                    core.set_node(plant_pos, { name = s_name })
                                    self.inv.saplings[s_name] = self.inv.saplings[s_name] - 1
                                    core.sound_play("default_place_node", { pos = plant_pos, gain = 0.5 })
                                    planted_count = planted_count + 1
                                end
                            end
                        end
                    end
                    ]] --

                    self.target_tree = nil
                    self.stand_target = nil
                    self.search_timer = 1.1
                end
                return true
            end
        end
    end
    return false
end

--- Bewegungslogik entlang eines Pfades (A* Pathfinding).
local function lumberjack_pathfinding(self, dtime, pos, target)
    if not target then return false end

    self.path_timer = (self.path_timer or 0) + dtime

    -- Falls das Ziel sich geändert hat, Pfad zurücksetzen
    if not self.last_target or not vector.equals(self.last_target, target) then
        self.path_way = nil
        self.last_target = vector.new(target)
        self.target_failures = 0
    end

    -- Pfad berechnen (alle 3 Sekunden oder falls kein Pfad vorhanden)
    if (not self.path_way or #self.path_way == 0) and self.path_timer > 3.0 then
        self.path_timer = 0
        self.path_way = core.find_path(pos, self.stand_target, 100, 1, 3, "AStar")

        if self.path_way then
            self.greedy_timer = 0
        else
            self.target_failures = (self.target_failures or 0) + 1
            self.greedy_timer = 5.0
        end

        -- Bei zu vielen Fehlschlägen Ziel blacklisten
        if self.target_failures >= 4 then
            local hash           = core.hash_node_position(target)
            self.blacklist[hash] = core.get_gametime() + 60
            self.target_tree     = nil
            self.target_chest    = nil
            self.stand_target    = nil
            self.path_way        = nil
            self.last_target     = nil
            self.target_failures = 0
        end
    end

    -- Entlang des Pfades bewegen
    if target and self.path_way and #self.path_way > 0 then
        set_state(self, "Moving on path to " .. (self.target_chest and "chest" or "tree"))
        local next_p = self.path_way[1]
        local target_wp = { x = next_p.x + 0.5, y = next_p.y, z = next_p.z + 0.5 }
        local d2node = vector.distance({ x = pos.x, y = 0, z = pos.z }, { x = target_wp.x, y = 0, z = target_wp.z })

        local threshold = (#self.path_way == 1) and 1.2 or 0.6
        if d2node < threshold then
            table.remove(self.path_way, 1)
            self.stuck_timer = 0
            self.last_pos = nil
            if #self.path_way == 0 then self:set_velocity(0) end
        else
            local direction = vector.direction({ x = pos.x, y = 0, z = pos.z },
                { x = target_wp.x, y = 0, z = target_wp.z })
            self.object:set_yaw(core.dir_to_yaw(direction))
            self:set_velocity(self.walk_velocity)
            self:set_animation("walk")

            -- Springen falls nötig
            self.jump_cooldown = (self.jump_cooldown or 0) - dtime
            if next_p.y > pos.y + 0.1 and self.jump_cooldown <= 0 then
                self:do_jump()
                self.jump_cooldown = 0.5
            end

            -- Stuck-Erkennung
            self.stuck_timer = (self.stuck_timer or 0) + dtime
            if self.stuck_timer >= 3.0 then
                if self.last_pos and vector.distance(pos, self.last_pos) < 0.5 then
                    core.log("action", "[civi_npc] Path stuck at " .. core.pos_to_string(pos) .. "! Handing to Mobs API.")
                    self.path_way = nil
                    self.path_timer = 3.1
                    self.target_failures = (self.target_failures or 0) + 1
                    self.mobs_takeover_timer = 8.0
                end
                self.last_pos    = vector.new(pos)
                self.stuck_timer = 0
            end
        end
        return true
    end
    return false
end

--- "Greedy" Bewegung (direkt aufs Ziel zu), falls Pathfinding versagt.
local function lumberjack_greedy_movement(self, dtime, pos, target)
    if target and not self.path_way and (self.greedy_timer or 0) > 0 then
        set_state(self, "Greedy fallback to " .. (self.target_chest and "chest" or "tree"))
        self.greedy_timer = self.greedy_timer - dtime
        local direction = vector.direction({ x = pos.x, y = 0, z = pos.z }, { x = target.x, y = 0, z = target.z })
        self.object:set_yaw(core.dir_to_yaw(direction))
        self:set_velocity(self.walk_velocity)
        self:set_animation("walk")

        self.jump_cooldown = (self.jump_cooldown or 0) - dtime
        local scan_pos = vector.add(pos, vector.multiply(direction, 0.8))
        if core.get_node(scan_pos).name ~= "air" and self.jump_cooldown <= 0 then
            self:do_jump()
            self.jump_cooldown = 1.0
        end

        self.stuck_timer = (self.stuck_timer or 0) + dtime
        if self.stuck_timer > 3.0 then
            if self.last_pos and vector.distance(pos, self.last_pos) < 0.2 then
                self.greedy_timer = 0
                self.target_failures = (self.target_failures or 0) + 1
                self.mobs_takeover_timer = 8.0
            end
            self.last_pos = vector.new(pos)
            self.stuck_timer = 0
        end
        return true
    end
    return false
end

--- Suchlogik für Bäume oder Truhen in der Umgebung.
local function lumberjack_search_logic(self, dtime, pos)
    self.search_timer = (self.search_timer or 0) + dtime
    if not self.target_tree and not self.target_chest then
        if self.search_timer >= 1.0 then
            self.search_timer = 0

            -- 1. TRUHEN-SUCHE (Priorität falls wir Holz haben)
            -- 1. TRUHEN-SUCHE (Priorität falls wir mind. 99 Holz haben)
            if (self.inv.wood or 0) >= 99 then
                set_state(self, "Searching for chest (Wood: " .. tostring(self.inv.wood) .. ")")
                local range = 110
                local chests = core.find_nodes_in_area(
                    { x = pos.x - range, y = pos.y - range, z = pos.z - range },
                    { x = pos.x + range, y = pos.y + range, z = pos.z + range },
                    { "default:chest", "default:chest_locked", "default:chest_open", "default:chest_locked_open" }
                )

                if #chests > 0 then
                    table.sort(chests, function(a, b) return vector.distance(pos, a) < vector.distance(pos, b) end)
                    for _, chest_pos in ipairs(chests) do
                        local hash = core.hash_node_position(chest_pos)
                        if not (self.blacklist[hash] and self.blacklist[hash] >= core.get_gametime()) then
                            local stand_spot = common.find_standing_spot(chest_pos)
                            if stand_spot then
                                self.target_chest = chest_pos
                                self.stand_target = stand_spot
                                self.path_timer = 3.1
                                set_state(self, "Moving to chest at " .. core.pos_to_string(chest_pos))
                                return true
                            else
                                self.blacklist[hash] = core.get_gametime() + 60
                            end
                        end
                    end
                end
            end

            -- 2. BAUM-SUCHE (Falls wir kein Holz haben)
            -- 2. BAUM-SUCHE (Falls wir weniger als 99 Holz haben)
            if (self.inv.wood or 0) < 99 then
                set_state(self, "Searching for tree (Wood: " .. tostring(self.inv.wood) .. ")")
                local range = 100
                local found_nodes = core.find_nodes_in_area(
                    { x = pos.x - range, y = pos.y - range, z = pos.z - range },
                    { x = pos.x + range, y = pos.y + range, z = pos.z + range },
                    { "group:tree" }
                )

                local roots = {}
                local now = core.get_gametime()
                for _, p in ipairs(found_nodes) do
                    local check_pos = vector.new(p)
                    for i = 1, 30 do
                        local under = { x = check_pos.x, y = check_pos.y - 1, z = check_pos.z }
                        if core.get_item_group(core.get_node(under).name, "tree") > 0 then
                            check_pos.y = check_pos.y - 1
                        else
                            break
                        end
                    end
                    local hash = core.hash_node_position(check_pos)
                    if not self.blacklist[hash] or self.blacklist[hash] < now then
                        roots[hash] = check_pos
                    end
                end

                local candidates = {}
                for _, root in pairs(roots) do table.insert(candidates, root) end

                if #candidates > 0 then
                    table.sort(candidates, function(a, b) return vector.distance(pos, a) < vector.distance(pos, b) end)
                    for _, found_root in ipairs(candidates) do
                        local stand_spot = common.find_standing_spot(found_root)
                        if stand_spot then
                            self.target_tree = found_root
                            self.stand_target = stand_spot
                            self.path_timer = 3.1
                            return true
                        else
                            self.blacklist[core.hash_node_position(found_root)] = core.get_gametime() + 300
                        end
                    end
                end
            end
            self.stuck_timer = 0
        end

        if self.search_timer < 0.9 then
            set_state(self, "Idle (Waiting for Search)")
        else
            set_state(self, "Idle / Return FALSE")
        end
    end
    return false
end

-- === ENTITY REGISTRIERUNG ===

mobs:register_mob("civi_npc:lumberjack", {
    type = "npc",
    passive = true,
    hp_min = 20,
    hp_max = 20,
    collisionbox = { -0.3, -0.0, -0.3, 0.3, 1.8, 0.3 },
    visual = "mesh",
    mesh = "skinsdb_3d_armor_character_5.b3d",
    textures = {
        "blank.png",                 -- Slot 1: 64x32 base
        "character.farmer_male.png", -- Slot 2: 64x64 overlay
        "blank.png",                 -- Slot 3: Armor
        "default_tool_steelaxe.png"  -- Slot 4: Wielded item
    },
    makes_footstep_sound = true,
    walk_velocity = 1.5,
    run_velocity = 3,
    water_damage = 0,
    lava_damage = 4,
    fall_damage = 0,
    pathfinding = 2,
    jump_height = 2.0,
    fear_height = 3,
    can_leap = true,
    animation = {
        speed_normal = 30,
        speed_run = 30,
        stand_start = 0,
        stand_end = 79,
        walk_start = 168,
        walk_end = 187,
        run_start = 168,
        run_end = 187,
        punch_start = 189,
        punch_end = 198,
    },

    do_custom = function(self, dtime)
        -- Initialisierung des NPCs
        if not self.inv then
            lumberjack_count = lumberjack_count + 1
            self._lumberjack_id = lumberjack_count
            self.inv = { wood = 0, saplings = {}, items = {} }
            self.blacklist = {}
            self.target_failures = 0
            self._lumberjack_state = "Init"
            self.last_search_log_time = 0
        end

        -- Sicherstellen, dass IDs und Tabellen existieren (z.B. nach Reload)
        if not self._lumberjack_id then
            lumberjack_count = lumberjack_count + 1
            self._lumberjack_id = lumberjack_count
        end
        if type(self.inv.saplings) == "number" then self.inv.saplings = {} end
        if not self.inv.items then self.inv.items = {} end
        self.greedy_timer = self.greedy_timer or 0
        self.blacklist = self.blacklist or {}
        self.target_failures = self.target_failures or 0

        local pos = self.object:get_pos()
        if not pos then return false end

        -- Gegenstände (Setzlinge, Früchte, Holz) vom Boden aufsammeln (da Blätter nun frei droppen)
        for _, obj in ipairs(core.get_objects_inside_radius(pos, 4)) do
            if not obj:is_player() and obj:get_luaentity() and obj:get_luaentity().name == "__builtin:item" then
                local itemstring = obj:get_luaentity().itemstring
                if itemstring then
                    local stack = ItemStack(itemstring)
                    local iname = stack:get_name()
                    local is_sapling = core.get_item_group(iname, "sapling") > 0 or iname:find("sapling")
                    local is_wood = core.get_item_group(iname, "tree") > 0 or iname == "default:tree"
                    local is_fruit = core.get_item_group(iname, "leafdecay") > 0 or iname:find("apple")

                    if is_sapling then
                        self.inv.saplings[iname] = (self.inv.saplings[iname] or 0) + stack:get_count()
                        obj:remove()
                    elseif is_wood then
                        self.inv.wood = (self.inv.wood or 0) + stack:get_count()
                        obj:remove()
                    elseif is_fruit then
                        self.inv.items[iname] = (self.inv.items[iname] or 0) + stack:get_count()
                        obj:remove()
                    end
                end
            end
        end

        -- Recovery durch Mobs API (falls festgesteckt)
        self.mobs_takeover_timer = (self.mobs_takeover_timer or 0) - dtime
        if self.mobs_takeover_timer > 0 then
            set_state(self, "Mobs API takeover (stuck recovery)")
            return true
        end

        -- Haupt-Entscheidungsbaum
        if lumberjack_chest_interaction(self, dtime, pos) then return true end
        if lumberjack_tree_interaction(self, dtime, pos) then return true end

        local target = self.target_chest or self.stand_target or self.target_tree
        if target then
            if lumberjack_pathfinding(self, dtime, pos, target) then return true end
            if lumberjack_greedy_movement(self, dtime, pos, target) then return true end
            return true
        end

        if lumberjack_search_logic(self, dtime, pos) then return true end

        return true
    end,
})

-- Spawnen des Holzfällers auf Gras
mobs:spawn({
    name = "civi_npc:lumberjack",
    nodes = { "default:dirt_with_grass" },
    min_light = 10,
    chance = 7000,
    active_object_count = 1,
    min_height = 0,
})

-- Spawnegg registrieren
mobs:register_egg("civi_npc:lumberjack", "Lumberjack (myCraftCivi)", "civi_lumberjack_spawner.png")
