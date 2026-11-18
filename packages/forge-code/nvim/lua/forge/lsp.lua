-- Language servers come from Arch packages (no Mason: the ISO is offline).
-- A server is enabled only if its program is installed, so a missing one is
-- silent instead of an error on every file.
-- nvim-lspconfig supplies the defaults (lsp/*.lua on the runtimepath); this
-- only adds the few we change and turns the servers on.

local function exe(name)
  return vim.fn.executable(name) == 1
end

local function first(...)
  for _, path in ipairs({ ... }) do
    if exe(path) then return path end
  end
end

vim.lsp.config("*", {
  capabilities = require("blink.cmp").get_lsp_capabilities(),
})

local servers = {
  lua_ls = "lua-language-server",
  pyright = "pyright-langserver",
  ruff = "ruff",
  clangd = "clangd",
  rust_analyzer = "rust-analyzer",
  bashls = "bash-language-server",
  taplo = "taplo",
  yamlls = "yaml-language-server",
  jsonls = "vscode-json-language-server",
  marksman = "marksman",
}

vim.lsp.config("lua_ls", {
  settings = { Lua = { runtime = { version = "LuaJIT" }, workspace = { checkThirdParty = false },
    diagnostics = { globals = { "vim" } }, telemetry = { enable = false } } },
})

-- basedpyright is not in the repos; use it only if the user installed it.
if not exe("pyright-langserver") and exe("basedpyright-langserver") then
  servers.pyright = nil
  servers.basedpyright = "basedpyright-langserver"
end

for server, program in pairs(servers) do
  if exe(program) then vim.lsp.enable(server) end
end

-- QML: qt6-declarative ships qmlls under /usr/lib/qt6/bin.
local qmlls = first("qmlls", "qmlls6", "/usr/lib/qt6/bin/qmlls")
if qmlls then
  vim.lsp.config("qmlls", {
    cmd = { qmlls },
    filetypes = { "qml", "qmljs" },
    root_markers = { ".qmlls.ini", ".git" },
  })
  vim.lsp.enable("qmlls")
end

-- Dart and Flutter: `dart language-server` from the SDK, if there is one.
if exe("dart") then
  vim.lsp.config("dartls", {
    cmd = { "dart", "language-server", "--protocol=lsp" },
    filetypes = { "dart" },
    root_markers = { "pubspec.yaml", ".git" },
  })
  vim.lsp.enable("dartls")
end

vim.diagnostic.config({
  virtual_text = { spacing = 2, prefix = "●" },
  severity_sort = true,
  float = { border = "rounded" },
})

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    local tb = function(f) return function() require("telescope.builtin")[f]() end end
    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("gD", vim.lsp.buf.declaration, "Go to declaration")
    map("gr", tb("lsp_references"), "References")
    map("gi", vim.lsp.buf.implementation, "Implementation")
    map("<leader>la", vim.lsp.buf.code_action, "Code action")
    map("<leader>lr", vim.lsp.buf.rename, "Rename")
    map("<leader>ld", vim.diagnostic.open_float, "Line diagnostics")
    map("<leader>lD", tb("diagnostics"), "All diagnostics")
    map("<leader>ls", tb("lsp_document_symbols"), "Symbols")
    map("<leader>lf", function() vim.lsp.buf.format({ async = true }) end, "Format")
    map("<leader>lh", function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = ev.buf }), { bufnr = ev.buf })
    end, "Toggle inlay hints")
    map("<leader>li", "<cmd>checkhealth vim.lsp<cr>", "LSP info")
  end,
})
