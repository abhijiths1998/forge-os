local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })
map("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Leave terminal mode" })
map("v", "<", "<gv")
map("v", ">", ">gv")

local function tel(cmd, opts)
  return function() require("telescope.builtin")[cmd](opts or {}) end
end

-- find
map("n", "<leader>ff", tel("find_files", { hidden = true }), { desc = "Files" })
map("n", "<leader>fg", tel("live_grep"), { desc = "Search text" })
map("n", "<leader>fb", tel("buffers"), { desc = "Buffers" })
map("n", "<leader>fr", tel("oldfiles"), { desc = "Recent files" })
map("n", "<leader>fh", tel("help_tags"), { desc = "Help" })
map("n", "<leader>fk", tel("keymaps"), { desc = "Keymaps" })
map("n", "<leader>fd", tel("diagnostics"), { desc = "Diagnostics" })

-- explorer
map("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "Explorer" })
map("n", "<leader>E", "<cmd>NvimTreeFindFile<cr>", { desc = "Explorer on this file" })

-- buffers
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Close buffer" })
map("n", "<leader>bn", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<leader>bp", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })

-- terminal
map("n", "<leader>tt", "<cmd>ToggleTerm direction=float<cr>", { desc = "Floating terminal" })
map("n", "<leader>th", "<cmd>ToggleTerm direction=horizontal<cr>", { desc = "Terminal below" })
map("n", "<leader>tv", "<cmd>ToggleTerm direction=vertical size=60<cr>", { desc = "Terminal beside" })

-- git (hunk keys are set per buffer by gitsigns)
map("n", "<leader>gg", tel("git_status"), { desc = "Changed files" })
map("n", "<leader>gc", tel("git_commits"), { desc = "Commits" })

-- help
map("n", "<leader>ht", "<cmd>ForgeTutorial<cr>", { desc = "Tutorial" })
map("n", "<leader>hk", "<cmd>WhichKey<cr>", { desc = "All keys" })
map("n", "<leader>hh", "<cmd>checkhealth<cr>", { desc = "Health" })

-- code
map({ "n", "v" }, "<leader>cf", function() require("conform").format({ lsp_format = "fallback" }) end,
  { desc = "Format" })
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit" })
