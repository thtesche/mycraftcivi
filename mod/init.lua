-- Register the Lumberjack mob
-- Table to map tree trunks to their respective saplings for smart replanting
local trunk_to_sapling = {
    ["default:tree"] = "default:sapling",
    ["default:acacia_tree"] = "default:acacia_sapling",
    ["default:aspen_tree"] = "default:aspen_sapling",
    ["default:jungletree"] = "default:jungle_sapling",
    ["default:pine_tree"] = "default:pine_sapling",
}

local lumberjack_count = 0

-- Utility: Find a valid air node next to a target where the NPC can stand
local function find_standing_spot(target_pos)
    -- Kann man physikalisch darin stehen?
    -- Luft, dekorative Flora (walkable=false) und Blaetter = passierbar
    -- WICHTIG: grass-Gruppe NICHT ausschliessen da default:dirt_with_grass group grass=1 hat!
    local function is_passable(name)
        local def = core.registered_nodes[name]
        if not def or not def.walkable then return true end                 -- Luft, Dekogras, etc.
        if core.get_item_group(name, "leaves") > 0 then return true end -- Blaetter
        return false                                                        -- alle anderen walkable=true Bloecke sind solid
    end

    -- Echter fester Boden (kein Baumstamm, keine Blaetter)?
    local function is_solid_ground(name)
        local def = core.registered_nodes[name]
        if not def or not def.walkable then return false end
        if core.get_item_group(name, "tree") > 0 then return false end
        if core.get_item_group(name, "leaves") > 0 then return false end
        return true
    end

    local neighbor_offsets = {
        { x = 1, z = 0 }, { x = -1, z = 0 }, { x = 0, z = 1 }, { x = 0, z = -1 },
        { x = 1, z = 1 }, { x = -1, z = -1 }, { x = 1, z = -1 }, { x = -1, z = 1 }
    }

    -- Pro Richtung: Y von oben nach unten scannen, ersten gueltigen Standplatz nehmen
    for _, off in ipairs(neighbor_offsets) do
        local cx = target_pos.x + off.x
        local cz = target_pos.z + off.z
        for dy = 3, -5, -1 do
            local cy      = target_pos.y + dy
            local n_here  = core.get_node({ x = cx, y = cy, z = cz }).name
            local n_below = core.get_node({ x = cx, y = cy - 1, z = cz }).name
            local n_above = core.get_node({ x = cx, y = cy + 1, z = cz }).name
            
            if is_passable(n_here) and is_solid_ground(n_below) and is_passable(n_above) then
                -- Muss von der Seite erreichbar sein (kein 1-Block-Loch, das nur von oben zugaenglich ist)
                local horizontal_ok = false
                for _, ho in ipairs({ { x = 1, z = 0 }, { x = -1, z = 0 }, { x = 0, z = 1 }, { x = 0, z = -1 } }) do
                    if is_passable(core.get_node({ x = cx + ho.x, y = cy, z = cz + ho.z }).name) then
                        horizontal_ok = true
                        break
                    end
                end
                if horizontal_ok then
                    return { x = cx, y = cy, z = cz }
                end
            end
        end
    end
    -- No spot found
    return nil
