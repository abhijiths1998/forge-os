-- forge.bind: every Forge keybind goes through here.
--
--   forge.bind("Windows", "SUPER + Q", "Close window", hl.dsp.window.close())
--
-- The description reaches `hyprctl binds -j` as "[Windows] Close window":
-- the desktop shortcut panel, the Super+/ cheat sheet, the which-key popup
-- and Forge Settings' shortcuts page all read it from there, so they never
-- go stale. tests/check-binds.lua fails the build for a bind without a
-- category or description, or two binds on the same keys.
local M = {}

M.list = {} -- every bind made, in order: { category, keys, description, submap }
M.submap = nil

local function normalise(keys)
    local parts = {}
    for p in keys:gmatch("[^+]+") do
        parts[#parts + 1] = p:gsub("^%s+", ""):gsub("%s+$", ""):upper()
    end
    local key = table.remove(parts)
    table.sort(parts)
    parts[#parts + 1] = key
    return table.concat(parts, "+")
end
M.normalise = normalise

function M.bind(category, keys, description, dispatcher, opts)
    assert(type(category) == "string" and category ~= "", "forge.bind: no category for " .. tostring(keys))
    assert(type(description) == "string" and description ~= "", "forge.bind: no description for " .. tostring(keys))
    opts = opts or {}
    opts.description = "[" .. category .. "] " .. description
    M.list[#M.list + 1] = {
        category = category, keys = keys, id = normalise(keys),
        description = description, submap = M.submap,
    }
    return hl.bind(keys, dispatcher, opts)
end

-- A submap whose binds are recorded under its name. `fn` makes the binds.
function M.submap_define(name, fn)
    hl.define_submap(name, function()
        local outer = M.submap
        M.submap = name
        fn()
        M.submap = outer
    end)
end

return M
