local o = vim.opt

o.number = true
o.relativenumber = true
o.cursorline = true
o.signcolumn = "yes"
o.termguicolors = true
o.mouse = "a"
o.clipboard = "unnamedplus"
o.ignorecase = true
o.smartcase = true
o.splitright = true
o.splitbelow = true
o.scrolloff = 6
o.undofile = true
o.updatetime = 250
o.timeoutlen = 400
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.breakindent = true
o.list = true
o.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
o.fillchars = { eob = " " }
o.winborder = "rounded"
o.showmode = false -- lualine shows it
o.completeopt = { "menu", "menuone", "noselect" }

-- Two spaces suit these.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "lua", "json", "yaml", "toml", "markdown", "qml", "dart", "sh", "bash" },
  callback = function()
    vim.bo.shiftwidth = 2
    vim.bo.tabstop = 2
  end,
})

-- Neovide: it applies its own opacity, so the colourscheme keeps solid colours.
if vim.g.neovide then
  vim.g.neovide_opacity = 0.85
  vim.g.neovide_window_blurred = true
  vim.g.neovide_cursor_vfx_mode = "pixiedust"
  vim.g.forge_transparent = false
end

-- Terminal transparency: on unless the user turns it off with
-- `vim.g.forge_transparent = false` (or `:ForgeTransparent`).
if vim.g.forge_transparent == nil then
  vim.g.forge_transparent = true
end
vim.api.nvim_create_user_command("ForgeTransparent", function()
  vim.g.forge_transparent = not vim.g.forge_transparent
  vim.cmd.colorscheme("forge")
end, { desc = "Toggle the transparent background" })
