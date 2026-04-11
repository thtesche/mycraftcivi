-- Gemeinsame Funktionen für alle NPCs in myCraftCivi

local common = {}

--- Findet einen gültigen Platz zum Stehen in der Nähe einer Zielposition.
-- @param target_pos Die Position, an der gearbeitet werden soll.
-- @return Eine Position {x, y, z} oder nil.
function common.find_standing_spot(target_pos)
    local function is_passable(name)
        local def = core.registered_nodes[name]
        if not def or not def.walkable then return true end
        if core.get_item_group(name, "leaves") > 0 then return true end
        return false
    end

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

    for _, off in ipairs(neighbor_offsets) do
        local cx = target_pos.x + off.x
        local cz = target_pos.z + off.z
        for dy = 3, -5, -1 do
            local cy      = target_pos.y + dy
            local n_here  = core.get_node({ x = cx, y = cy, z = cz }).name
            local n_below = core.get_node({ x = cx, y = cy - 1, z = cz }).name
            local n_above = core.get_node({ x = cx, y = cy + 1, z = cz }).name

            if is_passable(n_here) and is_solid_ground(n_below) and is_passable(n_above) then
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
    return nil
end

--- Setzt den Status des NPCs und loggt Änderungen.
-- @param self Die Entity (Mob).
-- @param state_field Der Name des Feldes im Mob (z.B. "_lumberjack_state").
-- @param id_field Der Name des ID-Feldes (z.B. "_lumberjack_id").
-- @param prefix Prefix für das Log (z.B. "Lumberjack").
-- @param new_state Der neue Status-String.
function common.set_state(self, state_field, id_field, prefix, new_state)
    local function is_boring(s)
        return s == "Idle / Return FALSE" or
            s == "Idle (Waiting for Search)" or
            (s and s:sub(1, 9) == "Searching")
    end

    if self[state_field] ~= new_state then
        if not (is_boring(self[state_field]) and is_boring(new_state)) then
            core.log("action", "[mycraftcivi] " .. prefix .. " #" .. (self[id_field] or "?") .. " State: " ..
                tostring(self[state_field]) .. " -> " .. new_state)
        end
        self[state_field] = new_state
    end
end

return common
