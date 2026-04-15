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


--- Hilfsfunktion: Entfernt "weiche" Hindernisse (Blätter, Erde) im Weg.
local function clear_soft_obstacles(self, pos, direction)
    if not direction then return false end
    local check_pos = vector.add(pos, vector.multiply(direction, 0.8))
    local cleared = false

    -- Prüfe Brusthöhe (1) und Kopfhöhe (2)
    for _, dy in ipairs({ 1, 2 }) do
        local p = { x = check_pos.x, y = math.floor(pos.y + dy), z = check_pos.z }
        local node = core.get_node(p)
        if node.name ~= "air" and node.name ~= "ignore" then
            local is_soft = core.get_item_group(node.name, "leaves") > 0 or
                core.get_item_group(node.name, "dirt") > 0 or
                core.get_item_group(node.name, "soil") > 0 or
                core.get_item_group(node.name, "grass") > 0 or
                core.get_item_group(node.name, "flora") > 0 or
                node.name:find("bush")

            if is_soft then
                core.log("action", "[mycraftcivi] Lumberjack #" .. (self._lumberjack_id or "?") ..
                    " clearing path at " .. core.pos_to_string(p) .. " (" .. node.name .. ")")

                -- Abbauen (simuliert durch Entfernen + Sound + Partikel)
                core.remove_node(p)
                core.sound_play("default_dig_choppy", { pos = p, gain = 0.5, max_hear_distance = 10 })
                self:set_animation("punch")
                cleared = true
            end
        end
    end
    return cleared
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
            if self.home_pos and vector.equals(self.home_pos, self.target_chest) then
                self.home_pos = nil
            end
        else
            -- Bei Interaktion setzen wir dieses Chest als dauerhaftes "Zuhause"
            if not self.home_pos then
                self.home_pos = vector.new(self.target_chest)
                core.log("action", "[mycraftcivi] Lumberjack #" .. (self._lumberjack_id or "?") ..
                    " established HOME at " .. core.pos_to_string(self.home_pos))
            end

            -- Distanzprüfung zur Truhe
            local chest_center = {
                x = self.target_chest.x + 0.5,
                y = self.target_chest.y + 0.5,
                z = self.target_chest.z +
                    0.5
            }
            local d2d = vector.distance({ x = pos.x, y = 0, z = pos.z },
                { x = chest_center.x, y = 0, z = chest_center.z })
            local dy = math.abs(pos.y - self.target_chest.y)

            if d2d <= 2.5 and dy <= 3.0 then
                local time = core.get_timeofday() or 0.5
                local is_night = (time > 0.76 or time < 0.24)

                local total_saplings = 0
                for _, count in pairs(self.inv.saplings) do
                    total_saplings = total_saplings + count
                end

                local has_chest_task = false
                if (self.inv.wood or 0) > 0 then has_chest_task = true end
                for _, v in pairs(self.inv.items) do if v > 0 then
                        has_chest_task = true; break
                    end end

                -- Setzling-Refill nur, wenn Cooldown abgelaufen ist
                if total_saplings > 50 then
                    has_chest_task = true
                elseif total_saplings < 50 then
                    if not self.refill_cooldown or self.refill_cooldown <= 0 then
                        has_chest_task = true
                    end
                end

                if self.chest_wait_timer and self.chest_wait_timer > 0 then
                    if not has_chest_task and is_night then
                        self.chest_wait_timer = 4.0 -- Keep checking later
                    end
                    self.chest_wait_timer = self.chest_wait_timer - dtime
                    self:set_animation("stand")
                    set_state(self, "Waiting (" .. tostring(math.ceil(self.chest_wait_timer)) .. "s)")
                    return true
                end

                if not has_chest_task and is_night then
                    self:set_animation("stand")
                    set_state(self, "Waiting for morning")
                    self.chest_wait_timer = 5.0
                    return true
                end

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
                    local leftovers = false

                    local wood_amount = (self.inv.wood or 0)
                    if wood_amount > 0 then
                        -- Holz verarbeiten: Häfte wird zu Brettern
                        local half_wood = math.floor(wood_amount / 2)
                        local boards = half_wood * 4
                        local remaining_wood = wood_amount - half_wood

                        local left_boards_count = 0
                        local left_wood_count = 0

                        if boards > 0 then
                            local l = inv:add_item("main", ItemStack("default:wood " .. boards))
                            left_boards_count = l:get_count()
                        end
                        if remaining_wood > 0 then
                            local l = inv:add_item("main", ItemStack("default:tree " .. remaining_wood))
                            left_wood_count = l:get_count()
                        end

                        local restored_wood = left_wood_count + math.ceil(left_boards_count / 4)
                        self.inv.wood = restored_wood
                        if restored_wood > 0 then leftovers = true end
                    end

                    -- Sonstige Items (Äpfel, sticks etc.) ablegen
                    for name, count in pairs(self.inv.items) do
                        if count > 0 then
                            -- Müll-Filter: Blätter, Gras und Blumen werden entsorgt statt eingelagert
                            local is_trash = core.get_item_group(name, "leaves") > 0 or
                                core.get_item_group(name, "grass") > 0 or
                                core.get_item_group(name, "flora") > 0

                            if not is_trash then
                                local l = inv:add_item("main", ItemStack(name .. " " .. count))
                                self.inv.items[name] = l:get_count()
                                if l:get_count() > 0 then leftovers = true end
                            else
                                self.inv.items[name] = 0
                            end
                        end
                    end

                    -- Zähle aktuelle Setzlinge
                    local total_saplings = 0
                    for name, count in pairs(self.inv.saplings) do
                        total_saplings = total_saplings + count
                    end

                    if total_saplings > 50 then
                        -- Überschüssige Setzlinge ablegen
                        local to_remove = total_saplings - 50
                        for name, count in pairs(self.inv.saplings) do
                            if to_remove > 0 and count > 0 then
                                local remove_from_this = math.min(count, to_remove)
                                local l = inv:add_item("main", ItemStack(name .. " " .. remove_from_this))
                                local actually_removed = remove_from_this - l:get_count()
                                self.inv.saplings[name] = count - actually_removed
                                to_remove = to_remove - actually_removed
                                if l:get_count() > 0 then leftovers = true end
                            end
                        end
                    elseif total_saplings < 50 then
                        -- Setzlinge aus der Truhe entnehmen
                        local to_add = 50 - total_saplings
                        local list = inv:get_list("main")
                        local gained = 0
                        for i = 1, inv:get_size("main") do
                            local stack = list[i]
                            if not stack:is_empty() then
                                local iname = stack:get_name()
                                local is_sapling = core.get_item_group(iname, "sapling") > 0 or iname:find("sapling")
                                if is_sapling then
                                    local take_count = math.min(stack:get_count(), to_add)
                                    local taken_stack = stack:take_item(take_count)
                                    inv:set_stack("main", i, stack)
                                    local taken_count = taken_stack:get_count()
                                    self.inv.saplings[iname] = (self.inv.saplings[iname] or 0) + taken_count
                                    to_add = to_add - taken_count
                                    gained = gained + taken_count
                                    if to_add <= 0 then break end
                                end
                            end
                        end

                        -- Falls nichts gefunden wurde, Cooldown setzen (5 Minuten)
                        if gained == 0 then
                            self.refill_cooldown = 300
                            set_state(self, "No saplings found. Refill cooldown active.")
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

                    self.deposit_timer = 0
                    if leftovers then
                        self.chest_wait_timer = 60.0
                    else
                        self.chest_wait_timer = nil
                        self.target_chest = nil
                        self.stand_target = nil
                        self.search_timer = 1.0
                    end
                end
                return true
            end
        end
        return false
    end
