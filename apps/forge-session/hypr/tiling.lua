-- Tiling, per workspace. New users start with it off: windows float, and
-- Super+arrows snap them, as on Windows. Super+Shift+T (or the Control
-- Center, or `forge tile`) turns it on for the workspace you're on.
--
-- The choice is kept in ~/.local/state/forge/tiling.json, which forged
-- reads and writes too:  { "default": false, "workspaces": { "2": true } }
-- After forged writes it, it runs `hyprctl eval 'forge.tiling.reload()'`.
local T = {}
local PATH = forge.state .. "/forge/tiling.json"

function T.reload()
    local s = forge.json.read(PATH) or {}
    T.default = s.default == true
    T.workspaces = type(s.workspaces) == "table" and s.workspaces or {}
    T.sync_rules()
    T.apply_all()
end

function T.enabled(id)
    local v = T.workspaces[tostring(id)]
    if v == nil then return T.default end
    return v
end

local function save()
    forge.json.write(PATH, { default = T.default, workspaces = T.workspaces })
end

-- Float (tiling off) or tile (tiling on) the windows already there.
-- Windows that a rule floats (dialogs, pickers) stay floating either way.
function T.apply(ws)
    if not ws or ws.special then return end
    local on = T.enabled(ws.id)
    for _, win in ipairs(hl.get_workspace_windows(ws.id)) do
        if on and win.floating and not T.rule_floated(win) then
            hl.dispatch(hl.dsp.window.float({ action = "unset", window = win }))
        elseif not on and not win.floating then
            hl.dispatch(hl.dsp.window.float({ action = "set", window = win }))
            hl.dispatch(hl.dsp.window.center({ window = win }))
        end
    end
end

function T.apply_all()
    if not hl.get_workspaces then return end
    for _, ws in ipairs(hl.get_workspaces()) do T.apply(ws) end
end

-- Windows a rule floated keep a tag, so turning tiling on leaves them be.
function T.rule_floated(win)
    for _, tag in ipairs(type(win.tags) == "table" and win.tags or {}) do
        if tag == "forge-float" then return true end
    end
    return false
end

function T.set(id, on)
    T.workspaces[tostring(id)] = on
    save()
    T.sync_rules()
    T.apply(hl.get_workspace(id))
end

function T.toggle()
    local ws = hl.get_active_workspace()
    if not ws then return end
    local on = not T.enabled(ws.id)
    T.set(ws.id, on)
    forge.hint(on and "Tiling on for this workspace" or "Tiling off: windows float", 1800)
end

-- New windows follow their workspace's choice from the start, before
-- they're shown, so nothing jumps: a rule floats every new window while
-- tiling is off by default, and one rule per workspace that differs from
-- the default says otherwise (later rules win).
local float_all = hl.window_rule({ name = "forge-tiling-default", match = { class = ".*" }, float = true })
local per_ws = {}

function T.sync_rules()
    float_all:set_enabled(not T.default)
    for id, on in pairs(T.workspaces) do
        local differs = (on ~= T.default)
        local r = per_ws[id]
        if differs and not r then
            local spec = { name = "forge-tiling-ws-" .. id, match = { workspace = tostring(id) } }
            if on then spec.tile = true else spec.float = true end
            per_ws[id] = { rule = hl.window_rule(spec), on = on }
        elseif r then
            if r.on ~= on then
                r.rule:set_enabled(false)
                local spec = { name = "forge-tiling-ws-" .. id .. (on and "-t" or "-f"), match = { workspace = tostring(id) } }
                if on then spec.tile = true else spec.float = true end
                per_ws[id] = { rule = hl.window_rule(spec), on = on }
            else
                r.rule:set_enabled(differs)
            end
        end
    end
end

-- A window moved to another workspace takes that workspace's choice.
hl.on("window.move_to_workspace", function(win)
    if not win or not win.workspace or win.workspace.special then return end
    local on = T.enabled(win.workspace.id)
    if on == win.floating and not T.rule_floated(win) then
        hl.dispatch(hl.dsp.window.float({ action = on and "unset" or "set", window = win }))
    end
end)

forge.tiling = T
T.default, T.workspaces = false, {}
local s = forge.json.read(PATH)
if s then
    T.default = s.default == true
    T.workspaces = type(s.workspaces) == "table" and s.workspaces or {}
end
T.sync_rules()
