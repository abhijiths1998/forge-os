-- The Forge theme, from ~/.config/forge/theme.json (the Theming Kit,
-- `forge theme` and `forge glass` write it; forge-theme-sync then runs
-- `hyprctl reload`). Missing keys fall back to Forge Glass.
--
-- KWin's liquid glass had refraction (lens, bevel, inner bending, colour
-- split); Hyprland's blur doesn't. The lens becomes a thin lit edge on each
-- window, and the rest is left out (docs/HYPRLAND.md, section 3).
local defaults = {
    dark = true, accent = "#7F8EF5", tintHue = 235, tintStrength = 1.0,
    blur = 7, saturation = 1.7, lensWidth = 2.5, lensStrength = 10, grain = 0,
    windowOpacity = 41, menuOpacity = 58, terminalOpacity = 64,
    cornerRadius = 14, cornerShape = 2.4, shadow = 1.0,
}

local file = forge.json.read(forge.config .. "/forge/theme.json") or {}
local t = {}
for k, v in pairs(defaults) do
    local x = file[k]
    t[k] = (type(x) == type(v)) and x or v
end

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- "#rrggbb" -> r, g, b (0-255)
local function rgb(hex)
    local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)")
    if not r then return 127, 142, 245 end
    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function rgba(r, g, b, a)
    return string.format("rgba(%02x%02x%02x%02x)", r, g, b, math.floor(clamp(a, 0, 1) * 255 + 0.5))
end

local ar, ag, ab = rgb(t.accent)
t.accent_rgba = function(a) return rgba(ar, ag, ab, a) end
t.rgba = rgba

-- Blur: KWin's 1-15 strength to Hyprland's kernel size and passes.
t.blur_size = math.max(2, math.floor(t.blur * 1.2 + 0.5))
t.blur_passes = clamp(1 + math.ceil(t.blur / 5), 1, 4)
t.vibrancy = clamp((t.saturation - 1) * 0.35, 0, 1)
t.noise = clamp(t.grain * 0.004, 0, 0.1)

-- The lens: a lit edge, as wide as the lens and as bright as its strength.
t.edge_width = (t.lensStrength > 0) and clamp(math.floor(t.lensWidth / 2 + 0.5), 1, 3) or 0
local edge = clamp(t.lensStrength / 20, 0, 1) * (t.dark and 0.55 or 0.75)
t.edge_active = { colors = { rgba(255, 255, 255, edge), t.accent_rgba(edge * 0.6), rgba(255, 255, 255, edge * 0.3) }, angle = 45 }
t.edge_inactive = rgba(255, 255, 255, edge * 0.45)

t.shadow_colour = rgba(0, 0, 0, (t.dark and 0.45 or 0.22) * t.shadow)

forge.theme = t