end

local function get_connected_wood(pos, max_nodes)
    local visited = {}
    local nodes = {}
    local queue = { pos }

    local min_y = pos.y
    local max_y = pos.y
    local top = vector.new(pos)

    local function pos_to_hash(p)
        return p.x .. "," .. p.y .. "," .. p.z
    end

    visited[pos_to_hash(pos)] = true

    while #queue > 0 do
        local p = table.remove(queue, 1)
        table.insert(nodes, p)

        if p.y < min_y then
            min_y = p.y
        end
        if p.y > max_y then
            max_y = p.y
            top = vector.new(p)
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

    -- Berechne den Schwerpunkt (Center) aller Blöcke auf der tiefsten Ebene
    local base_nodes = {}
    for _, n in ipairs(nodes) do
        if n.y == min_y then
            table.insert(base_nodes, n)
        end
    end

    local sum_x, sum_z = 0, 0
    for _, n in ipairs(base_nodes) do
        sum_x = sum_x + n.x
        sum_z = sum_z + n.z
    end

    local root_center = {
        x = math.floor(sum_x / #base_nodes + 0.5),
        y = min_y,
        z = math.floor(sum_z / #base_nodes + 0.5)
    }

    return nodes, root_center, top
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
            local tree_center = {
                x = self.target_tree.x + 0.5,
                y = self.target_tree.y + 0.5,
                z = self.target_tree.z + 0.5
            }
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

                    -- Identifiziere alle zusammenhängenden Holzblöcke
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
                        core.remove_node(p)
                    end

                    -- Wiederaufforstung
                    if root_pos then
                        local sapling_list = {}
                        for s_name, count in pairs(self.inv.saplings) do
                            if count > 0 then
                                for i = 1, count do table.insert(sapling_list, s_name) end
                            end
                        end

                        local plant_pos1 = { x = root_pos.x, y = root_pos.y, z = root_pos.z }
                        local is_hole = false
                        local horiz_offsets = { { x = 1, y = 0, z = 0 }, { x = -1, y = 0, z = 0 }, { x = 0, y = 0, z = 1 }, { x = 0, y = 0, z = -1 } }
                        for _, moff in ipairs(horiz_offsets) do
                            local nname = core.get_node(vector.add(root_pos, moff)).name
                            if nname ~= "air" and core.get_item_group(nname, "leaves") == 0 and core.get_item_group(nname, "plant") == 0 then
                                is_hole = true
                                break
                            end
                        end

                        if is_hole then
                            local fill_mat = "default:dirt"
                            for _, moff in ipairs(horiz_offsets) do
                                local nname = core.get_node(vector.add(root_pos, moff)).name
                                if core.get_item_group(nname, "soil") > 0 or core.get_item_group(nname, "dirt") > 0 then
                                    fill_mat = nname
                                    break
                                end
                            end
                            core.set_node(root_pos, { name = fill_mat })
                            plant_pos1.y = root_pos.y + 1
                        else
                            local under_pos = { x = root_pos.x, y = root_pos.y - 1, z = root_pos.z }
                            local under_node = core.get_node(under_pos)
                            if core.get_item_group(under_node.name, "soil") == 0 and core.get_item_group(under_node.name, "dirt") == 0 then
                                core.set_node(under_pos, { name = "default:dirt" })
                            end
                        end

                        if core.get_node(plant_pos1).name == "air" and #sapling_list > 0 then
                            local s_name = table.remove(sapling_list, 1)
                            core.set_node(plant_pos1, { name = s_name })
                            self.inv.saplings[s_name] = self.inv.saplings[s_name] - 1
                            core.sound_play("default_place_node", { pos = plant_pos1, gain = 0.5 })
                        end

                        if #sapling_list > 0 then
                            local candidates = {}
                            for dx = -4, 4 do
                                for dz = -4, 4 do
                                    table.insert(candidates, { dx = dx, dz = dz })
                                end
                            end
                            for i = #candidates, 2, -1 do
                                local j = math.random(i)
                                candidates[i], candidates[j] = candidates[j], candidates[i]
                            end

                            local planted_second = false
                            for _, cand in ipairs(candidates) do
                                if not planted_second then
                                    local p2 = { x = root_pos.x + cand.dx, y = root_pos.y, z = root_pos.z + cand.dz }
                                    for dy = 2, -2, -1 do
                                        local py = { x = p2.x, y = p2.y + dy, z = p2.z }
                                        local node_at = core.get_node(py)
                                        local node_under = core.get_node({ x = py.x, y = py.y - 1, z = py.z })

                                        if node_at.name == "air" and (core.get_item_group(node_under.name, "soil") > 0 or
                                                core.get_item_group(node_under.name, "dirt") > 0) then
                                            local dist = vector.distance(py, plant_pos1)
                                            if dist >= 3.0 and dist <= 6.0 then
                                                local s_name = sapling_list[1]
                                                core.set_node(py, { name = s_name })
                                                self.inv.saplings[s_name] = self.inv.saplings[s_name] - 1
                                                core.sound_play("default_place_node", { pos = py, gain = 0.5 })
                                                planted_second = true
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end

                    self.target_tree = nil
                    self.stand_target = nil
                    self.search_timer = 1.1
                end
                return true
            end
        end
        return false
    end
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
        local pos_str = "(" .. math.floor(pos.x) .. "," .. math.floor(pos.y) .. "," .. math.floor(pos.z) .. ")"
        local target_str = "(" ..
        math.floor(self.stand_target.x) ..
        "," .. math.floor(self.stand_target.y) .. "," .. math.floor(self.stand_target.z) .. ")"

        core.log("action", "[mycraftcivi] Lumberjack #" .. (self._lumberjack_id or "?") ..
            " starting journey to standing spot " .. target_str .. " from feet at " .. pos_str)

        self.path_way = core.find_path(pos, self.stand_target, 100, 1, 3, "AStar")

        if self.path_way then
            self.greedy_timer = 0
            core.log("action", "[mycraftcivi] Path found with " .. #self.path_way .. " nodes.")
        else
            self.target_failures = (self.target_failures or 0) + 1
            self.greedy_timer = 5.0
            core.log("action", "[mycraftcivi] Path: FAILED (No path to target)")
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

            -- Stuck-Erkennung & Hindernisbeseitigung
            self.stuck_timer = (self.stuck_timer or 0) + dtime
            if self.stuck_timer >= 0.8 then
                if clear_soft_obstacles(self, pos, direction) then
                    -- Falls etwas weggeräumt wurde, geben wir ihm eine Chance weiterzulaufen
                    -- self.stuck_timer = 0 -- Optional: Timer zurücksetzen?
                end
            end

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

        -- Stuck-Erkennung & Hindernisbeseitigung
        self.stuck_timer = (self.stuck_timer or 0) + dtime
        if self.stuck_timer > 0.8 then
            clear_soft_obstacles(self, pos, direction)
        end

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

            local time = core.get_timeofday() or 0.5
            local is_night = (time > 0.76 or time < 0.24)

            -- 0. HOME-VALIDIERUNG (Existiert die Truhe noch?)
            if self.home_pos then
                local node = core.get_node(self.home_pos)
                if node.name == "ignore" then
                    -- Block nicht geladen, wir behalten die Info
                elseif node.name ~= "default:chest" and node.name ~= "default:chest_locked" and
                    node.name ~= "default:chest_open" and node.name ~= "default:chest_locked_open" then
                    core.log("action", "[mycraftcivi] Lumberjack #" .. (self._lumberjack_id or "?") ..
                        " lost HOME (Chest removed) at " .. core.pos_to_string(self.home_pos))
                    self.home_pos = nil
                end
            end

            -- 1. TRUHEN-SUCHE (Priorität falls wir Holz haben, Nacht ist ODER wir noch kein HOME haben)
            if is_night or (self.inv.wood or 0) >= 99 or not self.home_pos then
                set_state(self, "Searching for " .. (self.home_pos and "chest" or "HOME chest"))
                local search_center = pos
                local range = 110

                -- Falls wir ein Home haben, aber weit weg sind, suchen wir bevorzugt dort
                if self.home_pos then search_center = self.home_pos end

                local chests = core.find_nodes_in_area(
                    { x = search_center.x - range, y = search_center.y - range, z = search_center.z - range },
                    { x = search_center.x + range, y = search_center.y + range, z = search_center.z + range },
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

                                -- Partikel einzeichnen für den Standplatz (Gelb)
                                core.add_particle({
                                    pos = { x = stand_spot.x, y = stand_spot.y + 2, z = stand_spot.z },
                                    velocity = { x = 0, y = 0, z = 0 },
                                    acceleration = { x = 0, y = 0, z = 0 },
                                    expirationtime = 15,
                                    size = 4,
                                    collisiondetection = false,
                                    vertical = false,
                                    texture = "heart.png^[colorize:#FFFF00:200",
                                    glow = 14,
                                })

                                return true
                            else
                                self.blacklist[hash] = core.get_gametime() + 60
                            end
                        end
                    end
                end
            end

            -- 2. BAUM-SUCHE (Falls wir weniger als 99 Holz haben, Tag ist UND wir ein Home haben)
            if not is_night and (self.inv.wood or 0) < 99 and self.home_pos then
                set_state(self, "Searching for tree near HOME")
                local search_center = self.home_pos
                local range = 60 -- Wir suchen nur im 60m Umkreis um die Truhe
                local found_nodes = core.find_nodes_in_area(
                    { x = search_center.x - range, y = search_center.y - range, z = search_center.z - range },
                    { x = search_center.x + range, y = search_center.y + range, z = search_center.z + range },
                    { "group:tree" }
                )

                local processed_nodes = {}
                local roots = {}
                local now = core.get_gametime()
                for _, p in ipairs(found_nodes) do
                    local node_hash = core.hash_node_position(p)
                    if not processed_nodes[node_hash] then
                        local tree_nodes, min_y_pos = get_connected_wood(p, 50)
                        for _, tp in ipairs(tree_nodes) do
                            processed_nodes[core.hash_node_position(tp)] = true
                        end
                        if min_y_pos then
                            local root_hash = core.hash_node_position(min_y_pos)
                            if not self.blacklist[root_hash] or self.blacklist[root_hash] < now then
                                roots[root_hash] = min_y_pos
                            end
                        end
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

                            -- Partikel einzeichnen
                            -- 1. Standplatz (Gelb)
                            core.add_particle({
                                pos = { x = stand_spot.x, y = stand_spot.y + 2, z = stand_spot.z },
                                expirationtime = 15,
                                size = 4,
                                texture = "heart.png^[colorize:#FFFF00:200",
                                glow = 14,
                            })
                            -- 2. Baumkrone (Grün)
                            local _, _, top_pos = get_connected_wood(found_root, 50)
                            if top_pos then
                                core.add_particle({
                                    pos = { x = top_pos.x, y = top_pos.y + 2, z = top_pos.z },
                                    expirationtime = 15,
                                    size = 4,
                                    texture = "heart.png^[colorize:#00FF00:200",
                                    glow = 14,
                                })
                            end

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
        return false
    end
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
    stepheight = 1.1,
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
        if type(self.inv.saplings) ~= "table" then self.inv.saplings = {} end
        if not self.inv.items then self.inv.items = {} end

        -- Cooldowns dekrementieren
        self.refill_cooldown = (self.refill_cooldown or 0) - dtime
        self.greedy_timer = self.greedy_timer or 0
        self.blacklist = self.blacklist or {}
        self.target_failures = self.target_failures or 0

        local pos = self.object:get_pos()
        if not pos then return false end

        -- Gegenstände (Setzlinge, Früchte, Holz) vom Boden aufsammeln (da Blätter nun frei droppen)
        for _, obj in ipairs(core.get_objects_inside_radius(pos, 8)) do
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

        -- Sicherheitsschranke: Entfernung zum Zuhause prüfen
        if self.home_pos then
            local dist_home = vector.distance(pos, self.home_pos)
            if dist_home > 100 and not self.target_chest then
                set_state(self, "Too far from HOME (" .. math.floor(dist_home) .. "m)! Returning.")
                self.target_tree = nil
                self.target_chest = self.home_pos
                self.stand_target = common.find_standing_spot(self.home_pos)
                self.path_timer = 3.1
            end
        end

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
--[[ mobs:spawn({
    name = "civi_npc:lumberjack",
    nodes = { "default:dirt_with_grass" },
    min_light = 10,
    chance = 7000,
    active_object_count = 1,
    min_height = 0,
}) ]]

-- Spawnegg registrieren
mobs:register_egg("civi_npc:lumberjack", "Lumberjack (myCraftCivi)", "civi_lumberjack_spawner.png")
