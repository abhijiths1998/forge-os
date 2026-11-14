-- Checks Forge's Hyprland config without Hyprland: loads every module
-- against a stub `hl` and fails when
--   * a bind doesn't go through forge.bind (so it'd have no category),
--   * a bind has no category or description,
--   * two binds in the same submap use the same keys,
--   * the JSON helper doesn't round-trip.
-- Run: lua tests/check-binds.lua [path/to/hypr]  (from apps/forge-session)
local dir = arg[1] or "hypr"
local failures = 0
local function fail(msg) failures = failures + 1; io.stderr:write("FAIL: " .. msg .. "\n") end

-- The stub: every table call returns a callable stub; binds are recorded.
local raw_binds = {}
local function stub() return setmetatable({}, { __index = function() return stub() end, __call = function() return stub() end }) end
hl = setmetatable({}, { __index = function() return stub() end })
hl.bind = function(keys, _dsp, opts)
    raw_binds[#raw_binds + 1] = { keys = keys, description = opts and opts.description }
    return stub()
end
hl.define_submap = function(_, fn) fn() end
hl.get_workspaces = function() return {} end

-- Absolute requires point at the installed path; map them to this tree.
local real_require = require
require = function(name)
    local local_path = name:gsub("^/usr/share/forge/hypr", dir)
    if local_path:match("%.lua$") then
        local chunk = assert(loadfile(local_path))
        return chunk()
    end
    return real_require(name)
end
os.execute = function() return true end
io.popen = function() return nil end

-- Isolated state: no user files, no theme.
os.getenv = (function(get) return function(k)
    if k == "HOME" or k == "XDG_CONFIG_HOME" or k == "XDG_STATE_HOME" then return "/nonexistent" end
    return get(k)
end end)(os.getenv)

local ok, err = pcall(require, dir .. "/forge.lua")
if not ok then fail("loading forge.lua: " .. tostring(err)) end

-- Every hl.bind came from forge.bind (the recorded list matches).
local recorded = forge and forge.binds and forge.binds.list or {}
if #recorded ~= #raw_binds then
    fail(string.format("%d binds made, %d through forge.bind", #raw_binds, #recorded))
end
for _, b in ipairs(raw_binds) do
    if not (b.description and b.description:match("^%[[^%]]+%] %S")) then
        fail("bind without '[Category] description': " .. b.keys)
    end
end

-- No two binds on the same keys in the same submap.
local seen = {}
for _, b in ipairs(recorded) do
    local id = (b.submap or "") .. "|" .. b.id
    if seen[id] then fail("keys bound twice: " .. b.keys .. " (" .. seen[id] .. " / " .. b.description .. ")") end
    seen[id] = b.description
end

-- No raw hl.bind in the module sources outside lib/bind.lua.
for _, name in ipairs({ "env", "theme", "look", "input", "rules", "tiling", "game", "keybinds", "autostart", "lib/snap" }) do
    local f = assert(io.open(dir .. "/" .. name .. ".lua"))
    local src = f:read("a"); f:close()
    if src:find("hl%.bind%(") then fail(name .. ".lua calls hl.bind directly; use forge.bind") end
end

-- JSON round trip.
local json = forge.json
local v = json.decode('{"default": false, "workspaces": {"2": true}, "a": [1, 2.5, "x\\n"], "n": null}')
if not (v and v.default == false and v.workspaces["2"] == true and v.a[2] == 2.5 and v.a[3] == "x\n") then
    fail("json.decode")
end
local again = json.decode(json.encode(v))
if not (again and again.workspaces["2"] == true and again.a[3] == "x\n") then fail("json round trip") end

if failures > 0 then
    io.stderr:write(failures .. " problem(s)\n")
    os.exit(1)
end
print(string.format("ok: %d binds, every one with a category and a description", #recorded))
