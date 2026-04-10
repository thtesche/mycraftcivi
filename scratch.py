import os

def check_structure():
    with open('mod/init.lua', 'r') as f:
        lines = f.readlines()
    
    # Let's locate the blocks
    do_custom_start = -1
    chest_start = -1
    tree_start = -1
    path_start = -1
    greedy_start = -1
    search_start = -1
    do_custom_end = -1
    
    for i, line in enumerate(lines):
        if "do_custom = function(" in line: do_custom_start = i
        if "        -- A. Chest Interaction" in line: chest_start = i
        if "        -- B. Tree Interaction" in line: tree_start = i
        if "        -- ==== 2. PATHFINDING LOGIC ====" in line: path_start = i
        if "        -- ==== 1.5 GREEDY FALLBACK MOVEMENT ====" in line: greedy_start = i
        if "        -- ==== 3. SEARCH LOGIC (Tree or Chest) ====" in line: search_start = i
        if line.strip() == "return true" and search_start != -1 and do_custom_end == -1:
            pass # wait, let's find the end of do_custom
        if lines[i].strip() == "})" and lines[i-1].strip() == "end,":
            do_custom_end = i - 1
            
    print(f"do_custom: {do_custom_start} to {do_custom_end}")
    print(f"chest: {chest_start}")
    print(f"tree: {tree_start}")
    print(f"path: {path_start}")
    print(f"greedy: {greedy_start}")
    print(f"search: {search_start}")
    
    # Extract blocks
    if chest_start != -1 and tree_start != -1:
        chest_lines = lines[chest_start:tree_start]
        tree_lines = lines[tree_start:path_start]
        path_lines = lines[path_start:greedy_start]
        greedy_lines = lines[greedy_start:search_start]
        
        # for search end, let's find the default fallback "return true" at the end of do_custom
        search_end = -1
        for i in range(search_start, do_custom_end):
            if "        -- Default fallback" in lines[i]:
                search_end = i
                break
        search_lines = lines[search_start:search_end]
        
        # State helper
        state_helper = """
local function set_state(self, new_state)
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
"""
        
        def fix_state(block):
            return [line.replace("set_state(", "set_state(self, ") for line in block]
            
        chest_lines = fix_state(chest_lines)
        tree_lines = fix_state(tree_lines)
        path_lines = fix_state(path_lines)
        greedy_lines = fix_state(greedy_lines)
        search_lines = fix_state(search_lines)
        
        chest_func = ["local function lumberjack_chest_interaction(self, dtime, pos)\n"] + chest_lines + ["    return false\n", "end\n\n"]
        tree_func = ["local function lumberjack_tree_interaction(self, dtime, pos)\n"] + tree_lines + ["    return false\n", "end\n\n"]
        path_func = ["local function lumberjack_pathfinding(self, dtime, pos, target)\n"] + ["    if not target then return false end\n"] + path_lines[1:] + ["    if target and self.path_way and #self.path_way > 0 then\n", "        return true\n", "    end\n", "    return false\n", "end\n\n"]
        
        # Greedy
        greedy_func = ["local function lumberjack_greedy_movement(self, dtime, pos, target)\n"] + greedy_lines + ["    if target and not self.path_way and (self.greedy_timer or 0) > 0 then\n", "        return true\n", "    end\n", "    return false\n", "end\n\n"]
        
        # Search end cleanup
        search_lines = search_lines[:-4] # removing the if self.search_timer < 0.9 the state setting blocks at the end
        search_func = ["local function lumberjack_search_logic(self, dtime, pos)\n"] + search_lines + [
            "    if self.search_timer < 0.9 then\n",
            "        set_state(self, \"Idle (Waiting for Search)\")\n",
            "    else\n",
            "        set_state(self, \"Idle / Return FALSE\")\n",
            "    end\n",
            "    return false\n",
            "end\n\n"
        ]
        
        new_do_custom = [
            "    do_custom = function(self, dtime)\n",
            "        if not self.inv then\n",
            "            lumberjack_count = lumberjack_count + 1\n",
            "            self._lumberjack_id = lumberjack_count\n",
            "            self.inv = { wood = 0, saplings = {}, items = {} }\n",
            "            self.blacklist = {} -- [pos_hash] = expiration_time\n",
            "            self.target_failures = 0\n",
            "            self._lumberjack_state = \"Init\"\n",
            "            self.last_search_log_time = 0\n",
            "        end\n",
            "        if not self._lumberjack_id then\n",
            "            lumberjack_count = lumberjack_count + 1\n",
            "            self._lumberjack_id = lumberjack_count\n",
            "        end\n",
            "        if type(self.inv.saplings) == \"number\" then self.inv.saplings = {} end\n",
            "        if not self.inv.items then self.inv.items = {} end\n",
            "        self.greedy_timer = self.greedy_timer or 0\n",
            "        self.blacklist = self.blacklist or {}\n",
            "        self.target_failures = self.target_failures or 0\n",
            "\n",
            "        local pos = self.object:get_pos()\n",
            "        if not pos then return false end\n",
            "\n",
            "        self.mobs_takeover_timer = (self.mobs_takeover_timer or 0) - dtime\n",
            "        if self.mobs_takeover_timer > 0 then\n",
            "            set_state(self, \"Mobs API takeover (stuck recovery)\")\n",
            "            return true\n",
            "        end\n",
            "\n",
            "        if lumberjack_chest_interaction(self, dtime, pos) then return true end\n",
            "        if lumberjack_tree_interaction(self, dtime, pos) then return true end\n",
            "\n",
            "        local target = self.target_chest or self.stand_target or self.target_tree\n",
            "        if target then\n",
            "            if lumberjack_pathfinding(self, dtime, pos, target) then return true end\n",
            "            if lumberjack_greedy_movement(self, dtime, pos, target) then return true end\n",
            "            return true\n",
            "        end\n",
            "\n",
            "        if lumberjack_search_logic(self, dtime, pos) then return true end\n",
            "\n",
            "        return true\n",
            "    end,\n"
        ]
        
        # Wait, do we have any local functions inside do_custom that were omitted?
        # Yes, find_standing_spot is outside do_custom! So that's safe.
        # But wait, search_logic uses find_standing_spot! So search_logic must be defined AFTER find_standing_spot.
        
        # Let's rebuild lines:
        reg_start = -1
        for i, l in enumerate(lines):
            if "mobs:register_mob(" in l:
                reg_start = i
                break
                
        top_lines = lines[:reg_start]
        bottom_lines = lines[do_custom_end:] # This includes "    }," and so on
        
        mob_header = lines[reg_start:do_custom_start]
        
        final_lines = top_lines + [state_helper] + chest_func + tree_func + path_func + greedy_func + search_func + mob_header + new_do_custom + bottom_lines
        
        with open('mod/init_refactored.lua', 'w') as f:
            f.writelines(final_lines)
            
        print("Refactored to mod/init_refactored.lua")

check_structure()
