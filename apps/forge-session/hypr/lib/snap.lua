-- Windows-style snapping for floating windows: Super+Left/Right fill a half
-- of the screen, Super+Up maximises, Super+Down puts the window back the
-- way it was (or minimises it if it wasn't snapped). Tiled windows move
-- within the layout instead.
local S = {}
local saved = {} -- window address -> { x, y, w, h } from before it snapped
local GAP = 12

local function usable(mon)
    local scale = mon.scale or 1
    local r = mon.reserved or {}
    local x = mon.x + (r.left or 0)
    local y = mon.y + (r.top or 0)
    local w = mon.width / scale - (r.left or 0) - (r.right or 0)
    local h = mon.height / scale - (r.top or 0) - (r.bottom or 0)
    return x, y, w, h
end

local function place(win, x, y, w, h)
    hl.dispatch(hl.dsp.window.resize({ x = math.floor(w), y = math.floor(h), window = win }))
    hl.dispatch(hl.dsp.window.move({ x = math.floor(x), y = math.floor(y), window = win }))
end

function S.snap(dir)
    local win = hl.get_active_window()
    if not win then return end
    if not win.floating then
        hl.dispatch(hl.dsp.window.move({ direction = dir }))
        return
    end
    if win.fullscreen and win.fullscreen > 0 then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" }))
    end
    local mon = win.monitor or hl.get_active_monitor()
    if not mon then return end
    if not saved[win.address] then
        saved[win.address] = { win.at.x, win.at.y, win.size.x, win.size.y }
    end
    local x, y, w, h = usable(mon)
    local half = (w - 3 * GAP) / 2
    if dir == "left" then
        place(win, x + GAP, y + GAP, half, h - 2 * GAP)
    else
        place(win, x + 2 * GAP + half, y + GAP, half, h - 2 * GAP)
    end
end

function S.maximise()
    local win = hl.get_active_window()
    if not win then return end
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
end

function S.restore_or_minimise()
    local win = hl.get_active_window()
    if not win then return end
    if win.fullscreen and win.fullscreen > 0 then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" }))
        return
    end
    local g = saved[win.address]
    if g and win.floating then
        saved[win.address] = nil
        place(win, g[1], g[2], g[3], g[4])
        return
    end
    -- Minimise: windows wait on a hidden workspace (Super+Shift+Down shows it).
    hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false }))
end

hl.on("window.destroy", function(win) if win then saved[win.address] = nil end end)

return S
