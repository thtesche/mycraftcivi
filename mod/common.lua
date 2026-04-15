-- Gemeinsame Funktionen für alle NPCs in myCraftCivi

local common = {}

--- Findet alle gültigen Plätze zum Stehen in der Nähe einer Zielposition.
-- @param target_pos Die Position, an der gearbeitet werden soll.
-- @return Eine Tabelle mit Positionen {x, y, z}.
function common.find_all_standing_spots(target_pos)
    local function is_passable(name)
        local def = core.registered_nodes[name]
        if not def or not def.walkable then return true end
        -- Blätter sind zwar passierbar für den Pfadfinder, aber wir wollen nicht darin STEHEN.
        -- Daher stufen wir sie hier als "nicht passierbar" für die Standplatz-Wahl ein.
        if core.get_item_group(name, "leaves") > 0 then return false end
        if core.get_item_group(name, "tree") > 0 then return false end
        return false
    end

    local function is_solid_ground(name)
        local def = core.registered_nodes[name]
        if not def or not def.walkable then return false end
        -- Wir stehen nicht auf Bäumen oder Blättern
        if core.get_item_group(name, "tree") > 0 then return false end
        if core.get_item_group(name, "leaves") > 0 then return false end
        return true
    end

    local neighbor_offsets = {
        -- Distanz 2 (Bevorzugt)
        { x = 2, z = 0 }, { x = -2, z = 0 }, { x = 0, z = 2 }, { x = 0, z = -2 },
        { x = 2, z = 1 }, { x = 2, z = -1 }, { x = -2, z = 1 }, { x = -2, z = -1 },
        { x = 1, z = 2 }, { x = 1, z = -2 }, { x = -1, z = 2 }, { x = -1, z = -2 },
        { x = 2, z = 2 }, { x = -2, z = -2 }, { x = 2, z = -2 }, { x = -2, z = 2 },
        -- Distanz 1 (Fallback)
        { x = 1, z = 0 }, { x = -1, z = 0 }, { x = 0, z = 1 }, { x = 0, z = -1 },
        { x = 1, z = 1 }, { x = -1, z = -1 }, { x = 1, z = -1 }, { x = -1, z = 1 }
    }

    local spots = {}
    -- Suche von der Zielhöhe aus nach oben und unten (Priorität auf dy=0)
    for _, dy in ipairs({ 0, -1, 1, -2, 2, -3, 3, -4, -5 }) do
        local found_at_this_height = false
        for _, off in ipairs(neighbor_offsets) do
            local cx = target_pos.x + off.x
            local cz = target_pos.z + off.z
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
                    table.insert(spots, { x = cx, y = cy, z = cz })
                    found_at_this_height = true
                end
            end
        end
        -- Wenn wir Spots auf dieser "idealen" Höhe gefunden haben, brechen wir die vertikale Suche ab.
        -- So garantieren wir, dass nur die besten Höhen zurückgegeben werden.
        if found_at_this_height then
            break
        end
    end
    return spots
end

--- Findet einen gültigen Platz zum Stehen (Wrapper für find_all_standing_spots).
function common.find_standing_spot(target_pos)
    local spots = common.find_all_standing_spots(target_pos)
    return spots[1]
end

--- Setzt den Status des NPCs und loggt Änderungen.
-- @param self Die Entity (Mob).
-- @param state_field Der Name des Feldes im Mob (z.B. "_lumberjack_state").
-- @param id_field Der Name des ID-Feldes (z.B. "_lumberjack_id").
-- @param prefix Prefix für das Log (z.B. "Lumberjack").
-- @param new_state Der neue Status-String.
function common.set_state(self, state_field, id_field, prefix, new_state)
    local function is_boring(s)
        if not s then return true end
        return s:find("Idle") or s:find("Searching") or s:find("Standing")
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
