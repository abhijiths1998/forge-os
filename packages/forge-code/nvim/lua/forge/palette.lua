-- Colours from ~/.config/forge/theme.json (the Theming Kit's file). Keys used:
-- dark (bool), accent ("#rrggbb"), tintHue (0-360). A missing or broken file
-- gives the Forge Glass dark defaults.

local M = {}

local function hex_to_rgb(h)
  h = h:gsub("^#", "")
  return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
end

local function rgb_to_hex(r, g, b)
  return string.format("#%02x%02x%02x", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

local function hsl(h, s, l)
  h, s, l = (h % 360) / 360, s / 100, l / 100
  local function f(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return rgb_to_hex(f(p, q, h + 1 / 3) * 255, f(p, q, h) * 255, f(p, q, h - 1 / 3) * 255)
end

--- Mix colour `a` into `b`; t = 0 gives b, t = 1 gives a.
local function mix(a, b, t)
  local ar, ag, ab = hex_to_rgb(a)
  local br, bg, bb = hex_to_rgb(b)
  return rgb_to_hex(br + (ar - br) * t, bg + (ag - bg) * t, bb + (ab - bb) * t)
end

local function read_theme()
  local path = (vim.env.XDG_CONFIG_HOME or (vim.env.HOME or "") .. "/.config") .. "/forge/theme.json"
  local f = io.open(path, "r")
  if not f then return {} end
  local text = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, text)
  return (ok and type(data) == "table") and data or {}
end

function M.get()
  local t = read_theme()
  local dark = t.dark ~= false
  local accent = (type(t.accent) == "string" and t.accent:match("^#%x%x%x%x%x%x$")) or "#7F8EF5"
  local hue = tonumber(t.tintHue) or 232

  local p = { dark = dark, accent = accent:lower(), hue = hue }
  if dark then
    p.bg = hsl(hue, 23, 13.7) -- #1b1d2b at the default hue
    p.bg_alt = hsl(hue, 23, 17)
    p.bg_hl = hsl(hue, 23, 22)
    p.border = hsl(hue, 20, 32)
    p.fg = "#f4f5fb"
    p.comment = mix(p.fg, p.bg, 0.42)
    p.red, p.orange, p.yellow = hsl(355, 85, 72), hsl(25, 85, 70), hsl(45, 80, 72)
    p.green, p.cyan, p.magenta = hsl(140, 55, 68), hsl(185, 65, 68), hsl(300, 60, 76)
  else
    p.bg = hsl(hue, 30, 96)
    p.bg_alt = hsl(hue, 30, 92)
    p.bg_hl = hsl(hue, 30, 86)
    p.border = hsl(hue, 20, 70)
    p.fg = hsl(hue, 25, 18)
    p.comment = mix(p.fg, p.bg, 0.5)
    p.red, p.orange, p.yellow = hsl(355, 70, 45), hsl(22, 80, 42), hsl(42, 80, 34)
    p.green, p.cyan, p.magenta = hsl(140, 50, 30), hsl(190, 70, 30), hsl(300, 45, 42)
  end
  p.sel = mix(p.accent, p.bg, 0.28)
  return p
end

M.mix = mix
return M
