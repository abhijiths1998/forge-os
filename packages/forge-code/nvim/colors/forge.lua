-- The Forge colourscheme, built at startup from ~/.config/forge/theme.json.
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
vim.g.colors_name = "forge"

local p = require("forge.palette").get()
vim.o.background = p.dark and "dark" or "light"

local clear = vim.g.forge_transparent ~= false
local bg = clear and "NONE" or p.bg
local bg_alt = clear and "NONE" or p.bg_alt

local hl = {
  Normal = { fg = p.fg, bg = bg },
  NormalNC = { fg = p.fg, bg = bg },
  NormalFloat = { fg = p.fg, bg = bg_alt },
  FloatBorder = { fg = p.accent, bg = bg_alt },
  FloatTitle = { fg = p.accent, bold = true },
  SignColumn = { bg = bg },
  LineNr = { fg = p.comment },
  CursorLineNr = { fg = p.accent, bold = true },
  CursorLine = { bg = p.bg_alt },
  ColorColumn = { bg = p.bg_alt },
  Cursor = { fg = p.bg, bg = p.accent },
  Visual = { bg = p.sel },
  Search = { fg = p.bg, bg = p.yellow },
  IncSearch = { fg = p.bg, bg = p.orange },
  CurSearch = { fg = p.bg, bg = p.orange },
  MatchParen = { fg = p.accent, bold = true, underline = true },
  VertSplit = { fg = p.border },
  WinSeparator = { fg = p.border },
  StatusLine = { fg = p.fg, bg = p.bg_alt },
  StatusLineNC = { fg = p.comment, bg = p.bg_alt },
  Pmenu = { fg = p.fg, bg = p.bg_alt },
  PmenuSel = { fg = p.fg, bg = p.sel },
  PmenuSbar = { bg = p.bg_hl },
  PmenuThumb = { bg = p.accent },
  Folded = { fg = p.comment, bg = p.bg_alt },
  NonText = { fg = p.border },
  Whitespace = { fg = p.border },
  EndOfBuffer = { fg = p.bg },
  Directory = { fg = p.accent },
  Title = { fg = p.accent, bold = true },
  ErrorMsg = { fg = p.red, bold = true },
  WarningMsg = { fg = p.yellow },
  MoreMsg = { fg = p.green },
  Question = { fg = p.accent },
  WildMenu = { bg = p.sel },
  TabLine = { fg = p.comment, bg = p.bg_alt },
  TabLineSel = { fg = p.fg, bg = p.sel },
  TabLineFill = { bg = p.bg_alt },

  Comment = { fg = p.comment, italic = true },
  Constant = { fg = p.orange },
  String = { fg = p.green },
  Character = { fg = p.green },
  Number = { fg = p.orange },
  Boolean = { fg = p.orange },
  Identifier = { fg = p.fg },
  Function = { fg = p.accent },
  Statement = { fg = p.magenta },
  Operator = { fg = p.cyan },
  Keyword = { fg = p.magenta },
  PreProc = { fg = p.cyan },
  Type = { fg = p.yellow },
  Special = { fg = p.cyan },
  Underlined = { underline = true },
  Error = { fg = p.red },
  Todo = { fg = p.bg, bg = p.yellow, bold = true },

  ["@variable"] = { fg = p.fg },
  ["@variable.builtin"] = { fg = p.red },
  ["@variable.parameter"] = { fg = p.orange },
  ["@property"] = { fg = p.cyan },
  ["@constructor"] = { fg = p.yellow },
  ["@module"] = { fg = p.yellow },
  ["@tag"] = { fg = p.magenta },
  ["@tag.attribute"] = { fg = p.yellow },
  ["@markup.heading"] = { fg = p.accent, bold = true },
  ["@markup.strong"] = { bold = true },
  ["@markup.italic"] = { italic = true },
  ["@markup.link.url"] = { fg = p.cyan, underline = true },
  ["@markup.raw"] = { fg = p.green },

  DiagnosticError = { fg = p.red },
  DiagnosticWarn = { fg = p.yellow },
  DiagnosticInfo = { fg = p.accent },
  DiagnosticHint = { fg = p.cyan },
  DiagnosticUnderlineError = { undercurl = true, sp = p.red },
  DiagnosticUnderlineWarn = { undercurl = true, sp = p.yellow },
  DiagnosticUnderlineInfo = { undercurl = true, sp = p.accent },
  DiagnosticUnderlineHint = { undercurl = true, sp = p.cyan },

  DiffAdd = { bg = p.dark and "#22352b" or "#d6efdc" },
  DiffChange = { bg = p.dark and "#2a2f45" or "#dde1f5" },
  DiffDelete = { bg = p.dark and "#3d2630" or "#f3d6da" },
  DiffText = { bg = p.sel },
  Added = { fg = p.green },
  Changed = { fg = p.yellow },
  Removed = { fg = p.red },
  GitSignsAdd = { fg = p.green },
  GitSignsChange = { fg = p.yellow },
  GitSignsDelete = { fg = p.red },

  TelescopeBorder = { fg = p.accent, bg = bg_alt },
  TelescopeSelection = { bg = p.sel },
  TelescopeMatching = { fg = p.accent, bold = true },
  WhichKey = { fg = p.accent },
  WhichKeyDesc = { fg = p.fg },
  WhichKeyGroup = { fg = p.magenta },
  NvimTreeNormal = { fg = p.fg, bg = bg },
  NvimTreeFolderName = { fg = p.accent },
  NvimTreeRootFolder = { fg = p.accent, bold = true },
  BlinkCmpMenu = { fg = p.fg, bg = bg_alt },
  BlinkCmpMenuBorder = { fg = p.accent, bg = bg_alt },
  BlinkCmpMenuSelection = { bg = p.sel },
}
hl.Delimiter = { fg = p.comment }

for name, spec in pairs(hl) do
  vim.api.nvim_set_hl(0, name, spec)
end

vim.g.terminal_color_0 = p.bg_hl
vim.g.terminal_color_1 = p.red
vim.g.terminal_color_2 = p.green
vim.g.terminal_color_3 = p.yellow
vim.g.terminal_color_4 = p.accent
vim.g.terminal_color_5 = p.magenta
vim.g.terminal_color_6 = p.cyan
vim.g.terminal_color_7 = p.fg
