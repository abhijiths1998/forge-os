-- Plugin specs. Every plugin lives under <root>/lazy (put there by the
-- package); the versions are pinned in lazy-lock.json. Nothing here may need
-- the network.

return {
  { "folke/lazy.nvim" },

  { "echasnovski/mini.icons", lazy = true,
    config = function()
      require("mini.icons").setup()
      require("mini.icons").mock_nvim_web_devicons()
    end },

  -- Treesitter (the `main` branch). Parsers are compiled when the package is
  -- built and sit in <root>/parsers, so nothing is installed at runtime.
  { "nvim-treesitter/nvim-treesitter", lazy = false,
    config = function()
      -- Default install dir (~/.local/share/forge-code/site, writable) so
      -- :checkhealth is happy; the shipped parsers are on the runtimepath.
      require("nvim-treesitter").setup()
      vim.treesitter.language.register("qmljs", "qml")
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          local lang = vim.treesitter.language.get_lang(ev.match)
          if lang and pcall(vim.treesitter.start, ev.buf, lang) then
            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end },

  { "neovim/nvim-lspconfig", lazy = false },

  { "saghen/blink.cmp", lazy = false,
    opts = {
      keymap = { preset = "enter" },
      -- The Rust matcher would need a binary download; the Lua one is fine.
      fuzzy = { implementation = "lua", prebuilt_binaries = { download = false } },
      completion = { documentation = { auto_show = true, auto_show_delay_ms = 300 } },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      signature = { enabled = true },
    } },

  { "mfussenegger/nvim-lint", event = { "BufReadPost", "BufNewFile" },
    config = function()
      local lint = require("lint")
      local wanted = { sh = "shellcheck", bash = "shellcheck", sql = "sqlfluff" }
      lint.linters_by_ft = {}
      for ft, linter in pairs(wanted) do
        if vim.fn.executable(linter) == 1 then lint.linters_by_ft[ft] = { linter } end
      end
      vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
        callback = function() lint.try_lint() end,
      })
    end },

  { "stevearc/conform.nvim", event = "BufWritePre", cmd = "ConformInfo",
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_organize_imports", "ruff_format" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        sql = { "sqlfluff" },
        json = { "prettier" },
        jsonc = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        -- C/C++, Rust, Dart, QML and TOML fall back to their language server.
      },
      format_on_save = { timeout_ms = 2000, lsp_format = "fallback" },
    } },

  { "nvim-telescope/telescope.nvim", cmd = "Telescope",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim" },
    },
    config = function()
      require("telescope").setup({ defaults = { sorting_strategy = "ascending",
        layout_config = { prompt_position = "top" } } })
      pcall(require("telescope").load_extension, "fzf")
    end },

  { "folke/which-key.nvim", event = "VeryLazy",
    opts = {
      preset = "modern",
      spec = {
        { "<leader>f", group = "find" },
        { "<leader>g", group = "git" },
        { "<leader>l", group = "lsp" },
        { "<leader>t", group = "terminal" },
        { "<leader>e", group = "explorer" },
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>h", group = "help" },
      },
    } },

  { "nvim-tree/nvim-tree.lua", cmd = { "NvimTreeToggle", "NvimTreeFindFile" },
    opts = {
      view = { width = 34 },
      renderer = { group_empty = true },
      filters = { dotfiles = false },
      git = { ignore = false },
    } },

  { "lewis6991/gitsigns.nvim", event = { "BufReadPost", "BufNewFile" },
    opts = {
      on_attach = function(buf)
        local gs = require("gitsigns")
        local function map(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc }) end
        map("]h", function() gs.nav_hunk("next") end, "Next hunk")
        map("[h", function() gs.nav_hunk("prev") end, "Previous hunk")
        map("<leader>gp", gs.preview_hunk, "Preview hunk")
        map("<leader>gs", gs.stage_hunk, "Stage hunk")
        map("<leader>gr", gs.reset_hunk, "Reset hunk")
        map("<leader>gb", gs.blame_line, "Blame line")
        map("<leader>gd", gs.diffthis, "Diff this")
      end,
    } },

  { "akinsho/toggleterm.nvim", cmd = "ToggleTerm",
    keys = { { "<C-\\>", desc = "Terminal" } },
    opts = { open_mapping = [[<C-\>]], direction = "float", float_opts = { border = "curved" } } },

  { "nvim-lualine/lualine.nvim", event = "VeryLazy",
    opts = function()
      local p = require("forge.palette").get()
      local function mode(c) return { a = { fg = p.bg, bg = c, gui = "bold" }, b = { fg = p.fg, bg = p.bg_hl },
        c = { fg = p.fg, bg = "NONE" } } end
      return {
        options = {
          theme = {
            normal = mode(p.accent), insert = mode(p.green), visual = mode(p.magenta),
            replace = mode(p.red), command = mode(p.yellow), inactive = mode(p.border),
          },
          component_separators = "",
          section_separators = { left = "", right = "" },
          globalstatus = true,
        },
      }
    end },
}
