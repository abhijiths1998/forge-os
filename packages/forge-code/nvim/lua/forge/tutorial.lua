-- First-run tutorial: "the 10 keys that matter". Shown once (a marker file in
-- the state dir), then on demand with :ForgeTutorial or <Space>ht.

local lines = {
  "  Welcome to Forge Code",
  "  =====================",
  "",
  "  Neovim has modes. These ten keys are enough to start.",
  "",
  "    i            Insert mode: type text (the cursor becomes a bar)",
  "    Esc          back to Normal mode, where keys are commands",
  "    h j k l      move left, down, up, right (the arrow keys work too)",
  "    u            undo (Ctrl+r redoes)",
  "    /text        search; n for the next match, Esc clears it",
  "    :w           save",
  "    :q           quit (:q! quits without saving, :wq does both)",
  "    Space        the leader menu: press it and wait, a list of keys appears",
  "    Space f f    find a file by name",
  "    Space e      the file explorer (the same key closes it)",
  "",
  "  That is the ten. Also handy:",
  "",
  "    Space f g    search text in all files",
  "    Space t t    a terminal (Ctrl+\\ too; Esc Esc to leave it)",
  "    Space l ...  language server: rename, code action, symbols",
  "    Space h t    show this page again (or :ForgeTutorial)",
  "",
  "  Formatting happens on save. Your own ~/.config/nvim is never touched:",
  "  Forge Code keeps its data in ~/.local/share/forge-code.",
  "",
  "  Close this page with :bd",
}

local function show()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "Forge Code tutorial")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_set_current_buf(buf)
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.list = false
end

vim.api.nvim_create_user_command("ForgeTutorial", show, { desc = "Show the Forge Code tutorial" })

local marker = vim.fn.stdpath("state") .. "/tutorial-seen"

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    -- Only for a person at a screen opening an empty editor; a launch with
    -- files, or a headless run, leaves the marker alone.
    if #vim.api.nvim_list_uis() == 0 or vim.fn.argc() > 0 then return end
    if vim.uv.fs_stat(marker) then return end
    show()
    vim.fn.mkdir(vim.fn.fnamemodify(marker, ":h"), "p")
    local f = io.open(marker, "w")
    if f then f:write("1\n") f:close() end
  end,
})
