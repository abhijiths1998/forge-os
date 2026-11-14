-- Forge Code: Forge OS's Neovim setup. Started by /usr/bin/forge-code with
-- `-u` pointing here and NVIM_APPNAME=forge-code, so ~/.config/nvim is never
-- read. Nothing is downloaded: every plugin is already under ./lazy.

local root = vim.env.FORGE_CODE_ROOT or "/usr/share/forge/nvim"
vim.g.forge_root = root

-- Our own runtime files (colors/, lua/) and the compiled parsers.
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(root .. "/lazy/lazy.nvim")
vim.opt.runtimepath:append(root .. "/parsers")
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site")

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("forge.options")

require("lazy").setup("forge.plugins", {
  root = root .. "/lazy",
  lockfile = root .. "/lazy-lock.json",
  -- Read-only install: no cloning, no update checks, no file watching.
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false, notify = false },
  -- Keep our own entry on the runtimepath (lazy would reset it).
  performance = { rtp = { reset = false } },
  rocks = { enabled = false },
  readme = { enabled = false },
  ui = { border = "rounded" },
})

require("forge.keymaps")
require("forge.lsp")
require("forge.tutorial")

vim.cmd.colorscheme("forge")