end

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
        "character.farmer_male.png", -- Slot 2: 64x64 overlay/modern
        "blank.png",                 -- Slot 3: Armor
        "blank.png"                  -- Slot 4: Wielded item
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
        if not self.inv then
            lumberjack_count = lumberjack_count + 1
            self._lumberjack_id = lumberjack_count
            self.inv = { wood = 0, saplings = {}, items = {} }
            self.blacklist = {} -- [pos_hash] = expiration_time
            self.target_failures = 0
            self._lumberjack_state = "Init"
            self.last_search_log_time = 0
        end
        -- Migration guards
        if not self._lumberjack_id then
            lumberjack_count = lumberjack_count + 1
            self._lumberjack_id = lumberjack_count
        end
        if type(self.inv.saplings) == "number" then self.inv.saplings = {} end
        if not self.inv.items then self.inv.items = {} end
        self.greedy_timer = self.greedy_timer or 0
        self.blacklist = self.blacklist or {}
        self.target_failures = self.target_failures or 0

        local function set_state(new_state)
            local function is_boring(s)
                return s == "Idle / Return FALSE" or
                    s == "Idle (Waiting for Search)" or
                    (s and s:sub(1, 9) == "Searching")
            end

            if self._lumberjack_state ~= new_state then
                if not (is_boring(self._lumberjack_state) and is_boring(new_state)) then
                    core.log("action", "[civi_npc] Lumberjack #" .. self._lumberjack_id .. " State: " ..
                        tostring(self._lumberjack_state) .. " -> " .. new_state)
                end
                self._lumberjack_state = new_state
            end
        end

        local pos = self.object:get_pos()
        if not pos then return false end

        -- === Obstacle Logic removed: handled by pathfinder ===

        self.mobs_takeover_timer = (self.mobs_takeover_timer or 0) - dtime
        if self.mobs_takeover_timer > 0 then
            set_state("Mobs API takeover (stuck recovery)")
            return true
        end

        local target = self.target_chest or self.stand_target or self.target_tree

        -- ==== 1. BUSY / INTERACTION LOCK ====
        -- If we are already chopping or delivering, stay stationary and do nothing else.

        -- A. Chest Interaction
        if self.target_chest then
            local target_node = core.get_node(self.target_chest)
            local tname = target_node.name
            if tname == "ignore" then
                -- Target is in an unloaded block, wait for it to load
            elseif tname ~= "default:chest" and tname ~= "default:chest_locked" and
                tname ~= "default:chest_open" and tname ~= "default:chest_locked_open" then
                core.log("action", "[civi_npc] ERROR: Chest rejected! Node name was: '" .. tostring(tname) .. "' at " .. core.pos_to_string(self.target_chest))
                self.target_chest = nil
                self.stand_target = nil
            else
                local chest_center = {
                    x = self.target_chest.x + 0.5,
                    y = self.target_chest.y + 0.5,
                    z = self
                        .target_chest.z + 0.5
                }
                local d2d = vector.distance({ x = pos.x, y = 0, z = pos.z }, {
                    x = chest_center.x,
                    y = 0,
                    z =
                        chest_center.z
                })
                local dy = math.abs(pos.y - self.target_chest.y)

                if d2d <= 3.5 and dy <= 3.0 then
                    set_state("Depositing in chest")
                    self:set_velocity(0)
                    self.path_way = nil
                    self:set_animation("punch")
                    self.deposit_timer = (self.deposit_timer or 0) + dtime

                    if self.deposit_timer < 0.1 then
                        local node = core.get_node(self.target_chest)
                        if not self.original_chest_name then
                            self.original_chest_name = node.name
                            if node.name == "default:chest" or node.name == "default:chest_locked" then
                                core.swap_node(self.target_chest, {
                                    name = node.name .. "_open",
                                    param2 = node
                                        .param2
                                })
                                core.sound_play("default_chest_open",
                                    { pos = self.target_chest, gain = 0.3, max_hear_distance = 10 })
                            end
                        end
                    end

                    if self.deposit_timer >= 2.0 then
                        local meta = core.get_meta(self.target_chest)
                        local inv = meta:get_inventory()
                        local wood_amount = (self.inv.wood or 0)
                        if wood_amount > 0 then
                            local half_wood = math.floor(wood_amount / 2)
                            local boards = half_wood * 4
                            local remaining_wood = wood_amount - half_wood
                            if boards > 0 then inv:add_item("main", ItemStack("default:wood " .. boards)) end
                            if remaining_wood > 0 then
                                inv:add_item("main",
                                    ItemStack("default:tree " .. remaining_wood))
                            end
                            self.inv.wood = 0
                        end

                        -- Deposit all miscellaneous items (fruits, etc.)
                        for name, count in pairs(self.inv.items) do
                            if count > 0 then
                                inv:add_item("main", ItemStack(name .. " " .. count))
                                self.inv.items[name] = 0
                            end
                        end

                        if self.original_chest_name then
                            local node = core.get_node(self.target_chest)
                            core.swap_node(self.target_chest, {
                                name = self.original_chest_name,
                                param2 = node
                                    .param2
                            })
                            core.sound_play("default_chest_close",
                                { pos = self.target_chest, gain = 0.3, max_hear_distance = 10 })
                            self.original_chest_name = nil
                        end
                        self.target_chest = nil
                        self.stand_target = nil
                        self.deposit_timer = 0
                        self.search_timer = 1.0
                    end
                    return true -- STAY BUSY
                end
            end
        end

        -- B. Tree Interaction
        if self.target_tree then
            local tnode = core.get_node(self.target_tree)
            if tnode.name == "ignore" then
                -- Target is in an unloaded block, wait for it to load
            elseif core.get_item_group(tnode.name, "tree") == 0 then
                self.target_tree = nil
                self.stand_target = nil
            else
                local tree_center = {
                    x = self.target_tree.x + 0.5,
                    y = self.target_tree.y + 0.5,
                    z = self.target_tree.z +
                        0.5
                }
                local dist_2d = vector.distance({ x = pos.x, y = 0, z = pos.z }, {
                    x = tree_center.x,
                    y = 0,
                    z =
                        tree_center.z
                })
                local dist_y = math.abs(pos.y - self.target_tree.y)

                if dist_2d <= 4.0 and dist_y <= 15.0 then
                    set_state("Chopping tree")
                    self:set_velocity(0)
                    self.path_way = nil
                    self:set_animation("punch")
                    self.chopping_timer = (self.chopping_timer or 0) + dtime
                    if self.chopping_timer > 2.0 then
                        self.chopping_timer = 0
                        for y_offset = -1, 30 do
                            for x_offset = -3, 3 do
                                for z_offset = -3, 3 do
                                    local check_pos = {
                                        x = self.target_tree.x + x_offset,
                                        y = self.target_tree.y +
                                            y_offset,
                                        z = self.target_tree.z + z_offset
                                    }
                                    local node = core.get_node(check_pos)
                                    local is_tree = core.get_item_group(node.name, "tree") > 0
                                    local is_leaves = core.get_item_group(node.name, "leaves") > 0
                                    local is_fruit = core.get_item_group(node.name, "leafdecay") >
                                        0 -- Includes apples

                                    if is_tree or is_leaves or is_fruit then
                                        local drops = core.get_node_drops(node.name, "")
                                        for _, item in ipairs(drops) do
                                            local stack = ItemStack(item)
                                            local iname = stack:get_name()
                                            local is_sapling = core.get_item_group(iname, "sapling") > 0 or
                                                iname == "default:sapling" or
                                                iname == "default:jungle_sapling"

                                            if core.get_item_group(iname, "tree") > 0 or iname == "default:tree" then
                                                self.inv.wood = self.inv.wood + stack:get_count()
                                            elseif is_sapling then
                                                local name = stack:get_name()
                                                self.inv.saplings[name] = (self.inv.saplings[name] or 0) +
                                                    stack:get_count()
                                            else
                                                -- Collect fruits, but EXCLUDE leaf nodes (as items)
                                                -- Also exclude grass/shrubs if they somehow drop
                                                if core.get_item_group(iname, "leaves") == 0 and
                                                    core.get_item_group(iname, "grass") == 0 and
                                                    core.get_item_group(iname, "flora") == 0 then
                                                    self.inv.items[iname] = (self.inv.items[iname] or 0) +
                                                        stack:get_count()
                                                end
                                            end
                                        end
                                        core.remove_node(check_pos)
                                    end
                                end
                            end
                        end

                        -- 1. Identify all available saplings in inventory
                        local available_saplings = {}
                        for s_name, count in pairs(self.inv.saplings) do
                            if count > 0 then
                                table.insert(available_saplings, { name = s_name, count = count })
                            end
                        end

                        if #available_saplings > 0 then
                            -- 2. Scan a 5x5 area around the root for planting spots
                            -- (We prioritize the original trunk positions if possible)
                            local plant_spots = {}
                            for dx = -2, 2 do
                                for dz = -2, 2 do
                                    local p_pos = {
                                        x = self.target_tree.x + dx,
                                        y = self.target_tree.y,
                                        z = self.target_tree.z + dz
                                    }
                                    local pos_below = { x = p_pos.x, y = p_pos.y - 1, z = p_pos.z }
                                    local node_below = core.get_node(pos_below)
                                    local is_soil = core.get_item_group(node_below.name, "soil") > 0 or
                                                    core.get_item_group(node_below.name, "dirt") > 0
                                    
                                    if is_soil and core.get_node(p_pos).name == "air" then
                                        table.insert(plant_spots, p_pos)
                                    end
                                end
                            end

                            -- 3. Plant until spots or saplings run out
                            for _, spot in ipairs(plant_spots) do
                                -- Find first available sapling type
                                for i = 1, #available_saplings do
                                    local sap = available_saplings[i]
                                    if sap.count > 0 then
                                        core.set_node(spot, { name = sap.name })
                                        sap.count = sap.count - 1
                                        self.inv.saplings[sap.name] = self.inv.saplings[sap.name] - 1
                                        core.sound_play("default_place_node", { pos = spot, gain = 0.5 })
                                        break
                                    end
                                end
                            end
                        end

                        self.target_tree = nil
                        self.stand_target = nil
                        self.search_timer = 1.1
                    end
                    return true -- STAY BUSY
                end
            end
        end

        -- ==== 2. PATHFINDING LOGIC ====
        target = self.target_chest or self.stand_target or self.target_tree
        if target then
            self.path_timer = (self.path_timer or 0) + dtime

            -- If target changed, reset path
            if not self.last_target or not vector.equals(self.last_target, target) then
                self.path_way = nil
                self.last_target = vector.new(target)
                self.target_failures = 0
            end

            -- Update path if it doesn't exist or every 3 seconds
            if (not self.path_way or #self.path_way == 0) and self.path_timer > 3.0 then
                self.path_timer = 0
                self.path_way = core.find_path(pos, self.stand_target, 100, 1, 3, "AStar")

                if self.path_way then
                    self.greedy_timer = 0 -- Reset greedy if path found
                else
                    self.target_failures = self.target_failures + 1
                    self.greedy_timer = 5.0
                end

                if self.target_failures >= 4 then
                    -- Give up on this target — alles zuruecksetzen
                    local hash           = core.hash_node_position(target)
                    self.blacklist[hash] = core.get_gametime() + 60
                    self.target_tree     = nil
                    self.target_chest    = nil
                    self.stand_target    = nil -- gecachten Standplatz vergessen!
                    self.path_way        = nil
                    self.last_target     = nil -- Zwangsrecalc beim naechsten Target
                    self.target_failures = 0
                end
            end
        else
            self.path_way = nil
            self.path_timer = 3.1 -- Ready for next target
        end

        -- Move along the path if it exists
        if target and self.path_way and #self.path_way > 0 then
            set_state("Moving on path to " .. (self.target_chest and "chest" or "tree"))
            local next_p = self.path_way[1]
            -- Offset to center of node for actual movement
            local target_wp = { x = next_p.x + 0.5, y = next_p.y, z = next_p.z + 0.5 }
            local d2node = vector.distance({ x = pos.x, y = 0, z = pos.z }, { x = target_wp.x, y = 0, z = target_wp.z })

            -- Arrival threshold: Stop earlier if it's the final node to avoid getting stuck or lunging
            -- Arrival threshold: Final node needs to be reached more precisely
            local threshold = (#self.path_way == 1) and 1.2 or 0.6
            if d2node < threshold then
                table.remove(self.path_way, 1)
                self.stuck_timer = 0 -- Fortschritt! Stuck-Timer zuruecksetzen.
                self.last_pos = nil  -- Position-Referenz ebenfalls zuruecksetzen
                if #self.path_way == 0 then
                    self:set_velocity(0)
                end
            else
                local direction = vector.direction({ x = pos.x, y = 0, z = pos.z }, {
                    x = target_wp.x,
                    y = 0,
                    z =
                        target_wp.z
                })
                self.object:set_yaw(core.dir_to_yaw(direction))
                self:set_velocity(self.walk_velocity)
                self:set_animation("walk")

                -- Sprung bei haengerem Blockl: mit Cooldown, nicht jeden Tick
                self.jump_cooldown = (self.jump_cooldown or 0) - dtime
                if next_p.y > pos.y + 0.1 and self.jump_cooldown <= 0 then
                    self:do_jump()
                    self.jump_cooldown = 0.5
                end

                -- Stuck-Erkennung: nur wenn wir uns WIRKLICH nicht bewegen
                -- (Vergleich mit Position vor 3 Sekunden, nicht mit aktuellem Velocity)
                self.stuck_timer = (self.stuck_timer or 0) + dtime
                if self.stuck_timer >= 3.0 then
                    local last = self.last_pos
                    if last and vector.distance(pos, last) < 0.5 then
                        -- Wirklich festgesteckt: Pfad neu berechnen und Mobs Redo uebernehmen lassen
                        local next_p = self.path_way[1]
                        local n0 = core.get_node(next_p).name
                        local n1 = core.get_node({x=next_p.x, y=next_p.y+1, z=next_p.z}).name
                        local n2 = core.get_node({x=next_p.x, y=next_p.y+2, z=next_p.z}).name
                        
                        core.log("action", "[civi_npc] Path stuck at " .. core.pos_to_string(pos) .. "!")
                        core.log("action", "[civi_npc] Waypoint " .. core.pos_to_string(next_p) .. " nodes: L0="..n0..", L1="..n1..", L2="..n2)
                        core.log("action", "[civi_npc] Handing to Mobs API for 8s for recovery.")
                        
                        self.path_way = nil
                        self.path_timer = 3.1
                        self.target_failures = (self.target_failures or 0) + 1
                        self.mobs_takeover_timer = 8.0
                    end
                    -- Neue Referenzposition merken
                    self.last_pos    = vector.new(pos)
                    self.stuck_timer = 0
                end
            end
        end

        -- ==== 1.5 GREEDY FALLBACK MOVEMENT ====
        if target and not self.path_way and (self.greedy_timer or 0) > 0 then
            set_state("Greedy fallback to " .. (self.target_chest and "chest" or "tree"))
            self.greedy_timer = self.greedy_timer - dtime
            local direction = vector.direction({ x = pos.x, y = 0, z = pos.z }, { x = target.x, y = 0, z = target.z })
            self.object:set_yaw(core.dir_to_yaw(direction))
            self:set_velocity(self.walk_velocity)
            self:set_animation("walk")

            -- Simple Obstacle Jumping
            self.jump_cooldown = (self.jump_cooldown or 0) - dtime
            local scan_pos = vector.add(pos, vector.multiply(direction, 0.8))
            if core.get_node(scan_pos).name ~= "air" and self.jump_cooldown <= 0 then
                self:do_jump()
                self.jump_cooldown = 1.0
            end

            -- If we are in greedy mode and truly stuck, fail sooner
            self.stuck_timer = (self.stuck_timer or 0) + dtime
            if self.stuck_timer > 3.0 then
                if self.last_pos and vector.distance(pos, self.last_pos) < 0.2 then
                    local yaw = self.object:get_yaw()
                    local dir = core.yaw_to_dir(yaw)
                    local front = vector.round(vector.add(pos, dir))
                    local n0 = core.get_node(front).name
                    local n1 = core.get_node({x=front.x, y=front.y+1, z=front.z}).name
                    local n2 = core.get_node({x=front.x, y=front.y+2, z=front.z}).name

                    core.log("action", "[civi_npc] Greedy stuck at " .. core.pos_to_string(pos) .. "!")
                    core.log("action", "[civi_npc] Block in front " .. core.pos_to_string(front) .. " nodes: L0="..n0..", L1="..n1..", L2="..n2)
                    core.log("action", "[civi_npc] Handing to Mobs API for 8s for recovery.")

                    self.greedy_timer = 0    -- Stop greedy
                    self.target_failures = (self.target_failures or 0) + 1
                    self.mobs_takeover_timer = 8.0
                end
                self.last_pos = vector.new(pos)
                self.stuck_timer = 0
            end
        end

        -- ==== 3. SEARCH LOGIC (Tree or Chest) ====
        self.search_timer = (self.search_timer or 0) + dtime
        if not self.target_tree and not self.target_chest then
            if self.search_timer >= 1.0 then
                self.search_timer = 0

                -- 1. CHEST SEARCH (Priority if we have wood)
                if self.inv.wood > 0 then
                    set_state("Searching for chest (Wood: " .. tostring(self.inv.wood) .. ")")
                    local crange = 110
                    local cp1 = { x = pos.x - crange, y = pos.y - crange, z = pos.z - crange }
                    local cp2 = { x = pos.x + crange, y = pos.y + crange, z = pos.z + crange }
                    local now = core.get_gametime()
                    local should_log = (now - (self.last_search_log_time or 0)) >= 60

                    local chests = core.find_nodes_in_area(cp1, cp2, {
                        "default:chest", "default:chest_locked",
                        "default:chest_open", "default:chest_locked_open"
                    })

                    if should_log then
                        core.log("action", "[civi_npc] Lumberjack #" .. self._lumberjack_id .. " Chest search: found " .. #chests .. " chests")
                        self.last_search_log_time = now
                    end
                    if #chests > 0 then
                        table.sort(chests, function(a, b)
                            return vector.distance(pos, a) < vector.distance(pos, b)
                        end)

                        for _, chest_pos in ipairs(chests) do
                            local hash = core.hash_node_position(chest_pos)
                            -- Blacklist pruefen: Truhe die nicht erreichbar war ueberspringen
                            if self.blacklist[hash] and self.blacklist[hash] >= core.get_gametime() then
                                -- skip silently (logs only every 60s via search summary)
                            else
                                local stand_spot = find_standing_spot(chest_pos)
                                if stand_spot then
                                    self.target_chest = chest_pos
                                    self.stand_target = stand_spot
                                    self.path_timer = 3.1
                                    set_state("Moving to chest at " .. core.pos_to_string(chest_pos))
                                    return true
                                else
                                    self.blacklist[hash] = core.get_gametime() + 60
                                    core.log("action", "[civi_npc] Blacklisted unreachable chest at " .. core.pos_to_string(chest_pos))
                                end
                            end
                        end
                    end
                end

                -- 2. TREE SEARCH (Only if we have no wood)
                if self.inv.wood == 0 then
                    set_state("Searching for tree (Wood: 0)")
                    local range = 100
                    local p1 = { x = pos.x - range, y = pos.y - range, z = pos.z - range }
                    local p2 = { x = pos.x + range, y = pos.y + range, z = pos.z + range }
                    local found_nodes = core.find_nodes_in_area(p1, p2, { "group:tree" })

                    local roots = {} -- hash -> root_pos
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
                    for _, root in pairs(roots) do
                        table.insert(candidates, root)
                    end

                    if #candidates > 0 then
                        table.sort(candidates, function(a, b)
                            return vector.distance(pos, a) < vector.distance(pos, b)
                        end)

                        for _, found_root in ipairs(candidates) do
                            local stand_spot = find_standing_spot(found_root)
                            if stand_spot then
                                self.target_tree = found_root
                                self.stand_target = stand_spot
                                self.path_timer = 3.1 -- Force immediate pathfinding
                                return true
                            else
                                self.blacklist[core.hash_node_position(found_root)] = core.get_gametime() + 300
                                core.log("action", "[civi_npc] Blacklisted unreachable tree at " .. found_root.x .. "," .. found_root.y .. "," .. found_root.z)
                            end
                        end
                    end
                end
                self.stuck_timer = 0
            end
            -- Only set Idle state if we are actually doing nothing and not waiting for the search timer
            if self.search_timer < 0.9 then
                set_state("Idle (Waiting for Search)")
            else
                set_state("Idle / Return FALSE")
            end
            return false
        end

        -- Default fallback: execute normal Mobs AI if custom logic is done for this tick
        return true
    end,
})

-- Spawning rule
mobs:spawn({
    name = "civi_npc:lumberjack",
    nodes = { "default:dirt_with_grass" },
    min_light = 10,
    chance = 7000,
    active_object_count = 1,
    min_height = 0,
})


-- Spawn egg for the inventory
mobs:register_egg("civi_npc:lumberjack", "Lumberjack (myCraftCivi)", "civi_wood.png", 1)
